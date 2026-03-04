import Foundation

/// Manages Claude Code hook registration in ~/.claude/settings.json
enum HookInstaller {

    // MARK: - Constants

    private static let claudeSettingsPath = NSHomeDirectory() + "/.claude/settings.json"
    private static let hookScriptPath = NSHomeDirectory() + "/.masko-desktop/hooks/hook-sender.sh"
    private static let hookCommand = "~/.masko-desktop/hooks/hook-sender.sh"

    /// All Claude Code event types we want to subscribe to
    private static let hookEvents = [
        "PreToolUse",
        "PostToolUse",
        "PostToolUseFailure",
        "Stop",
        "Notification",
        "SessionStart",
        "SessionEnd",
        "TaskCompleted",
        "PermissionRequest",
        "UserPromptSubmit",
        "SubagentStart",
        "SubagentStop",
        "PreCompact",
        "ConfigChange",
        "TeammateIdle",
        "WorktreeCreate",
        "WorktreeRemove",
    ]

    // MARK: - Public API

    /// Check if hooks are registered in ~/.claude/settings.json
    static func isRegistered() -> Bool {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: claudeSettingsPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else {
            return false
        }
        // Check that at least one event points to our hook script
        for event in hookEvents {
            if let entries = hooks[event] as? [[String: Any]],
               entries.contains(where: { entry in
                   guard let innerHooks = entry["hooks"] as? [[String: Any]] else { return false }
                   return innerHooks.contains { ($0["command"] as? String) == hookCommand }
               }) {
                return true
            }
        }
        return false
    }

    /// Register hooks globally in ~/.claude/settings.json
    static func install() throws {
        // Ensure hook script exists
        try ensureScriptExists()

        // Read existing settings (or start fresh)
        var settings: [String: Any] = [:]
        if let data = try? Data(contentsOf: URL(fileURLWithPath: claudeSettingsPath)),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings = json
        }

        // Build hooks config
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        let hookEntry: [String: Any] = [
            "matcher": "",
            "hooks": [["type": "command", "command": hookCommand]],
        ]

        for event in hookEvents {
            var entries = hooks[event] as? [[String: Any]] ?? []
            // Skip if our hook is already registered for this event
            let alreadyRegistered = entries.contains { entry in
                guard let innerHooks = entry["hooks"] as? [[String: Any]] else { return false }
                return innerHooks.contains { ($0["command"] as? String) == hookCommand }
            }
            if !alreadyRegistered {
                entries.append(hookEntry)
            }
            hooks[event] = entries
        }

        settings["hooks"] = hooks

        // Write back
        try writeSettings(settings)
    }

    /// Remove hooks from ~/.claude/settings.json
    static func uninstall() throws {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: claudeSettingsPath)),
              var settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var hooks = settings["hooks"] as? [String: Any] else {
            return // Nothing to uninstall
        }

        for event in hookEvents {
            guard var entries = hooks[event] as? [[String: Any]] else { continue }
            entries.removeAll { entry in
                guard let innerHooks = entry["hooks"] as? [[String: Any]] else { return false }
                return innerHooks.contains { ($0["command"] as? String) == hookCommand }
            }
            if entries.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = entries
            }
        }

        if hooks.isEmpty {
            settings.removeValue(forKey: "hooks")
        } else {
            settings["hooks"] = hooks
        }

        try writeSettings(settings)
    }

    private static let scriptVersion = "# version: 11"

    /// Create or update hook-sender.sh
    static func ensureScriptExists() throws {
        let scriptURL = URL(fileURLWithPath: hookScriptPath)

        // Check if existing script needs updating
        if FileManager.default.fileExists(atPath: hookScriptPath),
           let contents = try? String(contentsOf: scriptURL, encoding: .utf8),
           contents.contains(scriptVersion) {
            return // Already up to date
        }

        // Create directory
        try FileManager.default.createDirectory(
            at: scriptURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // Write script — v6: pgrep guard + capture terminal PID + block on PermissionRequest
        // Note: Claude Code fires PermissionRequest for AskUserQuestion too (confirmed).
        // Do NOT also block PreToolUse — it creates duplicate connections.
        let script = """
        #!/bin/bash
        \(scriptVersion)
        # hook-sender.sh — Forwards Claude Code hook events to masko-desktop
        # Exit instantly if the desktop app isn't running (avoids curl timeout latency)
        pgrep -xq masko-for-claude-code || exit 0
        INPUT=$(cat 2>/dev/null || echo '{}')
        EVENT_NAME=$(echo "$INPUT" | grep -o '"hook_event_name":"[^"]*"' | head -1 | cut -d'"' -f4)

        # Walk up process tree to find terminal app PID and shell PID
        TERM_PID=""
        LAST_SHELL=""
        SHELL_PID=""
        CUR=$$
        while [ "$CUR" != "1" ] && [ -n "$CUR" ]; do
          PAR=$(ps -o ppid= -p "$CUR" 2>/dev/null | tr -d ' ')
          [ -z "$PAR" ] && break
          COMM=$(ps -o comm= -p "$PAR" 2>/dev/null); COMM="${COMM##*/}"
          case "$COMM" in
            zsh|bash|fish|sh|nu|pwsh|elvish|-zsh|-bash|-fish|-sh) LAST_SHELL="$PAR" ;;
            Terminal|iTerm2|wezterm-gui|kitty|Cursor|Code|Windsurf|ghostty|alacritty|Warp|Zed) TERM_PID="$PAR"; SHELL_PID="$LAST_SHELL"; break ;;
          esac
          CUR="$PAR"
        done

        # Inject terminal_pid and shell_pid into JSON payload
        if [ -n "$TERM_PID" ]; then
          INJECT="\\"terminal_pid\\":$TERM_PID"
          [ -n "$SHELL_PID" ] && INJECT="$INJECT,\\"shell_pid\\":$SHELL_PID"
          INPUT=$(echo "$INPUT" | sed "s/}$/,$INJECT}/")
        fi

        if [ "$EVENT_NAME" = "PermissionRequest" ]; then
            # Blocking: wait indefinitely for user decision/answer
            RESPONSE=$(curl -s -w "\\n%{http_code}" -X POST \\
              -H "Content-Type: application/json" -d "$INPUT" \\
              "http://localhost:\(Constants.serverPort)/hook" \\
              --connect-timeout 2 2>/dev/null)
            HTTP_CODE=$(echo "$RESPONSE" | tail -1)
            BODY=$(echo "$RESPONSE" | sed '$d')
            [ -n "$BODY" ] && echo "$BODY"
            [ "$HTTP_CODE" = "403" ] && exit 2
            exit 0
        else
            # Fire-and-forget for all other events
            curl -s -X POST -H "Content-Type: application/json" -d "$INPUT" \\
              "http://localhost:\(Constants.serverPort)/hook" \\
              --connect-timeout 1 --max-time 2 2>/dev/null || true
            exit 0
        fi
        """

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)

        // Make executable
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: hookScriptPath
        )
    }

    // MARK: - Private

    private static func writeSettings(_ settings: [String: Any]) throws {
        // Ensure ~/.claude/ directory exists
        let claudeDir = (claudeSettingsPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: claudeDir,
            withIntermediateDirectories: true
        )

        let data = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: URL(fileURLWithPath: claudeSettingsPath))
    }
}
