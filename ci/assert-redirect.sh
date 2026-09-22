#!/usr/bin/env bash
# Assert that a URL answers with a redirect to exactly one destination.
#
# The transparent-address search defect was a redirect to the wrong page, and
# the page it pointed at then returned 500 — so following the redirect is not
# enough, the destination itself has to be asserted.
#
# Usage: ci/assert-redirect.sh <url> <expected-location>
set -uo pipefail

url="$1"
expected="$2"

read -r status location < <(
  curl -sS -o /dev/null -w '%{http_code} %{redirect_url}\n' --max-time 30 "$url" ||
    echo "000 -"
)

case "$status" in
  30[1278]) ;;
  *)
    echo "FAIL  $url"
    echo "      expected a redirect, got HTTP $status"
    exit 1
    ;;
esac

if [ "$location" != "$expected" ]; then
  echo "FAIL  $url"
  echo "      expected -> $expected"
  echo "      got      -> $location"
  exit 1
fi

echo "ok    $url ($status -> $location)"
