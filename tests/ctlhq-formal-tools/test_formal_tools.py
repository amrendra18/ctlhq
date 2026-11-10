import contextlib
import hashlib
import importlib.machinery
import importlib.util
import io
import os
from pathlib import Path
import shlex
import subprocess
import tarfile
import tempfile
import unittest
from unittest.mock import patch
import urllib.error


TOOL = Path(__file__).resolve().parents[2] / "bin/ctlhq-formal-tools"


class Response(io.BytesIO):
    def __init__(self, data, url):
        super().__init__(data)
        self.url = url

    def geturl(self):
        return self.url


class FormalToolsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not TOOL.is_file():
            raise AssertionError("ctlhq-formal-tools does not exist; implement the command after this failing test")
        loader = importlib.machinery.SourceFileLoader("formal_tools_under_test", str(TOOL))
        spec = importlib.util.spec_from_loader(loader.name, loader)
        cls.tool = importlib.util.module_from_spec(spec)
        loader.exec_module(cls.tool)

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="formal-tools-test-")
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name) / "home with space"
        self.home.mkdir()
        self.tools_root = self.home / ".ctlhq/tools"
        self.destination = self.tools_root / "formal"
        self.java_home = self.destination / "java" / "Contents" / "Home"
        self.archive_root = "jdk-25.0.4.1+1"
        self.java_bytes = b"stand-in Java, never execute this file\n"
        self.jar_bytes = b"stand-in tla2tools 1.7.4\n"
        self.archive = self.make_archive()
        self.downloads = Path(self.temp.name) / "stand-in-downloads"
        self.downloads.mkdir()
        self.calls = []
        self.stack = contextlib.ExitStack()
        self.addCleanup(self.stack.close)
        self.stack.enter_context(patch.object(self.tool.Path, "home", return_value=self.home))
        self.stack.enter_context(patch.object(self.tool.platform, "system", return_value="Darwin"))
        self.stack.enter_context(patch.object(self.tool.platform, "machine", return_value="arm64"))
        self.set_downloads(self.archive, self.jar_bytes)
        builder = self.stack.enter_context(patch.object(self.tool.urllib.request, "build_opener"))
        self.opener = builder.return_value.open
        self.opener.side_effect = self.open_download

    def make_archive(self, extra=None, release=None):
        data = io.BytesIO()
        java_home = Path(self.archive_root) / "Contents" / "Home"
        files = {
            (java_home / "bin" / "java").as_posix(): self.java_bytes,
            (java_home / "release").as_posix(): (
                release or 'JAVA_RUNTIME_VERSION="25.0.4.1+1"\nIMPLEMENTOR="Eclipse Adoptium"\n'
            ).encode(),
        }
        with tarfile.open(fileobj=data, mode="w:gz") as archive:
            for name, content in files.items():
                member = tarfile.TarInfo(name)
                member.size = len(content)
                member.mode = 0o755 if name.endswith("/java") else 0o644
                archive.addfile(member, io.BytesIO(content))
            if extra is not None:
                member, content = extra
                archive.addfile(member, io.BytesIO(content) if content is not None else None)
        return data.getvalue()

    def set_downloads(self, archive, jar):
        self.java_download = self.downloads / "java.tar.gz"
        self.tlc_download = self.downloads / "tla2tools.jar"
        self.java_download.write_bytes(archive)
        self.tlc_download.write_bytes(jar)
        self.stack.enter_context(patch.object(self.tool, "JAVA_SHA256", hashlib.sha256(archive).hexdigest()))
        self.stack.enter_context(patch.object(self.tool, "TLC_SHA256", hashlib.sha256(jar).hexdigest()))

    def open_download(self, request, timeout):
        url = request.full_url if hasattr(request, "full_url") else request
        self.calls.append(url)
        if url == self.tool.JAVA_URL:
            return Response(self.java_download.read_bytes(), url)
        if url == self.tool.TLC_URL:
            return Response(self.tlc_download.read_bytes(), url)
        raise AssertionError(f"unexpected download {url}")

    def run_tool(self, *args):
        stdout, stderr = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            result = self.tool.main(list(args))
        return result, stdout.getvalue(), stderr.getvalue()

    def install(self):
        result, out, err = self.run_tool("install")
        self.assertEqual(result, 0, err)
        return out

    def test_help_and_usage(self):
        result = subprocess.run([str(TOOL), "--help"], text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(result.stdout.startswith("ctlhq-formal-tools: "))
        for word in ("check", "install", "env", "Exit codes", "25.0.4.1+1", "1.7.4", "2026-08-19", "2024-08-05"):
            self.assertIn(word, result.stdout)
        for args in ([], ["bad"], ["check", "extra"], ["install", "--force"]):
            with self.subTest(args=args):
                self.assertEqual(self.run_tool(*args)[0], 2)

    def test_approved_pins(self):
        loader = importlib.machinery.SourceFileLoader("formal_tools_pins", str(TOOL))
        spec = importlib.util.spec_from_loader(loader.name, loader)
        module = importlib.util.module_from_spec(spec)
        loader.exec_module(module)
        self.assertEqual(module.JAVA_SHA256, "61979887f7506a24a57439ff99adb8b3a7fc89977d9cfe3b8984f58a981b7b9d")
        self.assertEqual(module.TLC_SHA256, "936a262061c914694dfd669a543be24573c45d5aa0ff20a8b96b23d01e050e88")
        self.assertEqual(module.JAVA_URL, "https://github.com/adoptium/temurin25-binaries/releases/download/jdk-25.0.4.1%2B1/OpenJDK25U-jdk_aarch64_mac_hotspot_25.0.4.1_1.tar.gz")
        self.assertEqual(module.TLC_URL, "https://github.com/tlaplus/tlaplus/releases/download/v1.7.4/tla2tools.jar")

    def test_missing_tools_create_nothing(self):
        result, out, err = self.run_tool("check")
        self.assertEqual(result, 1)
        self.assertIn("Java", out)
        self.assertIn("TLC", out)
        self.assertIn("missing", out)
        self.assertFalse(self.tools_root.exists())
        self.assertEqual(self.calls, [])
        result, out, err = self.run_tool("env")
        self.assertEqual(result, 1)
        self.assertEqual(out, "")
        self.assertIn("ctlhq-formal-tools install", err)
        self.assertFalse(self.tools_root.exists())

    def test_install_check_and_shell_safe_env(self):
        out = self.install()
        java = self.java_home / "bin" / "java"
        jar = self.destination / "tla2tools.jar"
        self.assertEqual(java.read_bytes(), self.java_bytes)
        self.assertEqual(jar.read_bytes(), self.jar_bytes)
        self.assertTrue(os.access(java, os.X_OK))
        self.assertIn(str(java), out)
        self.assertIn(str(jar), out)
        self.assertEqual(self.calls, [self.tool.JAVA_URL, self.tool.TLC_URL])
        self.assertEqual(self.run_tool("check")[0], 0)
        result, out, err = self.run_tool("env")
        self.assertEqual(result, 0, err)
        self.assertEqual(shlex.split(out), [f"JAVA={java}", f"TLA2TOOLS={jar}"])
        self.assertEqual(len(out.splitlines()), 2)
        self.assertEqual(sorted(p.name for p in self.tools_root.iterdir()), ["formal"])

    def test_wrong_java_checksum_refuses_before_unpacking(self):
        self.java_download.write_bytes(b"deliberately broken checksum test input")
        with patch.object(self.tool, "extract_java") as extract:
            result, out, err = self.run_tool("install")
            extract.assert_not_called()
        self.assertEqual(result, 1)
        self.assertIn("SHA-256", err)
        self.assertFalse(self.destination.exists())
        self.assertEqual(list(self.tools_root.iterdir()), [])
        self.assertEqual(self.calls, [self.tool.JAVA_URL])

    def test_wrong_tlc_checksum_leaves_no_install_and_can_retry(self):
        self.tlc_download.write_bytes(b"deliberately broken checksum test input")
        result, out, err = self.run_tool("install")
        self.assertEqual(result, 1)
        self.assertIn("SHA-256", err)
        self.assertFalse(self.destination.exists())
        self.assertEqual(list(self.tools_root.iterdir()), [])
        self.tlc_download.write_bytes(self.jar_bytes)
        self.install()

    def test_existing_install_is_never_overwritten(self):
        self.install()
        before = (self.destination / "tla2tools.jar").read_bytes()
        self.calls.clear()
        result, out, err = self.run_tool("install")
        self.assertEqual(result, 1)
        self.assertIn("refuse", err.lower())
        self.assertEqual(self.calls, [])
        self.assertEqual((self.destination / "tla2tools.jar").read_bytes(), before)

    def test_empty_or_broken_symlink_destination_is_never_overwritten(self):
        self.tools_root.mkdir(parents=True)
        for kind in ("empty", "symlink"):
            with self.subTest(kind=kind):
                if kind == "empty":
                    self.destination.mkdir()
                else:
                    self.destination.symlink_to(self.home / "absent")
                self.assertEqual(self.run_tool("install")[0], 1)
                self.assertEqual(self.calls, [])
                if kind == "empty":
                    self.destination.rmdir()
                else:
                    self.destination.unlink()

    def test_another_install_lock_is_kept(self):
        self.tools_root.mkdir(parents=True)
        lock = self.tools_root / ".formal-install.lock"
        lock.mkdir()
        result, out, err = self.run_tool("install")
        self.assertEqual(result, 1)
        self.assertIn("install", err.lower())
        self.assertTrue(lock.is_dir())
        self.assertEqual(self.calls, [])

    def test_network_failure_leaves_no_partial_install(self):
        self.opener.side_effect = urllib.error.URLError("stand-in network failure")
        result, out, err = self.run_tool("install")
        self.assertEqual(result, 1)
        self.assertIn("stand-in network failure", err)
        self.assertFalse(self.destination.exists())
        self.assertEqual(list(self.tools_root.iterdir()), [])

    def test_interrupted_download_cleans_staging_and_lock(self):
        response = Response(self.archive, self.tool.JAVA_URL)
        with patch.object(response, "read", side_effect=[b"partial stand-in", urllib.error.URLError("interrupted stand-in download")]):
            self.opener.side_effect = None
            self.opener.return_value = response
            result, out, err = self.run_tool("install")
        self.assertEqual(result, 1)
        self.assertIn("interrupted stand-in download", err)
        self.assertFalse(self.destination.exists())
        self.assertEqual(list(self.tools_root.iterdir()), [])

    def test_plain_http_source_and_redirect_are_refused(self):
        with patch.object(self.tool, "JAVA_URL", "http://example.invalid/java"):
            self.assertEqual(self.run_tool("install")[0], 1)
            self.opener.assert_not_called()
        self.opener.side_effect = lambda request, timeout: Response(self.archive, "http://example.invalid/redirect")
        self.assertEqual(self.run_tool("install")[0], 1)
        self.assertFalse(self.destination.exists())

    def test_redirect_handler_stops_https_downgrades_before_requesting(self):
        handler = self.tool.HttpsRedirects()
        request = self.tool.urllib.request.Request(self.tool.JAVA_URL)
        with self.assertRaises(ValueError):
            handler.redirect_request(request, None, 302, "Found", {}, "http://example.invalid/java")
        redirected = handler.redirect_request(request, None, 302, "Found", {}, "https://example.invalid/java")
        self.assertEqual(redirected.full_url, "https://example.invalid/java")

    def test_lts_release_metadata_is_accepted(self):
        self.set_downloads(self.make_archive(release='JAVA_RUNTIME_VERSION="25.0.4.1+1-LTS"\nIMPLEMENTOR="Eclipse Adoptium"\n'), self.jar_bytes)
        self.install()
        self.assertEqual(self.run_tool("check")[0], 0)

    def test_unsafe_archive_paths_and_special_files_are_refused(self):
        for name, kind in (("../escaped", tarfile.REGTYPE), ("/escaped", tarfile.REGTYPE), (f"{self.archive_root}/device", tarfile.CHRTYPE)):
            with self.subTest(name=name):
                member = tarfile.TarInfo(name)
                member.type = kind
                content = b"bad" if kind == tarfile.REGTYPE else None
                member.size = len(content) if content else 0
                self.set_downloads(self.make_archive((member, content)), self.jar_bytes)
                result, out, err = self.run_tool("install")
                self.assertEqual(result, 1)
                self.assertFalse(self.destination.exists())
                self.assertFalse((self.tools_root / "escaped").exists())

    def test_archive_links_are_refused(self):
        member = tarfile.TarInfo((Path(self.archive_root) / "Contents" / "Home" / "link").as_posix())
        member.type = tarfile.SYMTYPE
        member.linkname = "../../../../escaped"
        self.set_downloads(self.make_archive((member, None)), self.jar_bytes)
        self.assertEqual(self.run_tool("install")[0], 1)
        self.assertFalse(self.destination.exists())
        member.linkname = "bin/java"
        self.set_downloads(self.make_archive((member, None)), self.jar_bytes)
        self.assertEqual(self.run_tool("install")[0], 1)
        self.assertFalse(self.destination.exists())

    def test_wrong_release_metadata_and_missing_java_are_refused(self):
        self.set_downloads(self.make_archive(release='JAVA_RUNTIME_VERSION="25.0.3+1"\nIMPLEMENTOR="Eclipse Adoptium"\n'), self.jar_bytes)
        self.assertEqual(self.run_tool("install")[0], 1)
        self.assertFalse(self.destination.exists())
        self.set_downloads(self.archive, self.jar_bytes)
        self.install()
        (self.java_home / "bin" / "java").unlink()
        self.assertEqual(self.run_tool("check")[0], 1)
        self.assertEqual(self.run_tool("env")[1], "")

    def test_other_java_vendor_is_refused(self):
        self.set_downloads(self.make_archive(release='JAVA_RUNTIME_VERSION="25.0.4.1+1"\nIMPLEMENTOR="Different vendor"\n'), self.jar_bytes)
        self.assertEqual(self.run_tool("install")[0], 1)
        self.assertFalse(self.destination.exists())

    def test_corrupt_installed_jar_and_nonexecutable_java_are_refused(self):
        self.install()
        jar = self.destination / "tla2tools.jar"
        jar.write_bytes(b"tampered test input")
        result, out, err = self.run_tool("check")
        self.assertEqual(result, 1)
        self.assertIn("SHA-256", out)
        self.assertEqual(self.run_tool("env")[1], "")
        jar.write_bytes(self.jar_bytes)
        (self.java_home / "bin" / "java").chmod(0o644)
        self.assertEqual(self.run_tool("check")[0], 1)

    def test_unsupported_platforms_do_not_write_or_download(self):
        for system, machine in (("Linux", "aarch64"), ("Darwin", "x86_64")):
            with self.subTest(system=system, machine=machine):
                with patch.object(self.tool.platform, "system", return_value=system), patch.object(self.tool.platform, "machine", return_value=machine):
                    for command in ("check", "install", "env"):
                        result, out, err = self.run_tool(command)
                        self.assertEqual(result, 1)
                        self.assertIn("not supported", err)
        self.assertFalse(self.tools_root.exists())
        self.assertEqual(self.calls, [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
