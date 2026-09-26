#!/usr/bin/env python3
"""The launchers' first-run block, RUN against every case in
contracts/app-rules.json → helperBootstrap (GitHub #312).

The Mac app carries the four helper programs and the website builder's
starting disk; the launchers install the programs into Plantoir's tools
folder and create the website builder from that disk. This cuts the block
that does it out of setup.sh — from its `# >>> FIRST-RUN BLOCK >>>` line to
the bare `ensure_container_runtime` — and runs it with bash 3.2, the bash a
teacher's Mac has, against a scratch home folder. Everything that decides
anything is real: shasum, cp, xattr, tar, mktemp, mv. Only the network and
the programs themselves are stand-ins: `curl` serves files from a folder, and
`colima`/`docker` are small scripts that write down how they were called.

Every case runs twice — under `set -euo pipefail`, as setup.sh and deploy.sh
run, and without it, as preview.sh runs — because the same text runs under
both, and three ordinary moments (an unset variable, a file with no
quarantine mark, a refused start) abort one regime and not the other.

After every case the app's copy must be byte-for-byte what it was: anything
written inside the app would turn every later Sparkle update into a full
download, silently.

macOS only. The block uses `cp -c` and `xattr`, which Git Bash on Windows
does not have, and Windows has no helper programs to install; so it SKIPS on
anything that is not a Mac rather than failing there.
"""

import hashlib
import json
import os
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
import unittest
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parent.parent
LAUNCHERS = ["setup.sh", "preview.sh", "deploy.sh"]
BLOCK_START = "# >>> FIRST-RUN BLOCK >>>"
BASH = "/bin/bash"
ON_A_MAC = sys.platform == "darwin" and Path(BASH).exists() and shutil.which("xattr") is not None


def first_run_block(launcher):
    """The block, from its first line to the bare `ensure_container_runtime`."""
    lines = (REPOSITORY_ROOT / launcher).read_text(encoding="utf-8").split("\n")
    block = []
    inside = False
    for line in lines:
        if line.startswith(BLOCK_START):
            inside = True
        if inside:
            block.append(line)
            if line == "ensure_container_runtime":
                return block
    return []


def wait_for_docker_function():
    """`_wait_for_docker`, which the block calls and which sits just above it."""
    text = (REPOSITORY_ROOT / "setup.sh").read_text(encoding="utf-8")
    start = text.index("_wait_for_docker() {")
    end = text.index("\n}\n", start) + 3
    return text[start:end]


def the_contract():
    rules = json.loads((REPOSITORY_ROOT / "contracts" / "app-rules.json").read_text(encoding="utf-8"))
    return rules["helperBootstrap"]


def the_trail_entries():
    shared = json.loads((REPOSITORY_ROOT / "contracts" / "shared-rules.json").read_text(encoding="utf-8"))
    found = {}
    for entry in shared["activityTrail"]["mustRecord"]:
        found[entry["event"]] = entry
    return found


def sha256_of(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write_executable(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    path.chmod(0o755)


# The stand-in programs. Each carries a line saying where it came from, so a
# case can tell a copy from the app from a download from an older install.
COLIMA_STUB = """#!/bin/bash
# FROM={origin}
log="$HOME/.stub-log"
case "$1" in
  start)
    shift
    printf 'colima start' >> "$log"
    for word in "$@"; do printf ' [%s]' "$word" >> "$log"; done
    printf '\\n' >> "$log"
    case " $* " in
      *" --disk-image "*)
        case "${{STUB_SEED:-accepted}}" in
          refused)
            mkdir -p "$HOME/.colima/default"
            echo "FATA[0001] hash failure: SHA512 checksum mismatch"
            exit 1 ;;
          fails)
            echo "FATA[0000] dependency check failed"
            exit 1 ;;
        esac ;;
    esac
    mkdir -p "$HOME/.colima/default"
    touch "$HOME/.stub-docker-answers"
    echo "INFO[0020] done"
    exit 0 ;;
  list) exit 0 ;;
  stop) exit 0 ;;
  --version) echo "colima version stub" ;;
esac
exit 0
"""

DOCKER_STUB = """#!/bin/bash
# FROM={origin}
case "$1" in
  info) [ -f "$HOME/.stub-docker-answers" ] && exit 0; exit 1 ;;
  buildx) [ -x "$HOME/.docker/cli-plugins/docker-buildx" ] && [ ! -L "$HOME/.docker/cli-plugins/docker-buildx" ] && exit 0; exit 1 ;;
  images) exit 0 ;;
esac
exit 0
"""

SIMPLE_STUB = """#!/bin/bash
# FROM={origin} {name}
exit 0
"""

# Serves every URL from a folder of files named after the URL, and writes the
# URL down, so a case can count the downloads and see which kind of Mac they
# were for.
CURL_STUB = """#!/bin/bash
destination=""
url=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) destination="$2"; shift 2 ;;
    -*) shift ;;
    *) url="$1"; shift ;;
  esac
done
echo "$url" >> "$HOME/.stub-downloads"
name=$(printf '%s' "$url" | tr '/:' '__')
[ -f "$STUB_SERVED/$name" ] || exit 22
cp "$STUB_SERVED/$name" "$destination"
"""

UNAME_STUB = """#!/bin/bash
if [ "$1" = "-m" ]; then echo "${STUB_ARCH:-arm64}"; exit 0; fi
exec /usr/bin/uname "$@"
"""


@unittest.skipUnless(ON_A_MAC, "the first-run block needs a Mac: cp -c, xattr and bash 3.2")
class HelperBootstrapTests(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.contract = the_contract()
        cls.block = first_run_block("setup.sh")
        cls.pins = cls.read_pins()

    @classmethod
    def read_pins(cls):
        """The launcher's own values, asked of the block itself."""
        script = "\n".join(cls.block[:-1]) + "\n_helper_pins\n_helper_pins_word\necho \"$VM_IMAGE_NAME\"\n"
        result = subprocess.run([BASH, "-c", script], capture_output=True, text=True, check=True)
        lines = result.stdout.strip().split("\n")
        return {"line": lines[0], "word": lines[1], "image": lines[2]}

    # MARK: - The block itself

    def test_the_three_launchers_carry_the_same_block(self):
        first = first_run_block("setup.sh")
        self.assertGreater(len(first), 100, "the block was not found in setup.sh")
        for launcher in LAUNCHERS:
            self.assertEqual(first_run_block(launcher), first, launcher + "'s first-run block differs from setup.sh's")

    def test_the_printed_words_are_the_contracts(self):
        text = "\n".join(self.block)
        printed = self.contract["printed"]
        for key in ["preparingHelpers", "keptTheCopyHere", "firstStartSeeded", "firstStartDownloading"]:
            self.assertIn('echo "' + printed[key] + '"', text, key)
        self.assertIn('echo "📦 Downloading ${label}…"', text)
        self.assertEqual(printed["downloadingHelper"], "📦 Downloading what your website builder needs ({n} of 4)…")
        self.assertIn('echo "❌ Could not download ${label}."', text)
        for launcher in LAUNCHERS:
            whole = (REPOSITORY_ROOT / launcher).read_text(encoding="utf-8")
            self.assertIn('echo "' + printed["buildingFirstTime"] + '"', whole, launcher)

    def test_the_markers_are_the_trail_contracts(self):
        entries = the_trail_entries()
        text = "\n".join(self.block)
        for event in ["helper programs installed", "website builder created"]:
            self.assertIn(event, entries, "shared-rules.json has no '" + event + "' event")
            self.assertEqual(entries[event].get("appliesOn"), ["mac"], event)
            self.assertIn('echo "' + entries[event]["marker"]["prefix"] + " ", text, event)

    # MARK: - The cases

    def test_every_install_case(self):
        for case in self.contract["installCases"]:
            for strict in [True, False]:
                with self.subTest(case=case["name"], strict=strict):
                    self.run_install_case(case, strict)

    def test_every_first_start_case(self):
        for case in self.contract["firstStartCases"]:
            for strict in [True, False]:
                with self.subTest(case=case["name"], strict=strict):
                    self.run_first_start_case(case, strict)

    # MARK: - Building a case

    def make_world(self):
        root = Path(tempfile.mkdtemp(prefix="helper-bootstrap-"))
        self.addCleanup(shutil.rmtree, root, True)
        world = {
            "root": root,
            "home": root / "home",
            "tools": root / "home" / "Library" / "Application Support" / "Plantoir" / "tools",
            "bundle": root / "Plantoir.app" / "Contents" / "Resources" / "helpers",
            "served": root / "served",
            "stubs": root / "stubs",
            "elsewhere": root / "homebrew" / "bin",
        }
        for key in ["home", "served", "stubs", "elsewhere"]:
            world[key].mkdir(parents=True)
        write_executable(world["stubs"] / "curl", CURL_STUB)
        write_executable(world["stubs"] / "uname", UNAME_STUB)
        return world

    def program_files(self, origin, arch="arm64"):
        """Every file a full install has, as relative path → text."""
        return {
            "bin/colima": COLIMA_STUB.format(origin=origin),
            "bin/limactl": SIMPLE_STUB.format(origin=origin, name="limactl"),
            "bin/lima": SIMPLE_STUB.format(origin=origin, name="lima"),
            "bin/docker": DOCKER_STUB.format(origin=origin),
            "share/lima/lima-guestagent.Linux-aarch64.gz": "agent " + origin,
            "share/lima/templates/default.yaml": "template " + origin,
            "cli-plugins/docker-buildx": SIMPLE_STUB.format(origin=origin, name="buildx"),
        }

    def make_bundle(self, world, kind, quarantined):
        bundle = world["bundle"]
        origin = "bundle-resigned" if kind == "resigned" else "bundle"
        files = self.program_files(origin)
        for relative, text in files.items():
            write_executable(bundle / relative, text)
        (bundle / "vm").mkdir(parents=True)
        (bundle / "vm" / self.pins["image"]).write_bytes(b"a starting disk")
        arch = "x86_64" if kind == "otherArch" else "arm64"
        pins = self.pins["line"]
        if kind == "otherPins":
            pins = pins.replace("v0.10.3", "v0.9.9")
        lines = ["arch " + arch, pins, "image vm/" + self.pins["image"]]
        for relative in sorted(files):
            lines.append(sha256_of(bundle / relative) + "  " + relative)
        (bundle / "MANIFEST").write_text("\n".join(lines) + "\n", encoding="utf-8")
        if kind == "damaged":
            (bundle / "bin" / "docker").write_text("#!/bin/bash\n# damaged\n", encoding="utf-8")
        if quarantined:
            for path in bundle.rglob("*"):
                if path.is_file():
                    subprocess.run(["xattr", "-w", "com.apple.quarantine", "0083;00000000;Safari;", str(path)], check=True)

    def serve_downloads(self, world, serves):
        """The four downloads for both kinds of Mac, and the pins that match them."""
        overrides = {}
        if serves == "nothing":
            return self.pin_overrides_for({})
        built = world["root"] / "built"
        for arch, lima_arch, docker_arch, buildx_arch in [("arm64", "arm64", "aarch64", "arm64"),
                                                          ("x86_64", "x86_64", "x86_64", "amd64")]:
            folder = built / arch
            files = self.program_files("download-" + arch)
            staging = folder / "lima"
            for relative in ["bin/limactl", "bin/lima", "share/lima/lima-guestagent.Linux-aarch64.gz",
                             "share/lima/templates/default.yaml"]:
                write_executable(staging / relative, files[relative])
            write_executable(staging / "libexec" / "lima" / "limactl-mcp", "#!/bin/bash\n")
            (staging / "share" / "doc" / "lima").mkdir(parents=True)
            os.symlink("../../lima/templates", staging / "share" / "doc" / "lima" / "templates")
            lima_archive = folder / "lima.tar.gz"
            with tarfile.open(lima_archive, "w:gz") as archive:
                archive.add(staging, arcname=".")
            docker_folder = folder / "docker-archive"
            write_executable(docker_folder / "docker" / "docker", files["bin/docker"])
            docker_archive = folder / "docker.tgz"
            with tarfile.open(docker_archive, "w:gz") as archive:
                archive.add(docker_folder / "docker", arcname="docker")
            colima_file = folder / "colima"
            write_executable(colima_file, files["bin/colima"])
            buildx_file = folder / "buildx"
            write_executable(buildx_file, files["cli-plugins/docker-buildx"])

            pins = self.version_pins()
            urls = {
                "LIMA": ("https://github.com/lima-vm/lima/releases/download/v%s/lima-%s-Darwin-%s.tar.gz"
                         % (pins["LIMA_VERSION"], pins["LIMA_VERSION"], lima_arch), lima_archive),
                "COLIMA": ("https://github.com/abiosoft/colima/releases/download/%s/colima-Darwin-%s"
                           % (pins["COLIMA_VERSION"], arch), colima_file),
                "DOCKER_CLI": ("https://download.docker.com/mac/static/stable/%s/docker-%s.tgz"
                               % (docker_arch, pins["DOCKER_CLI_VERSION"]), docker_archive),
                "BUILDX": ("https://github.com/docker/buildx/releases/download/%s/buildx-%s.darwin-%s"
                           % (pins["BUILDX_VERSION"], pins["BUILDX_VERSION"], buildx_arch), buildx_file),
            }
            suffix = "ARM64" if arch == "arm64" else "X86_64"
            for name, (url, source) in urls.items():
                shutil.copy(source, world["served"] / url.replace("/", "_").replace(":", "_"))
                digest = sha256_of(source)
                if serves == "wrongBytes":
                    digest = "0" * 64
                overrides[name + "_SHA256_" + suffix] = digest
        return self.pin_overrides_for(overrides)

    def pin_overrides_for(self, overrides):
        lines = []
        for name in ["LIMA", "COLIMA", "DOCKER_CLI", "BUILDX"]:
            for suffix in ["ARM64", "X86_64"]:
                key = name + "_SHA256_" + suffix
                lines.append(key + '="' + overrides.get(key, "f" * 64) + '"')
        return "\n".join(lines)

    def version_pins(self):
        found = {}
        for line in self.block:
            for name in ["COLIMA_VERSION", "LIMA_VERSION", "DOCKER_CLI_VERSION", "BUILDX_VERSION"]:
                if line.startswith(name + '="'):
                    found[name] = line.split('"')[1]
        return found

    def install_tool(self, world, tool, origin, where="tools"):
        files = self.program_files(origin)
        paths = {"colima": ["bin/colima"], "limactl": ["bin/limactl", "bin/lima", "share/lima/lima-guestagent.Linux-aarch64.gz"],
                 "docker": ["bin/docker"]}[tool]
        for relative in paths:
            if where == "tools":
                write_executable(world["tools"] / relative, files[relative])
            elif relative.startswith("bin/"):
                write_executable(world["elsewhere"] / relative[len("bin/"):], files[relative])

    def write_stamp(self, world, tools, pins):
        lines = [pins, "source downloaded"]
        for tool in tools:
            for relative in {"colima": ["bin/colima"], "limactl": ["bin/limactl", "bin/lima"], "docker": ["bin/docker"]}[tool]:
                lines.append(sha256_of(world["tools"] / relative) + "  " + relative)
        (world["tools"] / ".installed").write_text("\n".join(lines) + "\n", encoding="utf-8")

    def arrange_before(self, world, before):
        stamped = []
        for tool in ["colima", "limactl", "docker"]:
            state = before[tool]
            if state == "elsewhere":
                self.install_tool(world, tool, "elsewhere", where="elsewhere")
            elif state in ["current", "damaged", "unrecorded"]:
                self.install_tool(world, tool, "old")
                stamped.append(tool)
        if before["stamp"] == "current":
            self.write_stamp(world, stamped, self.pins["line"])
        elif before["stamp"] == "different":
            self.write_stamp(world, stamped, self.pins["line"].replace("v0.10.3", "v0.9.9"))
        for tool in ["colima", "limactl", "docker"]:
            if before[tool] == "damaged":
                (world["tools"] / {"colima": "bin/colima", "limactl": "bin/limactl", "docker": "bin/docker"}[tool]).write_text(
                    DOCKER_STUB.format(origin="old") + "# damaged\n", encoding="utf-8")
        plugins = world["home"] / ".docker" / "cli-plugins"
        if before["buildx"] == "present":
            write_executable(plugins / "docker-buildx", SIMPLE_STUB.format(origin="old", name="buildx"))
        elif before["buildx"] == "link":
            plugins.mkdir(parents=True)
            os.symlink("/Applications/Docker.app/nowhere/docker-buildx", plugins / "docker-buildx")

    def run_block(self, world, strict, bundle_set, overrides, extra_environment):
        prologue = []
        if strict:
            prologue.append("set -euo pipefail")
        prologue.append('TOOLS_DIR="$HOME/Library/Application Support/Plantoir/tools"')
        prologue.append('export PATH="$TOOLS_DIR/bin:$PATH"')
        prologue.append(wait_for_docker_function())
        script = "\n".join(prologue + self.block[:-1] + [overrides, "ensure_container_runtime", 'echo "BLOCK-FINISHED"'])
        environment = {
            "HOME": str(world["home"]),
            "PATH": ":".join([str(world["stubs"]), str(world["elsewhere"]), "/usr/bin", "/bin", "/usr/sbin", "/sbin"]),
            "STUB_SERVED": str(world["served"]),
            "TMPDIR": str(world["root"]) + "/",
            "LANG": "en_US.UTF-8",
        }
        if bundle_set:
            environment["PLANTOIR_BUNDLED_HELPERS"] = str(world["bundle"])
        environment.update(extra_environment)
        return subprocess.run([BASH, "-c", script], capture_output=True, text=True, env=environment, timeout=120)

    def tree_fingerprint(self, folder):
        found = {}
        if not folder.exists():
            return found
        for path in sorted(folder.rglob("*")):
            relative = str(path.relative_to(folder))
            if path.is_file() and not path.is_symlink():
                attributes = subprocess.run(["xattr", str(path)], capture_output=True, text=True).stdout
                found[relative] = sha256_of(path) + " " + attributes.strip() + " " + oct(path.stat().st_mode)
            else:
                found[relative] = "folder"
        return found

    def origin_of(self, path):
        if not path.exists():
            return "none"
        for line in path.read_text(encoding="utf-8").split("\n"):
            if line.startswith("# FROM="):
                return line[len("# FROM="):].split(" ")[0]
        return "unknown"

    def markers_in(self, output, prefix):
        found = []
        for line in output.split("\n"):
            if line.startswith(prefix):
                found.append(line[len(prefix):].strip())
        return found

    # MARK: - Running a case

    def run_install_case(self, case, strict):
        world = self.make_world()
        bundle_kind = case["bundle"]
        if bundle_kind != "absent":
            self.make_bundle(world, bundle_kind, case.get("quarantined", False))
        overrides = self.serve_downloads(world, case["downloadsServe"])
        self.arrange_before(world, case["before"])
        if case["dockerAnswers"]:
            (world["home"] / ".stub-docker-answers").touch()
            if case["before"]["docker"] != "missing":
                (world["home"] / ".colima" / "default").mkdir(parents=True)
        else:
            (world["home"] / ".colima" / "default").mkdir(parents=True)
        before_tools = {}
        for tool, relative in [("colima", "bin/colima"), ("limactl", "bin/limactl"), ("docker", "bin/docker")]:
            before_tools[tool] = self.origin_of(world["tools"] / relative)
        before_tools["buildx"] = self.origin_of(world["home"] / ".docker" / "cli-plugins" / "docker-buildx")
        stamp_before = (world["tools"] / ".installed").read_bytes() if (world["tools"] / ".installed").exists() else None
        bundle_before = self.tree_fingerprint(world["bundle"])

        result = self.run_block(world, strict, bundle_kind != "absent", overrides,
                                {"STUB_ARCH": case["arch"]})
        output = result.stdout + result.stderr
        expect = case["expect"]
        self.assertEqual(result.returncode, expect["exit"], output)
        if expect["exit"] == 0:
            self.assertIn("BLOCK-FINISHED", output)

        # Which copy each program is now.
        arch_origin = "download-" + case["arch"]
        for tool, relative in [("colima", "bin/colima"), ("limactl", "bin/limactl"), ("docker", "bin/docker"),
                               ("buildx", None)]:
            if tool == "buildx":
                path = world["home"] / ".docker" / "cli-plugins" / "docker-buildx"
            else:
                path = world["tools"] / relative
            wanted = expect["tools"][tool]
            if path.is_symlink():
                now = "link"
            else:
                now = self.origin_of(path)
            if wanted == "bundled":
                self.assertIn(now, ["bundle", "bundle-resigned"], tool + "\n" + output)
            elif wanted == "downloaded":
                self.assertEqual(now, arch_origin, tool + "\n" + output)
            elif wanted == "asFound":
                self.assertEqual(now, "none", tool + " was installed over a copy found elsewhere\n" + output)
                self.assertEqual(self.origin_of(world["elsewhere"] / tool), "elsewhere")
            elif wanted == "unchanged":
                expected_now = "link" if case["before"].get(tool) == "link" else before_tools[tool]
                self.assertEqual(now, expected_now, tool + "\n" + output)
            elif wanted == "none":
                self.assertEqual(now, "none", tool + "\n" + output)
        if expect["tools"]["limactl"] in ["bundled", "downloaded"]:
            self.assertTrue((world["tools"] / "bin" / "lima").exists(), "Colima needs the lima wrapper beside limactl")
            self.assertTrue((world["tools"] / "share" / "lima" / "lima-guestagent.Linux-aarch64.gz").exists())

        # The downloads, and that they were for this kind of Mac.
        downloads_file = world["home"] / ".stub-downloads"
        downloads = downloads_file.read_text().strip().split("\n") if downloads_file.exists() else []
        self.assertEqual(len(downloads), expect["downloads"], output)
        for url in downloads:
            if case["arch"] == "x86_64":
                self.assertRegex(url, r"x86_64|amd64", url)
            else:
                self.assertRegex(url, r"arm64|aarch64", url)
        self.assertEqual(output.count("📦 Downloading what your website builder needs ("), expect["downloads"], output)

        # What was printed.
        printed = self.contract["printed"]
        for key in ["preparingHelpers", "keptTheCopyHere"]:
            self.assertEqual(printed[key] in output, key in expect["printed"], key + "\n" + output)
        self.assertEqual("❌ Could not download what your website builder needs (" in output,
                         "downloadFailed" in expect["printed"], output)

        # The lines the app reads.
        wanted_markers = []
        for marker in expect["markers"]:
            wanted_markers.append(marker.replace("{pins}", self.pins["word"]))
        self.assertEqual(self.markers_in(output, "PLANTOIR_HELPERS_INSTALLED:"), wanted_markers, output)

        # The stamp.
        stamp = world["tools"] / ".installed"
        if expect["stamp"] == "none":
            self.assertFalse(stamp.exists(), output)
        elif expect["stamp"] == "unchanged":
            now = stamp.read_bytes() if stamp.exists() else None
            self.assertEqual(now, stamp_before, output)
        else:
            text = stamp.read_text(encoding="utf-8")
            self.assertIn(self.pins["line"] + "\n", text)
            self.assertIn("source " + expect["stamp"] + "\n", text)
            checked = subprocess.run(["shasum", "-a", "256", "-c", "--status", str(stamp)], cwd=world["tools"])
            self.assertEqual(checked.returncode, 0, "the stamp does not describe what was installed:\n" + text)

        # Nothing written inside the app, nothing left half-done, nothing marked.
        self.assertEqual(self.tree_fingerprint(world["bundle"]), bundle_before, "the app's copy was changed")
        for folder in [world["tools"], world["home"] / ".docker" / "cli-plugins"]:
            if folder.exists():
                self.assertEqual([p.name for p in folder.iterdir() if p.name.startswith(".staging")], [], output)
        if world["tools"].exists():
            for path in world["tools"].rglob("*"):
                if path.is_file() and not path.is_symlink():
                    attributes = subprocess.run(["xattr", str(path)], capture_output=True, text=True).stdout
                    self.assertNotIn("com.apple.quarantine", attributes, str(path))

    def run_first_start_case(self, case, strict):
        world = self.make_world()
        if case["bundle"] != "absent":
            self.make_bundle(world, "otherArch" if case["bundle"] == "otherArch" else "present", False)
        overrides = self.serve_downloads(world, "pinned")
        for tool in ["colima", "limactl", "docker"]:
            self.install_tool(world, tool, "old")
        self.write_stamp(world, ["colima", "limactl", "docker"], self.pins["line"])
        write_executable(world["home"] / ".docker" / "cli-plugins" / "docker-buildx", SIMPLE_STUB.format(origin="old", name="buildx"))
        if case["vmExists"]:
            (world["home"] / ".colima" / "default").mkdir(parents=True)
        bundle_before = self.tree_fingerprint(world["bundle"])

        result = self.run_block(world, strict, case["bundle"] != "absent", overrides, {"STUB_SEED": case["seed"]})
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        self.assertIn("BLOCK-FINISHED", output)

        cpus = subprocess.run([BASH, "-c", "\n".join(self.block[:-1]) + "\n_colima_cpus"], capture_output=True, text=True).stdout.strip()
        memory = subprocess.run([BASH, "-c", "\n".join(self.block[:-1]) + "\n_colima_memory_gb"], capture_output=True, text=True).stdout.strip()
        wanted = []
        for arguments in case["expect"]["starts"]:
            words = []
            for word in arguments:
                word = word.replace("{cpus}", cpus).replace("{memory}", memory)
                word = word.replace("{bundle}", str(world["bundle"])).replace("{image}", self.pins["image"])
                words.append("[" + word + "]")
            wanted.append(" ".join(["colima start"] + words).strip())
        log = world["home"] / ".stub-log"
        starts = log.read_text().strip().split("\n") if log.exists() else []
        self.assertEqual(starts, wanted, output)

        markers = self.markers_in(output, "PLANTOIR_BUILDER_CREATED:")
        if case["expect"]["marker"] is None:
            self.assertEqual(markers, [], output)
        else:
            self.assertEqual(len(markers), 1, output)
            shape = case["expect"]["marker"].split(" ")
            words = markers[0].split(" ")
            self.assertEqual(words[0], shape[0], output)
            self.assertEqual(len(words), 2, output)
            self.assertTrue(words[1].isdigit(), output)

        printed = self.contract["printed"]
        for key in ["firstStartSeeded", "firstStartDownloading"]:
            self.assertEqual(printed[key] in output, key in case["expect"]["printed"], key + "\n" + output)
        self.assertNotIn("600 MB", output)
        self.assertEqual(self.tree_fingerprint(world["bundle"]), bundle_before, "the app's copy was changed")
        self.assertEqual(self.markers_in(output, "PLANTOIR_HELPERS_INSTALLED:"), [], output)


if __name__ == "__main__":
    unittest.main()
