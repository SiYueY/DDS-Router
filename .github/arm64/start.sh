#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
unset LD_PRELOAD
export LD_LIBRARY_PATH="$root/lib"
if (( $# == 0 )); then
    set -- -c "$root/ddsrouter.yaml"
fi
exec "$root/bin/ddsrouter" "$@"
