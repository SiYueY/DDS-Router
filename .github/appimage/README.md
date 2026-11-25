# DDS Router AppImage

Portable builds of [DDS Router 2.3.0](https://github.com/eProsima/DDS-Router/tree/v2.3.0)
for Ubuntu. Each AppImage includes DDS Router and its private shared libraries,
preserves the native command-line interface, and accepts external YAML
configuration files without requiring ROS 2 to be installed.

> This is an independent build, not an official eProsima release. DDS Router
> 2.x is end-of-life and no longer receives upstream security updates.

## Supported Platforms

| Operating system | Architecture | Distribution directory |
| --- | --- | --- |
| Ubuntu 22.04 | amd64 | humble/amd64 |
| Ubuntu 22.04 | arm64 | humble/arm64 |
| Ubuntu 24.04 | amd64 | jazzy/amd64 |
| Ubuntu 24.04 | arm64 | jazzy/arm64 |

The Humble and Jazzy labels identify the target operating systems, not ROS 2
dependencies or guaranteed middleware interoperability. Compatible glibc and
C/C++ runtime libraries are required on the target.

## Download

Download the **ddsrouter-2.3.0** artifact from a successful
[AppImage workflow run](https://github.com/SiYueY/DDS-Router/actions/workflows/appimage-ci.yml).
Extract the Actions artifact, then verify and unpack the distribution ZIP:

```bash
sha256sum -c ddsrouter-2.3.0.zip.sha256
unzip ddsrouter-2.3.0.zip
```

The distribution contains four AppImages:

```text
ddsrouter-2.3.0/
├── humble/
│   ├── amd64/ddsrouter-2.3.0-humble-amd64.AppImage
│   └── arm64/ddsrouter-2.3.0-humble-arm64.AppImage
└── jazzy/
    ├── amd64/ddsrouter-2.3.0-jazzy-amd64.AppImage
    └── arm64/ddsrouter-2.3.0-jazzy-arm64.AppImage
```

Actions artifacts expire according to the repository retention policy.
Keep a verified copy for offline use.

## Usage

Select the AppImage for the target platform. For Ubuntu 22.04 amd64:

```bash
cd ddsrouter-2.3.0/humble/amd64
chmod +x ddsrouter-2.3.0-humble-amd64.AppImage
./ddsrouter-2.3.0-humble-amd64.AppImage --version
./ddsrouter-2.3.0-humble-amd64.AppImage -c router.yaml
```

Use YAML format v4.0 and the native DDS Router options (see `--help`).
Without `-c`, DDS Router looks for `DDS_ROUTER_CONFIGURATION.yaml` in the
current working directory. No default configuration is injected.
For a local startup test, save [smoke.yaml](smoke.yaml) beside the AppImage
and run:

```bash
./ddsrouter-2.3.0-humble-amd64.AppImage -c smoke.yaml -t 2
```

The test uses loopback DDS domains 90 and 91. Avoid running it alongside
applications using those domains.
See the [configuration reference](https://github.com/eProsima/DDS-Router/blob/v2.3.0/docs/rst/user_manual/configuration.rst).

### Running without FUSE

Normal execution uses FUSE and requires access to `/dev/fuse` and a compatible
mount helper. The bundled static Runtime does not require libfuse2 to be
installed separately. If FUSE is unavailable:

```bash
APPIMAGE_EXTRACT_AND_RUN=1 ./ddsrouter-2.3.0-humble-amd64.AppImage -c router.yaml
```

In mount mode, SIGINT and SIGTERM stop DDS Router normally. In extract-and-run
mode, the pinned Runtime does not forward signals sent only to its outer PID.
Supervise the actual Router child, or explicitly extract the image and
supervise `AppRun` directly. The native exit status and working directory are
preserved.

## Build

Build natively on a supported Ubuntu platform. Install the prerequisites:

```bash
sudo apt-get update
sudo apt-get install --no-install-recommends \
    build-essential cmake git libasio-dev libtinyxml2-dev libssl-dev \
    libyaml-cpp-dev python3-yaml file patchelf curl shellcheck \
    desktop-file-utils squashfs-tools fuse3 zip unzip
```

From the repository root:

```bash
work=$(mktemp -d)
bash .github/appimage/tools.sh "$work/tools"
bash .github/appimage/build.sh "$work/build"
bash .github/appimage/package.sh "$work/build" "$work/tools" "$work/dist"
```

The build uses upstream [`ddsrouter.repos`](../../ddsrouter.repos) release tags
and the original vendor build for foonathan/memory. Dependencies are installed
in a private prefix; the actual source commits, compiler, platform, tool
versions, resolved libraries and source working-tree status are recorded
in `build-info.txt`. Packaging tools are checked against fixed SHA256 digests.
Tags and system packages are not immutable, so bit-for-bit reproducibility
is not guaranteed.

Use fresh build and output directories without whitespace or colons.
`BUILD_JOBS` may be set to a positive integer, capped at four.

### Validation

The [CI workflow](../workflows/appimage-ci.yml) builds all four platforms
natively and checks:

- Shell and Python syntax, ShellCheck and desktop metadata.
- AppImage startup, native CLI output, configuration loading, error exit
  codes and shutdown.
- FUSE mount mode and extraction mode in a clean container without ROS 2.
- Dynamic library closure, ELF architecture, AppImage format and ZIP checksums.

[test_appimage.py](test_appimage.py) compares the native binary with the
AppImage in both runtime modes. It uses [smoke.yaml](smoke.yaml), a
loopback-only configuration for startup and shutdown tests; no ROS 2
nodes or physical robot are required.

The aggregate job runs only after every platform passes.
These are packaging and runtime checks, not DDS interoperability,
performance or robot-control acceptance tests.

## License

DDS Router is licensed under Apache-2.0. The official DDS Router product icon
is sourced from [eProsima DDS-Monitor](licenses/ddsrouter-icon/NOTICE).
The embedded [AppImage Runtime](licenses/appimage-runtime/NOTICE) and the
icon retain their respective upstream licenses and attribution. Third-party
notices, including the header-only Option Parser and FileWatch licenses,
are included under `usr/share/licenses` in each AppImage. The Runtime notice
also identifies its statically linked libraries and the pinned upstream
build sources.

Before public distribution, verify the exact versions and license notices of
all embedded Runtime libraries, applicable source-delivery/relinking
obligations and product trademark permissions. Bundled license files alone
do not establish full redistribution compliance.
