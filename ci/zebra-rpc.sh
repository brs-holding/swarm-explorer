#!/usr/bin/env bash
# Call a JSON-RPC method on the Zebra container started by the CI job.
#
# The cookie file is mode 0600 and owned by uid 10001 inside the container, so
# the call is made from inside that container (docker exec runs as root there)
# rather than from the runner. `curl -u` takes the file's whole
# "__cookie__:<secret>" contents as user:password. The secret is never echoed.
#
# Usage: ci/zebra-rpc.sh <container> <method> [json-params]
set -euo pipefail

container="$1"
method="$2"
params="${3:-[]}"

docker exec "$container" sh -c \
  "curl -sS --fail-with-body --max-time 120 \
     -u \"\$(cat /zebra-cookie/.cookie)\" \
     -H 'Content-Type: application/json' \
     --data '{\"jsonrpc\":\"1.0\",\"id\":\"ci\",\"method\":\"${method}\",\"params\":${params}}' \
     http://127.0.0.1:18232/"
