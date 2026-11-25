#!/usr/bin/env bash
# Common build metadata, diagnostics and platform validation.

export LC_ALL=C
export TZ=UTC

readonly DDSROUTER_VERSION=2.3.0

log() {
    printf '[%s] [%s] %s\n' "$(date -u +%FT%TZ)" "${0##*/}" "$*" >&2
}

die() {
    log "ERROR: $*"
    exit 1
}

require_commands() {
    local command
    for command in "$@"; do
        command -v "$command" >/dev/null || die "Required command not found: $command"
    done
}

# These values are consumed by the individual build and packaging scripts.
# shellcheck disable=SC2034
detect_platform() {
    local ID VERSION_ID
    # shellcheck disable=SC1091
    source /etc/os-release

    case "$ID:$VERSION_ID" in
        ubuntu:22.04) distro=humble ;;
        ubuntu:24.04) distro=jazzy ;;
        *) die "Unsupported OS: $ID $VERSION_ID" ;;
    esac

    case "$(uname -m)" in
        x86_64)
            arch=amd64
            runtime_arch=x86_64
            elf_machine='Advanced Micro Devices X86-64'
            ;;
        aarch64)
            arch=arm64
            runtime_arch=aarch64
            elf_machine=AArch64
            ;;
        *) die "Unsupported architecture: $(uname -m)" ;;
    esac

    artifact="ddsrouter-$DDSROUTER_VERSION-$distro-$arch"
}

# LD_LIBRARY_PATH is colon-delimited and ldd reports paths in whitespace fields.
require_build_path() {
    local path="$1"
    [[ "$path" != *:* && "$path" != *[[:space:]]* ]] ||
        die "Build path must not contain whitespace or a colon: $path"
}

check_elf() {
    local path="$1" expected_machine="$2" header actual_machine
    header="$(readelf -h -- "$path")" || die "Invalid ELF file: $path"
    actual_machine="$(awk -F: '/^[[:space:]]*Machine:/ {sub(/^[[:space:]]+/, "", $2); print $2}' <<< "$header")"
    [[ "$actual_machine" == "$expected_machine" ]] ||
        die "Wrong ELF architecture: $path ($actual_machine; expected $expected_machine)"
}

# The Type 2 marker follows the ELF identification bytes.
check_appimage() {
    local path="$1" expected_machine="$2" magic
    check_elf "$path" "$expected_machine"
    magic="$(od -An -tx1 -j8 -N3 -- "$path" | tr -d '[:space:]')"
    [[ "$magic" == 414902 ]] || die "Invalid Type 2 AppImage marker: $path"
}
