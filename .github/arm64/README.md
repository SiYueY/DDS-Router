# DDS Router 2.3.0 — Ubuntu 24.04 ARM64

Built natively from the v2.3.0 dependency manifest on the GitHub-hosted
ubuntu-24.04-arm runner. No ROS 2 installation is required. The portable
archive targets Ubuntu 24.04 aarch64 and uses the target OS glibc, libstdc++
and GCC runtime. No sudo or installation is required to run it.

Extract the ZIP, then run `./start.sh --version` or `./start.sh`.
The included ddsrouter.yaml is a loopback-only smoke-test configuration.
For robot use, set the two actual domain IDs and interface IP addresses.
Use configuration version v4.0, not v5.0. Omitting allowlist and routes
allows dynamic bidirectional forwarding; do not expose it to untrusted Wi-Fi.

CI validates native build, ELF architecture, dependency resolution after
relocation, CLI help/version and timed startup/shutdown. It does not certify
Humble/Jazzy interoperability, ROS Graph discovery, or physical robot control.
Those require separate testing on the target hardware with safe test topics.
