#!/usr/bin/env bash
# Download fixed tool releases and verify their expected SHA256 digests.
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=.github/appimage/common.sh
source "$script_dir/common.sh"

[[ $# == 1 ]] || die "Usage: tools.sh TOOLS_DIRECTORY"
require_commands curl sha256sum readelf
detect_platform
dest="$(realpath -m "$1")"
mkdir -p "$dest"
tool_version=1.9.1
runtime_version=20251108
case "$arch" in
    amd64)
        tool_hash=ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0
        runtime_hash=2fca8b443c92510f1483a883f60061ad09b46b978b2631c807cd873a47ec260d
        ;;
    arm64)
        tool_hash=f0837e7448a0c1e4e650a93bb3e85802546e60654ef287576f46c71c126a9158
        runtime_hash=00cbdfcf917cc6c0ff6d3347d59e0ca1f7f45a6df1a428a0d6d8a78664d87444
        ;;
esac

download() {
    local url="$1" path="$2" hash="$3"
    local partial
    partial="$(mktemp "$path.part.XXXXXX")"
    log "Downloading $url"
    if ! curl --fail --silent --show-error --location --retry 3 --connect-timeout 20 \
        --max-time 300 --output "$partial" "$url"; then
        rm -f -- "$partial"
        die "Download failed: $url"
    fi
    if ! printf '%s  %s\n' "$hash" "$partial" | sha256sum --check --strict; then
        rm -f -- "$partial"
        die "Checksum mismatch: $url"
    fi
    check_elf "$partial" "$elf_machine"
    chmod 0755 "$partial"
    mv -- "$partial" "$path"
}

download "https://github.com/AppImage/appimagetool/releases/download/$tool_version/appimagetool-$runtime_arch.AppImage" \
    "$dest/appimagetool.AppImage" "$tool_hash"
download "https://github.com/AppImage/type2-runtime/releases/download/$runtime_version/runtime-$runtime_arch" \
    "$dest/runtime" "$runtime_hash"
# Reject a runtime requiring a dynamic interpreter or shared libraries.
readelf -l "$dest/runtime" > "$dest/runtime-headers.txt"
readelf -d "$dest/runtime" > "$dest/runtime-dynamic.txt"
if grep -q INTERP "$dest/runtime-headers.txt" || grep -q '(NEEDED)' "$dest/runtime-dynamic.txt"; then
    die "Runtime is not statically linked"
fi
printf 'appimagetool %s %s\ntype2-runtime %s %s\n' \
    "$tool_version" "$tool_hash" "$runtime_version" "$runtime_hash" > "$dest/tools-info.txt"
log "Verified packaging tool and static runtime"
