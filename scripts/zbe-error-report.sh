#!/bin/bash
# Daily health/error report for the zcashexplorer host.
#
# Run from root's crontab (needs docker + /var/log/nginx). Writes a dated
# report to $REPORT_LOG and exits non-zero if any threshold is breached, so
# cron surfaces it. Set KUMA_PUSH_URL to also report up/down to Uptime Kuma.
#
# Usage: zbe-error-report.sh [hours]   (default 24)
set -uo pipefail

HOURS="${1:-24}"
REPORT_LOG="${REPORT_LOG:-/var/log/zbe-daily-report.log}"
KUMA_PUSH_URL="${KUMA_PUSH_URL:-}"

DISK_PCT_MAX=85
SWAP_PCT_MAX=50
LOG_BYTES_MAX=$((1024 * 1024 * 1024))   # 1 GiB per container json.log
HTTP_5XX_PCT_MAX=1
MAINNET_TIP_AGE_MAX=1800                # 30 min
TESTNET_TIP_AGE_MAX=10800               # 3 h

ALERTS=()
alert() { ALERTS+=("$1"); }
section() { printf '\n== %s\n' "$1"; }

# --- application errors -----------------------------------------------------
container_errors() {
  local name="$1"
  docker logs --since "${HOURS}h" "$name" 2>&1 |
    grep -oE '\*\* \([A-Za-z.]+Error\) [^(]*|exited in: GenServer\.call\([^,]+, \{[^}]*\}' |
    cut -c1-110 | sort | uniq -c | sort -rn | head -15
}

# --- chain tip freshness ----------------------------------------------------
tip_age() {   # port -> seconds since the tip block was mined, or "?"
  local port="$1" height time
  height=$(curl -s --max-time 10 -X POST -H 'Content-Type: application/json' \
    -d '{"jsonrpc":"2.0","id":1,"method":"getblockcount","params":[]}' \
    "http://127.0.0.1:${port}/" | sed -n 's/.*"result":\([0-9]*\).*/\1/p')
  [ -z "$height" ] && { echo "?"; return; }
  time=$(curl -s --max-time 10 -X POST -H 'Content-Type: application/json' \
    -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"getblock\",\"params\":[\"${height}\",1]}" \
    "http://127.0.0.1:${port}/" | sed -n 's/.*"time":\([0-9]*\).*/\1/p' | head -1)
  [ -z "$time" ] && { echo "?"; return; }
  echo "$(( $(date +%s) - time ))"
}

check_tip() {
  local label="$1" port="$2" max="$3" age
  age=$(tip_age "$port")
  if [ "$age" = "?" ]; then
    echo "$label: RPC en :$port no responde"
    alert "$label: RPC en :$port no responde"
  else
    echo "$label: tip hace $((age / 60)) min"
    [ "$age" -gt "$max" ] && alert "$label: cadena detenida hace $((age / 60)) min (max $((max / 60)))"
  fi
}

{
  echo "########################################################################"
  echo "# Reporte zcashexplorer - $(date -u '+%Y-%m-%d %H:%M UTC') - ultimas ${HOURS}h"
  echo "########################################################################"

  section "Errores zbe_main"
  container_errors zbe_main
  section "Errores zbe_testnet"
  container_errors zbe_testnet

  section "HTTP 5xx (nginx, log actual)"
  if [ -r /var/log/nginx/access.log ]; then
    awk '{t++} $9 ~ /^5/ {e++; path=$7; sub(/\?.*/,"",path);
          gsub(/[0-9a-f]{64}/,":hash",path); gsub(/\/address\/[A-Za-z0-9]+/,"/address/:addr",path);
          c[path]++}
         END { pct = t ? e*100/t : 0;
               printf "total=%d  5xx=%d  (%.2f%%)\n", t, e, pct;
               for (p in c) printf "%8d %s\n", c[p], p | "sort -rn | head -10";
               exit (pct > PCTMAX) }' PCTMAX="$HTTP_5XX_PCT_MAX" /var/log/nginx/access.log ||
      alert "HTTP 5xx por encima del ${HTTP_5XX_PCT_MAX}%"
  else
    echo "(sin acceso a /var/log/nginx/access.log)"
  fi

  section "Cadena"
  check_tip "mainnet" 8232 "$MAINNET_TIP_AGE_MAX"
  check_tip "testnet" 18232 "$TESTNET_TIP_AGE_MAX"

  section "Recursos"
  df -h / | tail -1
  disk_pct=$(df --output=pcent / | tail -1 | tr -dc '0-9')
  [ "${disk_pct:-0}" -gt "$DISK_PCT_MAX" ] && alert "Disco / al ${disk_pct}% (max ${DISK_PCT_MAX}%)"

  free -h | sed -n '1,3p'
  read -r swap_total swap_used < <(free | awk '/^Swap:/ {print $2, $3}')
  if [ "${swap_total:-0}" -gt 0 ]; then
    swap_pct=$((swap_used * 100 / swap_total))
    [ "$swap_pct" -gt "$SWAP_PCT_MAX" ] && alert "Swap al ${swap_pct}% (max ${SWAP_PCT_MAX}%)"
  fi

  section "Memoria por contenedor"
  docker stats --no-stream --format '{{.Name}}\t{{.MemUsage}}\t{{.MemPerc}}' 2>/dev/null

  section "Tamano de logs docker"
  while read -r size path; do
    name=$(docker ps -a --format '{{.ID}} {{.Names}}' |
           grep -F "$(basename "$(dirname "$path")" | cut -c1-12)" | awk '{print $2}')
    echo "$(numfmt --to=iec "$size")  ${name:-$path}"
    [ "$size" -gt "$LOG_BYTES_MAX" ] && alert "Log de ${name:-$path} en $(numfmt --to=iec "$size") (max 1G) - revisar rotacion"
  done < <(find /var/lib/docker/containers -name '*-json.log' -printf '%s %p\n' 2>/dev/null | sort -rn | head -5)

  section "Reinicios y OOM"
  docker ps -a --format '{{.Names}}\t{{.Status}}\t{{.RunningFor}}'
  if dmesg -T 2>/dev/null | grep -qi 'Out of memory: Killed process'; then
    oom=$(dmesg -T 2>/dev/null | grep -i 'Out of memory: Killed process' | tail -1)
    echo "$oom"
    # dmesg is not time-bounded; only alert while the kernel ring buffer still shows it
    alert "OOM kill en el ring buffer del kernel: ${oom:0:120}"
  else
    echo "sin OOM kills en el ring buffer"
  fi

  section "RESUMEN"
  if [ ${#ALERTS[@]} -eq 0 ]; then
    echo "OK - sin alertas"
  else
    printf 'ALERTA: %s\n' "${ALERTS[@]}"
  fi
} 2>&1 | tee -a "$REPORT_LOG"

# Keep the report log from becoming the next runaway log.
tail -c 5242880 "$REPORT_LOG" > "${REPORT_LOG}.tmp" && mv "${REPORT_LOG}.tmp" "$REPORT_LOG"

if [ -n "$KUMA_PUSH_URL" ]; then
  if [ ${#ALERTS[@]} -eq 0 ]; then
    curl -m 10 -sS "${KUMA_PUSH_URL}&status=up&msg=OK" >/dev/null
  else
    curl -m 10 -sS --data-urlencode "msg=${ALERTS[0]}" "${KUMA_PUSH_URL}&status=down" >/dev/null
  fi
fi

[ ${#ALERTS[@]} -eq 0 ]
