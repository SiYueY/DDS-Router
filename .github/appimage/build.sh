#!/usr/bin/env bash
# Build DDS Router and its upstream dependencies in a private prefix.
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=.github/appimage/common.sh
source "$script_dir/common.sh"

[[ $# == 1 ]] || die "Usage: build.sh WORK_DIRECTORY"
require_commands git cmake python3 gcc g++ nproc
detect_platform

repo="$(cd "$script_dir/../.." && pwd)"
work="$(realpath -m "$1")"
require_build_path "$repo"
require_build_path "$work"
prefix="$work/install"
source_status="$(git -C "$repo" status --short)"

[[ ! -e "$work" ]] || die "Build workspace already exists: $work"
mkdir -p "$work/src" "$work/build" "$prefix"

# Keep the build independent of installed ROS workspaces.
unset AMENT_PREFIX_PATH COLCON_PREFIX_PATH CMAKE_PREFIX_PATH LD_LIBRARY_PATH LD_PRELOAD
export CMAKE_PREFIX_PATH="$prefix"

jobs="${BUILD_JOBS:-$(nproc)}"
[[ "$jobs" =~ ^[1-9][0-9]{0,5}$ ]] || die "BUILD_JOBS must be a positive integer"
# Limit peak compiler memory on the supported CI runners.
if (( jobs > 4 )); then
    jobs=4
fi

# Reuse the upstream release manifest; build DDS Router from this checkout.
python3 - "$repo/ddsrouter.repos" "$work/src" <<'PYDEPS'
from pathlib import Path
import subprocess
import sys

import yaml

repositories = yaml.safe_load(Path(sys.argv[1]).read_text())["repositories"]
for name, entry in repositories.items():
    if name != "ddsrouter":
        subprocess.run(
            ["git", "clone", "--depth", "1", "--branch", entry["version"],
             "--", entry["url"], str(Path(sys.argv[2]) / name)],
            check=True,
        )
PYDEPS

build_component() {
    local name="$1" source_dir="$2"
    shift 2

    log "Building $name ($jobs jobs)"
    cmake -S "$source_dir" -B "$work/build/$name" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$prefix" \
        -DCMAKE_PREFIX_PATH="$prefix" \
        -DCMAKE_FIND_USE_PACKAGE_REGISTRY=FALSE \
        -DCMAKE_FIND_USE_SYSTEM_PACKAGE_REGISTRY=FALSE \
        -DBUILD_TESTS=OFF "$@"
    cmake --build "$work/build/$name" --parallel "$jobs"
    cmake --install "$work/build/$name"
}

# Let the upstream vendor build its own dependency, even if the host has
# foonathan_memory installed. Fast DDS must then use that private package.
build_component foonathan_memory_vendor "$work/src/foonathan_memory_vendor" \
    -DBUILD_SHARED_LIBS=ON \
    -DCMAKE_DISABLE_FIND_PACKAGE_foonathan_memory=TRUE

memory_source="$work/build/foonathan_memory_vendor/foo_mem-ext-prefix/src/foo_mem-ext"
memory_config="$(find "$prefix" -type f -iname 'foonathan_memory-config.cmake')"
[[ -d "$memory_source/.git" && -f "$memory_config" ]] ||
    die "Private foonathan_memory build is incomplete"
memory_dir="$(dirname "$memory_config")"

build_component fastcdr "$work/src/fastcdr"
build_component fastdds "$work/src/fastdds" -Dfoonathan_memory_DIR="$memory_dir"
build_component cmake_utils "$work/src/dev_utils/cmake_utils"
build_component cpp_utils "$work/src/dev_utils/cpp_utils"
build_component ddspipe_core "$work/src/ddspipe/ddspipe_core"
build_component ddspipe_participants "$work/src/ddspipe/ddspipe_participants"
build_component ddspipe_yaml "$work/src/ddspipe/ddspipe_yaml"
build_component ddsrouter_core "$repo/ddsrouter_core"
build_component ddsrouter_yaml "$repo/ddsrouter_yaml"
build_component ddsrouter_tool "$repo/tools/ddsrouter_tool"

{
    printf 'DDS Router source: %s\n' "$(git -C "$repo" rev-parse HEAD)"
    printf 'Source working tree (empty means clean):\n%s\n' "$source_status"
    printf 'Platform: %s/%s\n' "$distro" "$arch"
    printf 'Dependency revisions:\n'
    for dir in "$work"/src/*; do
        printf '%s %s\n' "$(basename "$dir")" "$(git -C "$dir" rev-parse HEAD)"
    done
    printf 'foonathan_memory %s\n' "$(git -C "$memory_source" rev-parse HEAD)"
    cat /etc/os-release
    uname -a
    gcc --version
    g++ --version
    cmake --version
} > "$work/build-info.txt"
log "Build completed: $prefix"
