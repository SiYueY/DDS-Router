#!/usr/bin/env bash
# Stage the native binary and its ELF dependency closure into an AppDir.
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=.github/appimage/common.sh
source "$script_dir/common.sh"

[[ $# == 3 ]] || die "Usage: package.sh WORK TOOLS OUTPUT"
require_commands readelf ldd patchelf sha256sum install
detect_platform
work="$(realpath "$1")"
tools="$(realpath "$2")"
out="$(realpath -m "$3")"
prefix="$work/install"
appdir="$work/DDSRouter.AppDir"
repo="$(cd "$script_dir/../.." && pwd)"
require_build_path "$work"
require_build_path "$tools"
require_build_path "$out"
[[ ! -e "$appdir" ]] || die "Use a fresh build directory: $appdir"
[[ ! -e "$out" ]] || die "Use a fresh output directory: $out"

# Leave glibc and the compiler runtime to the target OS.
is_system_runtime() {
    case "$1" in
        libc.so.*|libm.so.*|libpthread.so.*|libdl.so.*|librt.so.*|libgcc_s.so.*|libstdc++.so.*|ld-linux-*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

mkdir -p "$appdir/usr/"{bin,lib,share/licenses,share/ddsrouter} "$out"
binary="$prefix/bin/ddsrouter"
[[ -x "$binary" ]] || die "Missing native binary: $binary"
check_elf "$binary" "$elf_machine"
install -m 0755 "$binary" "$appdir/usr/bin/ddsrouter"

# Resolve dependencies using the private install, not ROS environment paths.
unset LD_PRELOAD
export LD_LIBRARY_PATH
LD_LIBRARY_PATH="$(find "$prefix" -type f -name '*.so*' -printf '%h\n' | sort -u | paste -sd:)"
[[ -n "$LD_LIBRARY_PATH" ]] || die "No private shared libraries"

native_dependencies="$(ldd "$binary")"
[[ "$native_dependencies" != *'not found'* ]] || die "Unresolved dependencies"
while read -r soname path; do
    is_system_runtime "$soname" && continue
    log "Bundling $soname"
    cp -L -- "$path" "$appdir/usr/lib/$soname"
done < <(awk '$2 == "=>" && $3 ~ /^\// {print $1, $3}' <<< "$native_dependencies")

# shellcheck disable=SC2016
patchelf --set-rpath '$ORIGIN/../lib' "$appdir/usr/bin/ddsrouter"
for lib in "$appdir"/usr/lib/*; do
    check_elf "$lib" "$elf_machine"
    # shellcheck disable=SC2016
    patchelf --set-rpath '$ORIGIN' "$lib"
done
# Verify the staged closure without access to the original build libraries.
bundled_dependencies="$(LD_LIBRARY_PATH="$appdir/usr/lib" ldd "$appdir/usr/bin/ddsrouter")"
[[ "$bundled_dependencies" != *'not found'* ]] || die "Unresolved AppDir dependencies"
while read -r soname path; do
    is_system_runtime "$soname" && continue
    [[ "$path" == "$appdir/usr/lib/"* ]] ||
        die "Unbundled dependency: $soname ($path)"
done < <(awk '$2 == "=>" && $3 ~ /^\// {print $1, $3}' <<< "$bundled_dependencies")

install -m 0755 "$script_dir/AppRun" "$appdir/AppRun"
install -m 0644 "$script_dir/ddsrouter.desktop" "$script_dir/ddsrouter.svg" "$appdir/"

# Keep one build record with the image and the CI artifact.
{
    cat "$work/build-info.txt" "$tools/tools-info.txt"
    printf '\nBundled dependency resolution:\n%s\n' "$bundled_dependencies"
} > "$out/build-info.txt"
install -m 0644 "$out/build-info.txt" "$appdir/usr/share/ddsrouter/"

install -D -m 0644 "$repo/LICENSE" "$appdir/usr/share/licenses/DDS-Router/LICENSE"
# Include separate license and attribution files for packaging assets.
for license_dir in "$script_dir"/licenses/*; do
    destination="$appdir/usr/share/licenses/$(basename "$license_dir")"
    install -d "$destination"
    install -m 0644 "$license_dir/"* "$destination/"
done
for dir in "$work"/src/*; do
    license_dir="$appdir/usr/share/licenses/$(basename "$dir")"
    mkdir -p "$license_dir"
    find "$dir" -maxdepth 1 -type f \( -iname 'license*' -o -iname 'notice*' -o -iname 'copying*' \) \
        -exec cp -- {} "$license_dir/" \;
done
# The vendor's nested dependency has its own license.
memory_source="$work/build/foonathan_memory_vendor/foo_mem-ext-prefix/src/foo_mem-ext"
install -D -m 0644 "$memory_source/LICENSE" \
    "$appdir/usr/share/licenses/foonathan_memory/LICENSE"

# Debian package copyright paths differ across Ubuntu releases.
for pkg in libasio-dev libyaml-cpp0.7 libyaml-cpp0.8 libtinyxml2-9 libtinyxml2-10 libssl3 libssl3t64; do
    if [[ -f "/usr/share/doc/$pkg/copyright" ]]; then
        install -D -m 0644 "/usr/share/doc/$pkg/copyright" "$appdir/usr/share/licenses/$pkg/copyright"
    fi
done

# The packaging tool runs without FUSE. Embed the verified static runtime.
unset LD_LIBRARY_PATH
log "Creating $artifact.AppImage"
ARCH="$runtime_arch" APPIMAGE_EXTRACT_AND_RUN=1 "$tools/appimagetool.AppImage" \
    --runtime-file "$tools/runtime" "$appdir" "$out/$artifact.AppImage"
chmod 0755 "$out/$artifact.AppImage"
check_appimage "$out/$artifact.AppImage" "$elf_machine"
(cd "$out" && sha256sum "$artifact.AppImage" > "$artifact.AppImage.sha256")
log "AppImage created: $out/$artifact.AppImage"
