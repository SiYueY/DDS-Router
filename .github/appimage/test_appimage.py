#!/usr/bin/env python3
"""Smoke-test AppImage execution against the native DDS Router binary."""

import argparse
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time

COMMAND_TIMEOUT = 30
LIFECYCLE_TIMEOUT = 15
STARTED = "DDS Router running."
STOPPED = "DDS Router stopped correctly."


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def kill_group(process: subprocess.Popen) -> None:
    """Clean up the private process group, including Runtime descendants."""
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    process.wait(timeout=LIFECYCLE_TIMEOUT)


def run_command(
    binary: Path, arguments: tuple[str, ...], cwd: Path, env: dict[str, str],
) -> tuple[int, str, str]:
    with subprocess.Popen(
        [str(binary), *arguments], cwd=cwd, env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        start_new_session=True,
    ) as process:
        try:
            stdout, stderr = process.communicate(timeout=COMMAND_TIMEOUT)
        except subprocess.TimeoutExpired as exc:
            kill_group(process)
            stdout, stderr = process.communicate(timeout=LIFECYCLE_TIMEOUT)
            raise RuntimeError(
                f"Command timed out: {binary} {arguments}\n{stdout}\n{stderr}"
            ) from exc
        except BaseException:
            kill_group(process)
            raise
        return process.returncode, stdout, stderr


def router_child(parent_pid: int) -> int:
    """Find the actual Router child of the pinned extract-and-run Runtime."""
    children = Path(f"/proc/{parent_pid}/task/{parent_pid}/children")
    for pid in children.read_text().split():
        try:
            if Path(f"/proc/{pid}/exe").resolve(strict=True).name == "ddsrouter":
                return int(pid)
        except FileNotFoundError:
            continue
    raise RuntimeError(f"Router child not found for Runtime PID {parent_pid}")


def test_signal(
    binary: Path, config: Path, cwd: Path, env: dict[str, str],
    signum: signal.Signals, extracted: bool = False,
) -> None:
    """Verify graceful shutdown, targeting the child in extraction mode."""
    output = cwd / f"{binary.name}-{signum.name}.log"
    with output.open("w", encoding="utf-8") as stream:
        process = subprocess.Popen(
            [str(binary), "-c", str(config)], cwd=cwd, env=env,
            stdout=stream, stderr=subprocess.STDOUT, start_new_session=True,
        )
        try:
            deadline = time.monotonic() + LIFECYCLE_TIMEOUT
            while time.monotonic() < deadline:
                text = output.read_text(encoding="utf-8", errors="replace")
                require(process.poll() is None, f"Early exit: {binary}\n{text}")
                if STARTED in text:
                    break
                time.sleep(0.1)
            else:
                raise RuntimeError(f"Startup timed out: {binary}\n{text}")

            target = router_child(process.pid) if extracted else process.pid
            os.kill(target, signum)
            status = process.wait(timeout=LIFECYCLE_TIMEOUT)
            text = output.read_text(encoding="utf-8", errors="replace")
            require(
                status == 0 and STOPPED in text,
                f"{binary} {signum.name}: exit={status}\n{text}",
            )
        except BaseException:
            kill_group(process)
            raise


def verify_appimage(
    native: Path, image: Path, config: Path, library_path: str, mode: str,
) -> None:
    base = dict(os.environ)
    for key in ("LD_PRELOAD", "LD_LIBRARY_PATH", "APPIMAGE_EXTRACT_AND_RUN"):
        base.pop(key, None)
    native_env = dict(base, LD_LIBRARY_PATH=library_path)
    # Deliberately supply a wrong library path; AppRun must replace it.
    image_env = dict(base, LD_LIBRARY_PATH="/nonexistent/ros-libraries")
    if mode == "extract":
        image_env["APPIMAGE_EXTRACT_AND_RUN"] = "1"

    with tempfile.TemporaryDirectory(prefix="ddsrouter-appimage-") as directory:
        cwd = Path(directory)
        local_config = cwd / "config with spaces.yaml"
        local_config.write_bytes(config.read_bytes())
        default_config = cwd / "DDS_ROUTER_CONFIGURATION.yaml"
        default_config.write_bytes(config.read_bytes())
        (cwd / "invalid.yaml").write_text("participants: [\n", encoding="utf-8")
        # Expected result categories: exact CLI output, startup/shutdown, error.
        cases = [
            ("help", ("--help",), "exact"),
            ("version", ("--version",), "exact"),
            ("default config", ("-t", "1"), "run"),
            ("no default config", ("-t", "1"), "error"),
            ("relative config", (
                "-c", local_config.name, "-d", "-r", "1", "-t", "2",
            ), "run"),
            ("absolute config", (
                "--config-path", str(local_config),
                "--log-filter", "DDSROUTER", "--log-verbosity", "info",
                "--timeout", "1",
            ), "run"),
            ("invalid option", ("--not-a-ddsrouter-option",), "error"),
            ("missing config", ("-c", "missing.yaml"), "error"),
            ("invalid YAML", ("-c", "invalid.yaml"), "error"),
        ]
        for name, arguments, behavior in cases:
            expected = run_command(native, arguments, cwd, native_env)
            actual = run_command(image, arguments, cwd, image_env)
            diagnostic = f"{mode}/{name}: native={expected}, AppImage={actual}"
            require(expected[0] == actual[0], diagnostic)
            require((actual[0] == 0) == (behavior != "error"), diagnostic)
            if behavior == "exact":
                require(expected == actual, diagnostic)
            elif behavior == "run":
                for _, stdout, stderr in (expected, actual):
                    output = stdout + stderr
                    require(STARTED in output and STOPPED in output, diagnostic)
            print(f"PASS {mode}: {name} (exit {actual[0]})", flush=True)
            if name == "default config":
                # Explicit paths must work without falling back to a default.
                default_config.unlink()

        for signum in (signal.SIGINT, signal.SIGTERM):
            test_signal(native, local_config, cwd, native_env, signum)
            test_signal(
                image, local_config, cwd, image_env, signum,
                extracted=mode == "extract",
            )
            print(f"PASS {mode}: {signum.name}", flush=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("native", type=Path)
    parser.add_argument("image", type=Path)
    parser.add_argument("config", type=Path)
    parser.add_argument("--library-path", required=True)
    parser.add_argument("--mode", choices=("mount", "extract"), required=True)
    args = parser.parse_args()
    try:
        verify_appimage(
            args.native.resolve(strict=True), args.image.resolve(strict=True),
            args.config.resolve(strict=True), args.library_path, args.mode,
        )
    except (OSError, RuntimeError, subprocess.SubprocessError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
