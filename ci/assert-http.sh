#!/usr/bin/env bash
# Assert that a URL answers 200 and its body contains every given string.
#
# Usage: ci/assert-http.sh <url> [expected-substring ...]
set -uo pipefail

url="$1"
shift

body_file="$(mktemp)"
status="$(curl -sS -L -o "$body_file" -w '%{http_code}' --max-time 60 "$url" || echo 000)"

fail() {
  echo "FAIL  $url"
  echo "      $1"
  echo "      --- first 60 lines of the body ---"
  head -n 60 "$body_file" | sed 's/^/      /'
  rm -f "$body_file"
  exit 1
}

[ "$status" = "200" ] || fail "expected HTTP 200, got $status"

for expected in "$@"; do
  grep -qF -- "$expected" "$body_file" || fail "body does not contain: $expected"
done

echo "ok    $url (200, $# substring(s) matched)"
rm -f "$body_file"
