import AppKit
import Foundation

/// Shared utility for focusing the terminal running a Claude Code session.
/// Attempts IDE extension URI first (exact tab), falls back to AppleScript app activation.
enum IDETerminalFocus {

    /// Focus the terminal for a given session.
    static func focusSession(_ session: ClaudeSession) {
        focus(terminalPid: session.terminalPid, shellPid: session.shellPid)
    }

    /// Focus a terminal by PID.
    /// 1. If shellPid + IDE extension available → open URI to focus exact terminal tab
    /// 2. If terminalPid available → activate the IDE/terminal app (brings to foreground)
    /// 3. Fallback → activate first running terminal-like app
    static func focus(terminalPid: Int? = nil, shellPid: Int? = nil) {
        // Resolve bundle ID from terminalPid
        var bundleId: String?
        if let pid = terminalPid,
           let app = NSRunningApplication(processIdentifier: pid_t(pid)) {
            bundleId = app.bundleIdentifier
        }

        // Try IDE extension URI for exact terminal tab focus
        if let shellPid,
           let bundleId,
           let scheme = ExtensionInstaller.uriScheme(forBundleId: bundleId),
           UserDefaults.standard.bool(forKey: "ideExtensionEnabled") {
            let urlString = "\(scheme)://masko.masko-terminal-focus/focus?pid=\(shellPid)"
            if let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
                return
            }
        }

        // Try terminal-specific tab switching (iTerm2, Terminal.app)
        if let shellPid, let bundleId {
            if activateTerminalTab(bundleId: bundleId, shellPid: shellPid) {
                return
            }
        }

        // Fallback: bring IDE/terminal to foreground (no tab switch)
        if let bundleId {
            activateApp(bundleId: bundleId)
            return
        }

        // Last resort: find any running terminal app
        let bundleIDs = [
            "com.apple.Terminal",
            "com.googlecode.iterm2",
            "com.github.wez.wezterm",
            "net.kovidgoyal.kitty",
            "com.todesktop.230313mzl4w4u92",
            "com.microsoft.VSCode",
            "com.microsoft.VSCodeInsiders",
            "com.exafunction.windsurf",
            "dev.zed.Zed",
            "com.mitchellh.ghostty",
            "org.alacritty",
            "dev.warp.Warp-Stable",
            "com.google.antigravity",
        ]
        for id in bundleIDs {
            if NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == id }) {
                activateApp(bundleId: id)
                return
            }
        }
    }

    /// Get the tty name for a given PID (e.g. "ttys003").
    private static func ttyForPid(_ pid: Int) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-o", "tty=", "-p", "\(pid)"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch { return nil }
    }

    /// Try to switch to the exact terminal tab matching shellPid's tty.
    /// Returns true if a terminal-specific AppleScript succeeded.
    private static func activateTerminalTab(bundleId: String, shellPid: Int) -> Bool {
        guard let tty = ttyForPid(shellPid), !tty.isEmpty else { return false }
        let ttyDevice = "/dev/\(tty)"

        let script: String?
        switch bundleId {
        case "com.googlecode.iterm2":
            script = """
            tell application "iTerm2"
                activate
                repeat with aWindow in windows
                    repeat with aTab in tabs of aWindow
                        repeat with aSession in sessions of aTab
                            if tty of aSession is "\(ttyDevice)" then
                                select aTab
                                return
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            """
        case "com.apple.Terminal":
            script = """
            tell application "Terminal"
                activate
                repeat with aWindow in windows
                    repeat with aTab in tabs of aWindow
                        if tty of aTab is "\(ttyDevice)" then
                            set selected tab of aWindow to aTab
                            set index of aWindow to 1
                            return
                        end if
                    end repeat
                end repeat
            end tell
            """
        default:
            script = nil
        }

        guard let src = script else { return false }
        // Try in-process first (works in .app bundle with NSAppleEventsUsageDescription)
        if let appleScript = NSAppleScript(source: src) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if let error {
                let code = error[NSAppleScript.errorNumber] as? Int ?? 0
                // -1743 = not authorized — try osascript subprocess as fallback
                if code == -1743 {
                    return runOsascript(src)
                }
                return false
            }
            return true
        }
        return false
    }

    /// Run AppleScript via osascript subprocess (inherits caller's Automation permissions).
    private static func runOsascript(_ source: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// AppleScript `tell application id` — most reliable cross-Space activation on macOS 14+.
    private static func activateApp(bundleId: String) {
        let src = "tell application id \"\(bundleId)\" to activate"
        if let script = NSAppleScript(source: src) {
            var error: NSDictionary?
            script.executeAndReturnError(&error)
        }
    }
}
