#!/usr/bin/env bash
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
work="$(realpath "${1:?WORK_DIRECTORY required}")"
out="$(realpath -m "${2:?OUTPUT_DIRECTORY required}")"
prefix="$work/install"
name=ddsrouter-2.3.0-ubuntu24.04-arm64
bundle="$out/$name"
mkdir -p "$bundle/bin" "$bundle/lib" "$bundle/licenses"
binary="$(find "$prefix" -type f -name ddsrouter -executable -print -quit)"
test -n "$binary"
cp "$binary" "$bundle/bin/ddsrouter"
readelf -h "$binary" | grep -q 'AArch64'

# Resolve the complete ELF dependency closure using only the private install
# and runner system libraries. Keep glibc and the toolchain runtime on target.
export LD_LIBRARY_PATH="$(find "$prefix" -type f -name '*.so*' -printf '%h\n' | sort -u | paste -sd:)"
ldd "$binary" | tee "$out/linked-libraries.txt"
if grep -q 'not found' "$out/linked-libraries.txt"; then exit 1; fi
while read -r soname path; do
    case "$soname" in
        libc.so.*|libm.so.*|libpthread.so.*|libdl.so.*|librt.so.*|libgcc_s.so.*|libstdc++.so.*|ld-linux-*) continue ;;
    esac
    cp -L "$path" "$bundle/lib/$soname"
done < <(awk '$2 == "=>" && $3 ~ /^\// {print $1, $3}' "$out/linked-libraries.txt")
# Bundle relocatable private libraries, without absolute build paths.
patchelf --set-rpath '$ORIGIN/../lib' "$bundle/bin/ddsrouter"
for lib in "$bundle"/lib/*; do
    patchelf --set-rpath '$ORIGIN' "$lib"
done
cp "$repo/.github/arm64/ddsrouter.yaml" "$bundle/ddsrouter.yaml"
cp "$repo/.github/arm64/start.sh" "$bundle/start.sh"
cp "$repo/.github/arm64/README.md" "$bundle/README.md"
cp "$work/build-info.txt" "$bundle/build-info.txt"
cp "$repo/LICENSE" "$bundle/licenses/DDS-Router-LICENSE"
for dir in "$work"/src/*; do
    mkdir -p "$bundle/licenses/$(basename "$dir")"
    find "$dir" -maxdepth 1 -type f \( -iname 'license*' -o -iname 'notice*' -o -iname 'copying*' \) -exec cp {} "$bundle/licenses/$(basename "$dir")/" \;
done
for pkg in libyaml-cpp0.8 libtinyxml2-10 libssl3t64; do
    if [[ -f /usr/share/doc/$pkg/copyright ]]; then
        cp /usr/share/doc/$pkg/copyright "$bundle/licenses/$pkg-copyright"
    fi
done
chmod +x "$bundle/start.sh"
(cd "$out" && zip -qr "$name.zip" "$name" && sha256sum "$name.zip" > "$name.zip.sha256")

# Test the extracted archive away from the build tree and without ROS paths.
check="$(mktemp -d)"
trap 'rm -rf "$check"' EXIT
unzip -q "$out/$name.zip" -d "$check"
cd "$check/$name"
unset LD_LIBRARY_PATH
ldd bin/ddsrouter | tee "$out/portable-libraries.txt"
if grep -q 'not found' "$out/portable-libraries.txt"; then exit 1; fi
if grep -Fq "$prefix" "$out/portable-libraries.txt"; then exit 1; fi
./start.sh --version | tee "$out/version.txt"
grep -q '2.3.0' "$out/version.txt"
./start.sh --help
timeout 30 ./start.sh -c ddsrouter.yaml -t 3 2>&1 | tee "$out/smoke.log"
grep -q 'DDS Router running.' "$out/smoke.log"
grep -q 'DDS Router stopped correctly.' "$out/smoke.log"
