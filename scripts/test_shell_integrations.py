#!/usr/bin/env python3
"""Run real integration generators with synthetic data, without launching the app.

Unavailable app dependencies are fail-closed fixtures: calling profile/auth APIs
aborts instead of consulting local stores. Only temporary scripts and HOME/PATH
are used. Requires the macOS Swift command-line toolchain.
"""

import base64
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
FIXTURES = r'''
import Foundation
enum Constants {
    enum ClaudePaths {
        static var homeDirectory: URL { URL(fileURLWithPath: ProcessInfo.processInfo.environment["SHELL_TEST_HOME"]!) }
        static var claudeDirectory: URL { homeDirectory.appendingPathComponent(".claude") }
    }
}
struct Profile {
    let id = UUID()
    var name: String
    var terminalLauncherSlug: String? = nil
    var customKeychainServiceName: String? = nil
    var hasCliAccount = false
    var claudeSessionKey: String? = nil
    var organizationId: String? = nil
    var provider: Provider { Provider() }
}
struct Provider { var descriptor: Descriptor { Descriptor() } }
struct Descriptor { var capabilities: Capabilities { Capabilities() } }
struct Capabilities { var cliAccountSync = true }
class ProfileManager {
    static let shared = ProfileManager()
    var activeProfile: Profile? { fatalError("Tests must never consult profile/auth state") }
    func updateProfile(_ profile: Profile) { fatalError("Tests must never update profiles") }
}
class ClaudeCodeSyncService {
    static let shared = ClaudeCodeSyncService()
    func sha256HexPrefix(_ value: String, length: Int) -> String { fatalError("Not used by script tests") }
    func listClaudeCodeKeychainServices() -> [String] { fatalError("Tests must never consult Keychain") }
}
class LoggingService {
    static let shared = LoggingService()
    func log(_ message: String) {}
    func logError(_ message: String, error: Error) {}
}
class SharedDataStore {
    static let shared = SharedDataStore()
    func loadStatuslineElementColors() -> StatuslineElementColors { StatuslineElementColors() }
    func uses24HourTime() -> Bool { false }
}
class ClaudeAPIService {
    static func sessionCookieHeader(sessionKey: String, url: URL) -> String { fatalError("Tests must never read cookies") }
}
struct SessionKeyValidator {
    func isValid(_ value: String) -> Bool { fatalError("Tests must never inspect real keys") }
}
'''

MAIN = r'''
import Foundation
let args = CommandLine.arguments
let name = String(data: Data(base64Encoded: args[2])!, encoding: .utf8)!
let home = Constants.ClaudePaths.homeDirectory
if args[1] == "launcher" {
    let service = TerminalLauncherService(homeDirectory: home)
    let slug = try service.install(for: Profile(name: name))
    print(service.scriptURL(forSlug: slug).path)
} else {
    let service = StatuslineService.shared
    try service.installScripts(injectSessionKey: false)
    if args[1] == "update" {
        try service.updateProfileNameInConfig(name)
    } else {
        try service.updateConfiguration(showModel: false, showDirectory: false,
            showBranch: false, showContext: false, contextAsTokens: false,
            showUsage: false, showProgressBar: false, showResetTime: false,
            colorMode: .monochrome, showProfile: true, profileName: name)
    }
}
'''


class ShellIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.compilation = tempfile.TemporaryDirectory(prefix="shell-integration-compile-")
        directory = Path(cls.compilation.name)
        (directory / "Fixtures.swift").write_text(FIXTURES)
        (directory / "main.swift").write_text(MAIN)
        cls.generator = directory / "generate-fixture"
        sources = [
            ROOT / "Claude Usage/Shared/Services/StatuslineService.swift",
            ROOT / "Claude Usage/Shared/Services/TerminalLauncherService.swift",
            ROOT / "Claude Usage/Shared/Models/StatuslineColorMode.swift",
            ROOT / "Claude Usage/Shared/Models/StatuslineElementColors.swift",
            ROOT / "Claude Usage/Shared/Models/ClaudeUsage.swift",
            ROOT / "Claude Usage/Shared/Extensions/Date+Extensions.swift",
        ]
        helper = ROOT / "Claude Usage/Shared/Utilities/ShellLiteral.swift"
        if helper.exists():
            sources.append(helper)
        compilation = subprocess.run(["swiftc", "-module-cache-path", str(directory / "module-cache"),
                        *map(str, sources), str(directory / "Fixtures.swift"),
                        str(directory / "main.swift"), "-o", str(cls.generator)],
                       capture_output=True, text=True)
        if compilation.returncode:
            raise RuntimeError(compilation.stderr)

    @classmethod
    def tearDownClass(cls):
        cls.compilation.cleanup()

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="shell-integration-home-")
        self.home = Path(self.temporary.name)
        self.addCleanup(self.temporary.cleanup)
        self.marker = self.home / "unexpected-command"
        self.environment = dict(os.environ, HOME=str(self.home),
                                SHELL_TEST_HOME=str(self.home), PATH="/usr/bin:/bin")

    def generate(self, mode, name):
        encoded = base64.b64encode(name.encode()).decode()
        return subprocess.run([str(self.generator), mode, encoded], env=self.environment,
                              check=True, capture_output=True, text=True).stdout

    def statusline(self):
        script = self.home / ".claude/statusline-command.sh"
        result = subprocess.run(["/bin/bash", str(script)], env=self.environment,
                                input=b"{}", capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        self.assertFalse(self.marker.exists(), "Profile/config contents executed a command")
        return re.sub(r"\x1b\[[0-9;]*m", "", result.stdout.decode()).removesuffix("\n")

    def test_statusline_profile_names_are_literal_data(self):
        names = [
            "O'Reilly \"Work\" $HOME",
            f'$(touch "{self.marker}")',
            f'`touch "{self.marker}"`',
            f'first\"\ntouch "{self.marker}"\n# last',
            "עברית 日本語 \\n\ntrailing\n\n",
            "carriage\rreturn\tand tabs",
        ]
        for name in names:
            with self.subTest(name=name):
                self.marker.unlink(missing_ok=True)
                self.generate("statusline", name)
                self.assertEqual(self.statusline(), name)

    def test_statusline_legacy_config_is_data_and_preserves_valid_settings(self):
        self.generate("statusline", "placeholder")
        config = self.home / ".claude/statusline-config.txt"
        config.write_text('SHOW_MODEL=0\nSHOW_DIRECTORY=0\nSHOW_BRANCH=0\nSHOW_CONTEXT=0\n'
                          'SHOW_USAGE=0\nSHOW_WEEKLY=0\nSHOW_EXTRA_USAGE=0\n'
                          'SHOW_PROFILE=1\nCOLOR_MODE=monochrome\nPROFILE_NAME="Legacy Work"\n'
                          f'touch "{self.marker}"\nIGNORED=$(touch "{self.marker}")\n'
                          f'SINGLE_COLOR=$(touch "{self.marker}")\n'
                          f'SHOW_CONTEXT=$(touch "{self.marker}")\n')
        self.assertEqual(self.statusline(), "Legacy Work")

    def test_profile_switch_replaces_multiline_name_and_keeps_settings(self):
        self.generate("statusline", 'first\"\nsecond')
        name = f'next\'\"$(touch "{self.marker}")\nlast\n'
        self.generate("update", name)
        self.assertEqual(self.statusline(), name)
        self.assertIn("SHOW_USAGE=0", (self.home / ".claude/statusline-config.txt").read_text())

    def test_launcher_profile_comment_and_config_path_cannot_execute_commands(self):
        # The path itself contains shell substitutions, quotes, and spaces.
        adversarial_home = self.home / "O'Reilly \"$(touch unexpected-command)\" `touch unexpected-command`"
        adversarial_home.mkdir()
        self.environment.update(HOME=str(adversarial_home), SHELL_TEST_HOME=str(adversarial_home))
        fake_bin = self.home / "fake-bin"
        fake_bin.mkdir()
        fake = fake_bin / "claude"
        fake.write_text('#!/bin/bash\nprintf "%s\\0" "$CLAUDE_CONFIG_DIR" "$@"\n')
        fake.chmod(0o700)
        self.environment["PATH"] = f"{fake_bin}:/usr/bin:/bin"
        name = f'first\"\ntouch "{self.marker}"\n# last'
        script = self.generate("launcher", name).strip()
        arguments = ["argument with spaces", "$(touch unexpected-command)", "O'Reilly"]
        result = subprocess.run(["/bin/bash", script, *arguments], env=self.environment,
                                cwd=self.home, capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        self.assertFalse(self.marker.exists(), "Launcher comment/path executed a command")
        values = result.stdout.split(b"\0")[:-1]
        self.assertEqual(values[1:], [value.encode() for value in arguments])
        self.assertEqual(Path(values[0].decode()).parent, adversarial_home)


if __name__ == "__main__":
    unittest.main(verbosity=2)
