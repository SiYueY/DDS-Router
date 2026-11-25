#!/usr/bin/env bash
# Verify all four native artifacts and assemble the release bundle.
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=.github/appimage/common.sh
source "$script_dir/common.sh"

[[ $# == 2 ]] || die "Usage: aggregate.sh ARTIFACTS OUTPUT"
require_commands sha256sum readelf zip unzip install
input="$(realpath "$1")"
output="$(realpath -m "$2")"
bundle="ddsrouter-$DDSROUTER_VERSION"
mkdir -p "$output"
[[ ! -e "$output/$bundle.zip" && ! -e "$output/$bundle.zip.sha256" ]] ||
    die "Release bundle already exists: $output/$bundle.zip"

stage="$(mktemp -d "$output/.aggregate.XXXXXX")"
trap 'rm -rf -- "$stage"' EXIT

for distro in humble jazzy; do
    for arch in amd64 arm64; do
        name="$bundle-$distro-$arch.AppImage"
        dir="$input/${name%.AppImage}"
        [[ -f "$dir/$name" && -f "$dir/$name.sha256" ]] ||
            die "Missing image or checksum: $name"

        # Bind the digest to exactly this file, not arbitrary checksum entries.
        expected="$(cd "$dir" && sha256sum -- "$name")"
        [[ "$(cat "$dir/$name.sha256")" == "$expected" ]] ||
            die "Invalid checksum: $name"

        case "$arch" in
            amd64) machine='Advanced Micro Devices X86-64' ;;
            arm64) machine=AArch64 ;;
        esac
        check_appimage "$dir/$name" "$machine"

        # GitHub artifact transport does not preserve executable permissions.
        install -D -m 0755 "$dir/$name" "$stage/$bundle/$distro/$arch/$name"
        log "Verified $name"
    done
done

(
    cd "$stage"
    zip -q -r -X "$bundle.zip" "$bundle"
    unzip -t "$bundle.zip"
    sha256sum "$bundle.zip" > "$bundle.zip.sha256"
)
mv -- "$stage/$bundle.zip" "$stage/$bundle.zip.sha256" "$output/"
log "Release bundle: $output/$bundle.zip"
