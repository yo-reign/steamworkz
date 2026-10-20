#!/usr/bin/env python3
"""Optional, bounded local source/package check; never part of zig build test."""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import platform
import re
import subprocess
import tarfile

PACKAGE_FILES = frozenset("""
build.zig build.zig.zon README.md LICENSE ROADMAP.md CHECKPOINT.md
c/core.cpp c/core.h c/networking.cpp c/networking.h c/lobbies.cpp c/lobbies.h
c/services.cpp c/services.h c/types.h
c/networking_config.cpp c/networking_config.h c/networking_debug.cpp c/networking_debug.h
src/Client.zig src/Context.zig src/Networking.zig src/NetworkingConfig.zig src/NetworkingDebug.zig
src/Lobbies.zig src/events.zig
src/native.zig src/requests.zig src/root.zig src/services.zig src/types.zig
examples/smoke.zig tests/lifecycle_runner.zig tests/networking_guards.cpp
tests/consumer/build.zig tests/consumer/build.zig.zon tests/consumer/main.zig tests/consumer/no_debug.zig
tests/consumer/invalid_request.zig tests/consumer/invalid_image.zig
tests/offline/check.py tests/offline/README.md
""".split())
REPOSITORY_FILES = PACKAGE_FILES | {".gitignore", "AGENTS.md", ".github/workflows/offline.yml"}
MAX_FILE = 1024 * 1024
MAX_TOTAL = 8 * MAX_FILE


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def safe_name(name):
    parts = name.split("/")
    require(name and not name.startswith("/") and "\\" not in name and ":" not in name
            and all(p not in ("", ".", "..") for p in parts), "unsafe member path")
    return PurePosixPath(name)


def audit_text(name, data):
    require(len(data) <= MAX_FILE and b"\x00" not in data, "oversized or binary input: " + name)
    text = data.decode("utf-8")
    # Deliberately bounded signatures, not a universal secret/copyright detector.
    machine = r"/(?:" + "Users|home|private/tmp|tmp|var/folders" + r")/|(?<![A-Za-z])[A-Za-z]:[\\/]"
    credentials = r"-----BEGIN " + r"(?:RSA |OPENSSH |EC )?PRIVATE KEY-----|gh[pousr]_" + r"[A-Za-z0-9]{30,}"
    require(not re.search(machine, text), "machine-specific path: " + name)
    require(not re.search(credentials, text), "credential signature: " + name)


def read_sources(root):
    names = subprocess.check_output([
        "git", "-C", str(root), "ls-files", "--cached", "--others", "--exclude-standard", "-z"
    ]).decode().split("\0")
    names = set(filter(None, names))
    require(names == REPOSITORY_FILES, "unexpected/missing repository inputs: " + repr(sorted(names ^ REPOSITORY_FILES)))
    files = {}
    for name in sorted(names):
        safe_name(name)
        path = root / name
        require(path.is_file() and not path.is_symlink() and path.resolve().is_relative_to(root), "nonregular source: " + name)
        # Reject symlinked parents too, even if they happen to resolve inside root.
        require(all(not parent.is_symlink() for parent in path.parents if parent.is_relative_to(root)), "source link")
        require(path.stat().st_size <= MAX_FILE, "source size budget exceeded: " + name)
        data = path.read_bytes()
        audit_text(name, data)
        files[name] = data
    require(sum(map(len, files.values())) <= MAX_TOTAL, "source size budget exceeded")
    return files


def audit_archive(archive, package_hash, expected):
    require(archive.stat().st_size <= MAX_TOTAL, "archive size budget exceeded")
    found = {}
    total = 0
    with tarfile.open(archive, "r:gz") as tar:
        for index, member in enumerate(tar):
            require(index < 128, "archive member budget exceeded")
            path = safe_name(member.name.rstrip("/") if member.isdir() else member.name)
            require(path.parts[0] == package_hash, "unexpected archive prefix")
            require(member.isdir() or member.isfile(), "links/special archive members forbidden")
            name = "/".join(path.parts[1:])
            if member.isdir():
                require(not name or any(p.startswith(name + "/") for p in PACKAGE_FILES), "unexpected archive directory")
                continue
            require(name in PACKAGE_FILES and name not in found, "unexpected/duplicate archive file: " + name)
            require(0 <= member.size <= MAX_FILE, "archive member size budget exceeded")
            total += member.size
            require(total <= MAX_TOTAL, "expanded archive size budget exceeded")
            stream = tar.extractfile(member)
            if stream is None:
                raise RuntimeError("regular archive member has no data: " + name)
            with stream:
                data = stream.read(MAX_FILE + 1)
            audit_text(name, data)
            require(data == expected[name], "archive differs from candidate: " + name)
            found[name] = data
    require(set(found) == PACKAGE_FILES, "archive missing required sources")
    return found


def self_test():
    for name in ("../x", "/x", "a/../b", "a\\b", "C:" + "/x", "a//b", "./x"):
        try:
            safe_name(name)
        except RuntimeError:
            continue
        raise RuntimeError("unsafe path accepted")
    safe_name("tests/consumer/main.zig")
    for data in (b"binary\x00", b"/" + b"Users/example/sdk", b"-----BEGIN " + b"PRIVATE KEY-----"):
        try:
            audit_text("probe", data)
        except RuntimeError:
            continue
        raise RuntimeError("unsafe content accepted")
    # Exercise archive validation, including links and valid but unexpected inputs.
    import tempfile
    with tempfile.TemporaryDirectory() as directory:
        archive = Path(directory) / "probe.tar.gz"
        expected = {name: b"owned text\n" for name in PACKAGE_FILES}
        for bad in (None, "link", "extra", "missing", "changed", "traversal", "duplicate"):
            with tarfile.open(archive, "w:gz") as tar:
                for index, (name, data) in enumerate(sorted(expected.items())):
                    if bad == "missing" and index == 0:
                        continue
                    member = tarfile.TarInfo("probe/" + name)
                    member.size = len(data)
                    tar.addfile(member, io.BytesIO(data if bad != "changed" or index else b"wrong text\n"))
                if bad in ("link", "extra", "traversal", "duplicate"):
                    name = "probe/extra" if bad != "traversal" else "probe/../escape"
                    if bad == "duplicate":
                        name = "probe/" + sorted(expected)[0]
                    member = tarfile.TarInfo(name)
                    if bad == "link":
                        member.type = tarfile.SYMTYPE
                        member.linkname = "outside"
                    tar.addfile(member)
            try:
                audit_archive(archive, "probe", expected)
            except RuntimeError:
                require(bad is not None, "valid archive rejected")
            else:
                require(bad is None, "unsafe archive accepted: " + str(bad))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--sdk", type=Path, default=os.environ.get("STEAMWORKS_SDK"))
    parser.add_argument("--evidence", type=Path, help="new private directory outside source and SDK; retained on failure")
    parser.add_argument("--zig", default="zig")
    parser.add_argument("--run-consumer", action="store_true", help="run only the inspected pure installed consumer main")
    parser.add_argument("--self-test", action="store_true", help="run checker unit controls only (no SDK needed)")
    args = parser.parse_args()
    self_test()
    if args.self_test:
        print("PASS: checker controls")
        return
    if args.sdk is None or args.evidence is None:
        raise RuntimeError("--sdk/STEAMWORKS_SDK and --evidence required")
    root, sdk, evidence = args.source.resolve(), args.sdk.resolve(), args.evidence.resolve()
    require(not sdk.is_relative_to(root) and not root.is_relative_to(sdk), "SDK must remain external")
    require(not evidence.is_relative_to(root) and not evidence.is_relative_to(sdk)
            and not root.is_relative_to(evidence) and not sdk.is_relative_to(evidence), "evidence must be disjoint from source and SDK")
    evidence.mkdir(mode=0o700, parents=True, exist_ok=False)
    os.umask(0o077)
    records = []
    env = os.environ.copy()
    # A caller's Zig overrides must not redirect outputs back into package inputs.
    for key in ("ZIG_LOCAL_CACHE_DIR", "ZIG_GLOBAL_CACHE_DIR", "ZIG_BUILD_RUNNER"):
        env.pop(key, None)

    def run(label, command, cwd, run_env=None):
        log = evidence / (label + ".log")
        with log.open("wb") as output:
            result = subprocess.run(command, cwd=cwd, env=run_env or env, stdout=output, stderr=subprocess.STDOUT, timeout=600)
        records.append({"label": label, "command": list(map(str, command)), "returncode": result.returncode})
        (evidence / "commands.json").write_text(json.dumps(records, indent=2) + "\n")
        require(result.returncode == 0, "command failed; inspect private log: " + label)
        return log.read_text()

    version = run("zig-version", [args.zig, "version"], evidence).strip()
    require(version == "0.16.0", "Zig 0.16.0 required")
    require((sdk / "public/steam/steam_api.h").is_file(), "SDK public headers missing")
    files = read_sources(root)
    snapshot, driver = evidence / "snapshot", evidence / "driver"
    snapshot.mkdir()
    driver.mkdir()
    # Zig 0.16 fetch locates a project even without --save. Keep that driver and
    # its zig-pkg output entirely outside the source snapshot being fetched.
    (driver / "build.zig").write_text('pub fn build(_: *@import("std").Build) void {}\n')
    (driver / "build.zig.zon").write_text('.{ .name = .steamworkz_consumer, .version = "0.0.0", .fingerprint = 0x295e56848c2e3165, .paths = .{"build.zig", "build.zig.zon"} }\n')
    for name, data in files.items():
        path = snapshot / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    fetch_cache = evidence / "fetch-cache"
    package_hash = run("fetch", [args.zig, "fetch", "--global-cache-dir", str(fetch_cache), str(snapshot)], driver).strip()
    require(re.fullmatch(r"steamworkz-0\.1\.0-[A-Za-z0-9_-]+", package_hash), "unexpected fetch hash")
    archive = fetch_cache / "p" / (package_hash + ".tar.gz")
    package = audit_archive(archive, package_hash, files)
    require({p.relative_to(snapshot).as_posix(): p.read_bytes() for p in snapshot.rglob("*") if p.is_file()} == files, "fetch mutated snapshot")
    relocated = evidence / "relocated"
    relocated.mkdir()
    for name, data in package.items():
        path = relocated / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    common = ["-Dsdk=" + str(sdk), "-Doptimize=ReleaseFast", "--summary", "all"]
    run("relocated-test-install", [args.zig, "build", "test", "install", *common,
        "--cache-dir", str(evidence / "relocated-cache"), "--global-cache-dir", str(evidence / "relocated-global"),
        "--prefix", str(evidence / "relocated-install")], relocated)
    consumer = evidence / "consumer"
    consumer.mkdir()
    # Copy every consumer source from the already validated exact allowlist.
    # A second handwritten filename list could omit a new linkage fixture.
    for path, data in sorted(package.items()):
        if not path.startswith("tests/consumer/"):
            continue
        name = path.removeprefix("tests/consumer/")
        if name == "build.zig.zon":
            old = b'.path = "../.."'
            require(data.count(old) == 1, "consumer dependency recipe changed")
            data = data.replace(old, ('.url = "' + archive.as_uri() + '", .hash = "' + package_hash + '"').encode())
        (consumer / name).write_bytes(data)
    run("archive-consumer", [args.zig, "build", "install", "check-negative", *common,
        "--cache-dir", str(evidence / "consumer-cache"), "--global-cache-dir", str(evidence / "consumer-global"),
        "--prefix", str(evidence / "consumer-install")], consumer)
    host = platform.system()
    runtime_dir, runtime_name = {"Darwin": ("osx", "libsteam_api.dylib"), "Linux": ("linux64", "libsteam_api.so"),
                                 "Windows": ("win64", "steam_api64.dll")}[host]
    runtime = (sdk / "redistributable_bin" / runtime_dir / runtime_name).read_bytes()
    for install in ("relocated-install", "consumer-install"):
        require((evidence / install / "bin" / runtime_name).read_bytes() == runtime, "installed runtime mismatch")
    if args.run_consumer:
        # main.zig is maintained as a pure value-only entry point. Its retained
        # native-backed exports are deliberately uncalled; review them before use.
        clean_env = env.copy()
        for key in ("DYLD_LIBRARY_PATH", "DYLD_FALLBACK_LIBRARY_PATH", "LD_LIBRARY_PATH", "SteamAppId", "SteamGameId", "STEAMWORKS_SDK"):
            clean_env.pop(key, None)
        clean_env["PATH"] = os.pathsep.join(p for p in clean_env.get("PATH", "").split(os.pathsep) if p and not Path(p).resolve().is_relative_to(sdk))
        exe = evidence / "consumer-install/bin" / ("steamworkz-consumer.exe" if host == "Windows" else "steamworkz-consumer")
        run("installed-pure-consumer", [str(exe)], driver, clean_env)
    require(read_sources(root) == files, "source changed during check")
    summary = {"package_hash": package_hash, "archive": str(archive), "archive_sha256": hashlib.sha256(archive.read_bytes()).hexdigest(),
               "members": sorted(package), "source_sha256": {name: hashlib.sha256(data).hexdigest() for name, data in sorted(files.items())},
               "runtime_sha256": hashlib.sha256(runtime).hexdigest(), "installed_runtime_copies_match": 2,
               "pure_consumer_executed": args.run_consumer, "host": platform.platform(), "zig": version}
    (evidence / "audit.json").write_text(json.dumps(summary, indent=2) + "\n")
    print("PASS: source, fetched archive, relocated tests/install, independent hash consumer and runtime bytes")
    print("PASS: installed pure consumer" if args.run_consumer else "NOT RUN: installed pure consumer")


if __name__ == "__main__":
    main()
