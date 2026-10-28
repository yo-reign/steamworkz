"""Optional, bounded local source/package check; never part of zig build test."""
import argparse
import hashlib
import io
import json
import os
import platform
import re
import shutil
import subprocess
import tarfile
from pathlib import Path, PurePosixPath

PACKAGE_FILES = frozenset([
    "build.zig", "build.zig.zon", "README.md", "LICENSE",
    "docs/api.md", "docs/building.md", "docs/lifecycle.md", "docs/migration.md", "docs/networking.md", "docs/services.md",
    "docs/development/README.md", "docs/development/ROADMAP.md", "docs/development/CHECKPOINT.md",
    "c/core.cpp", "c/core.h", "c/networking.cpp", "c/networking.h", "c/lobbies.cpp", "c/lobbies.h",
    "c/services.cpp", "c/services.h", "c/types.h", "c/utils.cpp", "c/utils.h", "c/input.cpp", "c/input.h",
    "c/networking_config.cpp", "c/networking_config.h", "c/networking_debug.cpp", "c/networking_debug.h",
    "c/voice.cpp", "c/voice.h", "c/remote_play.cpp", "c/remote_play.h", "c/timeline.cpp", "c/timeline.h",
    "c/workshop.cpp", "c/workshop.h", "c/screenshots.cpp", "c/screenshots.h",
    "src/Client.zig", "src/Context.zig", "src/Networking.zig", "src/NetworkingConfig.zig", "src/NetworkingDebug.zig",
    "src/Lobbies.zig", "src/events.zig", "src/Utils.zig", "src/Input.zig",
    "src/Voice.zig", "src/RemotePlay.zig", "src/Timeline.zig", "src/Workshop.zig", "src/Screenshots.zig",
    "src/native.zig", "src/requests.zig", "src/root.zig", "src/services.zig", "src/types.zig",
    "examples/smoke.zig", "examples/client.zig", "examples/lobby.zig", "examples/messages.zig",
    "tests/lifecycle_runner.zig", "tests/networking_guards.cpp", "tests/platform_guards.cpp", "tests/capability_guards.cpp",
    "tests/consumer/build.zig", "tests/consumer/build.zig.zon", "tests/consumer/main.zig", "tests/consumer/no_debug.zig",
    "tests/consumer/invalid_request.zig", "tests/consumer/invalid_image.zig",
    "tests/offline/check.py", "tests/offline/README.md",
])
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
    # Cached names include unstaged deletions; audit the current working tree.
    deleted = subprocess.check_output([
        "git", "-C", str(root), "ls-files", "--deleted", "-z"
    ]).decode().split("\0")
    names.difference_update(filter(None, deleted))
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


def linux_elf_metadata(dynamic, program_headers):
    needed = re.findall(r"\(NEEDED\).*?\[([^]]+)\]", dynamic)
    require("libsteam_api.so" in needed, "ELF lost Steam runtime dependency")
    require(not any("/" in name for name in needed), "ELF has path-qualified dependency")
    paths = re.findall(r"\((?:RUNPATH|RPATH)\).*?\[([^]]*)\]", dynamic)
    # These owned fixtures need no nonstandard library directory except adjacency.
    require(paths == ["$ORIGIN"], "ELF must have only the explicit $ORIGIN search path")
    interpreters = re.findall(r"Requesting program interpreter: ([^]]+)\]", program_headers)
    require(len(interpreters) == 1 and Path(interpreters[0]).is_absolute(), "ELF interpreter missing/invalid")
    return Path(interpreters[0])


def linux_deployment(executables, sdk, evidence, run, env):
    """Inspect trusted owned Linux artifacts; loader --list never enters main/init."""
    require(platform.system() == "Linux" and platform.machine() == "x86_64",
            "Linux deployment checks require a native x86_64 glibc host")
    require(shutil.which("readelf") is not None, "Linux deployment checks require binutils readelf")
    runtime = sdk / "redistributable_bin/linux64/libsteam_api.so"
    clean_env = {key: value for key, value in env.items()
                 if not key.startswith("LD_") and key not in ("STEAMWORKS_SDK", "SteamAppId", "SteamGameId", "GLIBC_TUNABLES")}
    clean_env["LC_ALL"] = "C"
    for index, executable in enumerate(executables):
        label = "linux-" + str(index) + "-" + executable.name
        dynamic = run(label + "-dynamic", ["readelf", "-dW", str(executable)], evidence, clean_env)
        headers = run(label + "-headers", ["readelf", "-lW", str(executable)], evidence, clean_env)
        loader = linux_elf_metadata(dynamic, headers)
        require(loader.is_file(), "native ELF interpreter unavailable")
        adjacent = executable.parent / runtime.name
        require(adjacent.read_bytes() == runtime.read_bytes(), "installed runtime mismatch")
        relocated = evidence / (label + "-relocated")
        missing = evidence / (label + "-missing-runtime")
        relocated.mkdir()
        missing.mkdir()
        shutil.copy2(executable, relocated / executable.name)
        shutil.copy2(adjacent, relocated / runtime.name)
        shutil.copy2(executable, missing / executable.name)
        for location, binary in (("installed", executable), ("relocated", relocated / executable.name)):
            output = run(label + "-" + location, [str(loader), "--inhibit-cache", "--list", str(binary)], evidence, clean_env)
            resolved = re.findall(r"libsteam_api\.so => (.+?) \(0x[0-9a-fA-F]+\)", output)
            require(len(resolved) == 1 and Path(resolved[0]).resolve() == binary.parent / runtime.name,
                    "loader did not select adjacent runtime")
        output = run(label + "-missing", [str(loader), "--inhibit-cache", "--list", str(missing / executable.name)],
                     evidence, clean_env, expect_success=False)
        require("libsteam_api.so: cannot open shared object file" in output,
                "missing-runtime control did not fail for the Steam runtime")
    return len(executables)


def self_test():
    dynamic = "(NEEDED) Shared library: [libsteam_api.so]\n(RUNPATH) Library runpath: [$ORIGIN]"
    headers = "[Requesting program interpreter: /lib64/ld-linux-x86-64.so.2]"
    linux_elf_metadata(dynamic, headers)
    for bad_dynamic, bad_headers in (
            (dynamic.replace("libsteam_api.so", "libother.so"), headers),
            (dynamic.replace("libsteam_api.so", "/sdk/libsteam_api.so"), headers),
            (dynamic.replace("$ORIGIN", "$ORIGIN:/sdk"), headers),
            (dynamic.replace("$ORIGIN", ""), headers),
            (dynamic.replace("$ORIGIN", "/sdk"), headers),
            (dynamic + "\n(RPATH) Library rpath: [/sdk]", headers),
            (dynamic, ""), (dynamic, headers.replace("/lib64/", ""))):
        try:
            linux_elf_metadata(bad_dynamic, bad_headers)
        except RuntimeError:
            continue
        raise RuntimeError("invalid Linux deployment metadata accepted")
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
    # Exercise working-tree inventory with an unstaged deletion and added file.
    import tempfile
    from unittest.mock import patch
    with tempfile.TemporaryDirectory() as directory:
        inventory = Path(directory) / "inventory"
        inventory.mkdir()
        for name in REPOSITORY_FILES:
            path = inventory / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"owned text\n")
        for bad in (None, "missing", "extra"):
            names = set(REPOSITORY_FILES) | {"old-document.md"}
            if bad == "missing":
                names.remove("README.md")
            if bad == "extra":
                names.add("unexpected.md")
            listed = ("\0".join(sorted(names)) + "\0").encode()
            with patch.object(subprocess, "check_output", side_effect=[listed, b"old-document.md\0"]):
                try:
                    read_sources(inventory)
                except RuntimeError as err:
                    require(bad is not None and "unexpected/missing repository inputs" in str(err),
                            "valid working-tree inventory rejected or wrong failure")
                else:
                    require(bad is None, "invalid working-tree inventory accepted: " + str(bad))

        # Exercise archive validation, including links and valid but unexpected inputs.
        archive = Path(directory) / "probe.tar.gz"
        expected = dict.fromkeys(PACKAGE_FILES, b"owned text\n")
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
                        name = "probe/" + min(expected)
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
    parser.add_argument("--linux-install", type=Path, action="append", default=[],
                        help="check only an existing Linux install prefix (repeatable); no builds or application execution")
    args = parser.parse_args()
    require(not (args.linux_install and args.run_consumer), "--linux-install never executes applications; omit --run-consumer")
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
    for key in ("ZIG_LOCAL_CACHE_DIR", "ZIG_GLOBAL_CACHE_DIR", "ZIG_LOCAL_PKG_DIR", "ZIG_BUILD_RUNNER"):
        env.pop(key, None)

    def run(label, command, cwd, run_env=None, expect_success=True):
        log = evidence / (label + ".log")
        with log.open("wb") as output:
            result = subprocess.run(command, cwd=cwd, env=run_env or env, stdout=output, stderr=subprocess.STDOUT, timeout=600, check=False)
        records.append({"label": label, "command": list(map(str, command)), "returncode": result.returncode,
                        "expect_success": expect_success})
        (evidence / "commands.json").write_text(json.dumps(records, indent=2) + "\n")
        require((result.returncode == 0) == expect_success, "unexpected command status; inspect private log: " + label)
        return log.read_text()

    version = run("zig-version", [args.zig, "version"], evidence).strip()
    require(version == "0.17.0", "Zig 0.17.0 required")
    require((sdk / "public/steam/steam_api.h").is_file(), "SDK public headers missing")
    files = read_sources(root)
    if args.linux_install:
        executables = []
        for prefix in args.linux_install:
            binaries = prefix.resolve() / "bin"
            found = [binaries / name for name in (
                "steamworkz-smoke", "steamworkz-consumer", "steamworkz-no-debug",
                "steamworkz-example-client", "steamworkz-example-lobby", "steamworkz-example-messages")
                if (binaries / name).is_file()]
            require(found, "no owned Linux executable in install prefix")
            executables.extend(found)
        count = linux_deployment(executables, sdk, evidence, run, env)
        require(read_sources(root) == files, "source changed during check")
        (evidence / "deployment.json").write_text(json.dumps({
            "executables": list(map(str, executables)), "checked": count,
            "source_sha256": {name: hashlib.sha256(data).hexdigest() for name, data in sorted(files.items())},
            "application_execution": False}, indent=2) + "\n")
        print("PASS: Linux metadata, runtime bytes, installed/relocated lookup and missing-runtime controls:", count)
        return
    snapshot, driver = evidence / "snapshot", evidence / "driver"
    snapshot.mkdir()
    driver.mkdir()
    # Zig 0.17 fetch without --save needs no driver project and writes globally.
    # Keep the invoking directory and cache outside the source snapshot.
    for name, data in files.items():
        path = snapshot / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    fetch_cache = evidence / "fetch-cache"
    package_hash = run("fetch", [args.zig, "fetch", str(snapshot)], driver,
                       {**env, "ZIG_GLOBAL_CACHE_DIR": str(fetch_cache)}).strip()
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
    common = ["-Dsdk=" + str(sdk), "-Doptimize=fast", "-j2", "--summary", "all"]
    # Launch outside the package root. Nested builds must preserve cache paths
    # relative to the invoking process, not reinterpret them relative to build.zig.
    run("relocated-test-install", [args.zig, "build", "test", "install", "examples", *common,
        "--build-file", str(relocated / "build.zig"),
        "--cache-dir", str(evidence / "relocated-cache"), "--pkg-dir", str(evidence / "relocated-pkg"),
        "--prefix", str(evidence / "relocated-install")], evidence,
        {**env, "ZIG_GLOBAL_CACHE_DIR": str(evidence / "relocated-global")})
    require({p.relative_to(relocated).as_posix(): p.read_bytes() for p in relocated.rglob("*") if p.is_file()} == package,
            "relocated build wrote into package sources")
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
        "--cache-dir", str(evidence / "consumer-cache"), "--pkg-dir", str(evidence / "consumer-pkg"),
        "--prefix", str(evidence / "consumer-install")], consumer,
        {**env, "ZIG_GLOBAL_CACHE_DIR": str(evidence / "consumer-global")})
    host = platform.system()
    runtime_dir, runtime_name = {"Darwin": ("osx", "libsteam_api.dylib"), "Linux": ("linux64", "libsteam_api.so"),
                                 "Windows": ("win64", "steam_api64.dll")}[host]
    runtime = (sdk / "redistributable_bin" / runtime_dir / runtime_name).read_bytes()
    for install in ("relocated-install", "consumer-install"):
        require((evidence / install / "bin" / runtime_name).read_bytes() == runtime, "installed runtime mismatch")
    linux_checked = 0
    if host == "Linux":
        linux_checked = linux_deployment([
            evidence / "relocated-install/bin/steamworkz-smoke",
            evidence / "relocated-install/bin/steamworkz-example-client",
            evidence / "relocated-install/bin/steamworkz-example-lobby",
            evidence / "relocated-install/bin/steamworkz-example-messages",
            evidence / "consumer-install/bin/steamworkz-consumer",
            evidence / "consumer-install/bin/steamworkz-no-debug",
        ], sdk, evidence, run, env)
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
               "linux_deployment_artifacts_checked": linux_checked, "pure_consumer_executed": args.run_consumer, "host": platform.platform(), "zig": version}
    (evidence / "audit.json").write_text(json.dumps(summary, indent=2) + "\n")
    print("PASS: source, fetched archive, relocated tests/install, independent hash consumer and runtime bytes")
    print("PASS: installed pure consumer" if args.run_consumer else "NOT RUN: installed pure consumer")


if __name__ == "__main__":
    main()
