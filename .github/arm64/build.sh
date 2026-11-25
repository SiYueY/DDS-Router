#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
work="$(realpath -m "${1:?Usage: build.sh WORK_DIRECTORY}")"
prefix="$work/install"
mkdir -p "$work/src" "$work/build" "$prefix"

# Use the tagged upstream manifest, except build the checked-out fork itself.
python3 - "$repo/ddsrouter.repos" "$work/src" <<'PYDEPS'
import pathlib, subprocess, sys, yaml
repos = yaml.safe_load(pathlib.Path(sys.argv[1]).read_text())["repositories"]
root = pathlib.Path(sys.argv[2])
for name, info in repos.items():
    if name == "ddsrouter":
        continue
    target = root / name
    subprocess.run(["git", "clone", "--depth", "1", "--branch", info["version"],
                    info["url"], str(target)], check=True)
PYDEPS

unset AMENT_PREFIX_PATH COLCON_PREFIX_PATH CMAKE_PREFIX_PATH LD_LIBRARY_PATH
export CMAKE_PREFIX_PATH="$prefix"
jobs="${BUILD_JOBS:-$(nproc)}"
# Cap peak memory for Fast DDS compilation on hosted runners.
if (( jobs > 4 )); then jobs=4; fi

build() {
    local name="$1" source="$2"
    shift 2
    cmake -S "$source" -B "$work/build/$name" \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$prefix" \
        -DCMAKE_PREFIX_PATH="$prefix" -DBUILD_TESTS=OFF "$@"
    cmake --build "$work/build/$name" --parallel "$jobs"
    cmake --install "$work/build/$name"
}

build foonathan_memory_vendor "$work/src/foonathan_memory_vendor" -DBUILD_SHARED_LIBS=ON
build fastcdr "$work/src/fastcdr"
build fastdds "$work/src/fastdds"
build cmake_utils "$work/src/dev_utils/cmake_utils"
build cpp_utils "$work/src/dev_utils/cpp_utils"
build ddspipe_core "$work/src/ddspipe/ddspipe_core"
build ddspipe_participants "$work/src/ddspipe/ddspipe_participants"
build ddspipe_yaml "$work/src/ddspipe/ddspipe_yaml"
build ddsrouter_core "$repo/ddsrouter_core"
build ddsrouter_yaml "$repo/ddsrouter_yaml"
build ddsrouter_tool "$repo/tools/ddsrouter_tool"

{
    git -C "$repo" rev-parse HEAD
    for dir in "$work"/src/*; do
        printf '%s ' "$(basename "$dir")"
        git -C "$dir" rev-parse HEAD
    done
    uname -a
    gcc --version
} > "$work/build-info.txt"
