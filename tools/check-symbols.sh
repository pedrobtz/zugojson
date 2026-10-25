#!/bin/sh
# Fails if the built shared object links a symbol CRAN's compiled-code
# check rejects: anything that can end the R process or write to the
# process's own streams. The stock Goose runtime uses all of these, and
# goose_r_runtime.c exists to keep them out, so a Goose bump or a new
# runtime piece in goose_vendor.c must not bring one back.
#
#   tools/check-symbols.sh path/to/zugojson.so

set -eu
so=${1:?usage: $0 <shared object>}
bad=$(nm -u "$so" | awk '{print $2}' | sed 's/@.*//' |
  grep -E '^_?(abort|exit|_exit|_Exit|quick_exit|stdout|stderr|__stdoutp|__stderrp|printf|puts|putchar|fprintf|vprintf|fputs|fwrite|sprintf|vsprintf|rand|srand|random|srandom)$' || true)
if [ -n "$bad" ]; then
  echo "forbidden symbols in $so:" >&2
  echo "$bad" >&2
  exit 1
fi
echo "no forbidden symbols in $so"
