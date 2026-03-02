<p align="center">
  <img src="Sources/Resources/Images/app-icon.png" width="128" />
</p>

<h1 align="center">Masko for Claude Code</h1>

<p align="center">
  A living mascot that floats above your windows, reacts to Claude Code, and lets you handle everything without leaving your flow.
</p>

<p align="center">
  <a href="https://github.com/RousselPaul/masko-for-claude-code/releases/latest"><img src="https://img.shields.io/github/v/release/RousselPaul/masko-for-claude-code?style=flat-square&color=f95d02" alt="Release" /></a>
  <img src="https://img.shields.io/badge/macOS-14.0%2B-black?style=flat-square&logo=apple" alt="macOS 14+" />
  <img src="https://img.shields.io/badge/Apple%20Silicon-arm64-black?style=flat-square" alt="Apple Silicon" />
  <img src="https://img.shields.io/badge/license-MIT-blue?style=flat-square" alt="License" />
</p>

<p align="center">
  <a href="https://github.com/RousselPaul/masko-for-claude-code/releases/latest"><strong>Download</strong></a> · <a href="https://masko.ai/claude-code"><strong>Website</strong></a> · <a href="https://masko.ai"><strong>Custom Mascots</strong></a>
</p>

---

<!-- Add a screenshot or GIF here: ![Screenshot](docs/screenshot.png) -->

## Features

| | Feature | Description |
|---|---|---|
| 🎭 | **Animated overlay** | A mascot that floats above all windows and reacts to Claude Code state — idle, working, thinking, needs attention |
| 🔐 | **Permission handling** | Approve or deny tool use requests from a speech bubble. No window switching |
| 💬 | **Question answering** | Answer Claude's questions directly from the overlay |
| 📋 | **Plan review** | Review and approve plans without opening your terminal |
| 📊 | **Session tracking** | Monitor active sessions, subagents, and status at a glance |
| 🔔 | **Notification dashboard** | Priority levels, resolution tracking, color-coded activity feed |
| 🖥️ | **Find the right terminal** | Jump to the correct terminal tab instantly |
| 🔄 | **Auto-updates** | Built-in Sparkle updates — always on the latest version |

## How It Works

```
┌─────────────┐     hook events     ┌─────────────┐
│  Claude Code │ ──────────────────▶ │    Masko     │
│  (terminal)  │                     │  (menu bar)  │
└─────────────┘                     └─────────────┘
        │                                   │
        │  fires hooks on tool use,         │  updates mascot animation,
        │  sessions, notifications          │  shows permission prompts,
        │                                   │  tracks sessions
        ▼                                   ▼
   ~/.claude/settings.json          local HTTP :49152
```

1. **Download the app** — Install the DMG. Lives in your menu bar, no dock clutter.
2. **Grant accessibility** — First launch installs Claude Code hooks automatically into `~/.claude/settings.json`.
3. **Pick a mascot** — Choose the default Masko or bring your own from [masko.ai](https://masko.ai).
4. **Start coding** — Open a terminal, run Claude Code. Your mascot springs to life.

## Custom Mascots

The default Masko fox is included. Want your own character? Create one on [masko.ai](https://masko.ai) with AI-generated animations for every state (idle, working, attention). Export and load it into the desktop app in one click.

## VS Code Extension

The `vscode-extension/` directory includes a lightweight VS Code extension that adds click-to-focus: click the mascot overlay and it jumps to the active Claude Code terminal tab.

## Requirements

- macOS 14.0+ (Sonoma)
- Apple Silicon (M1, M2, M3, M4)
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed

## Install

Download the latest `.dmg` from [**Releases**](https://github.com/RousselPaul/masko-for-claude-code/releases/latest).

## Build from Source

```bash
git clone https://github.com/RousselPaul/masko-for-claude-code.git
cd masko-for-claude-code
swift build
swift run
```

## Project Structure

```
Sources/
├── App/             # App entry point & lifecycle
├── Models/          # Data models (sessions, events, hooks)
├── Services/        # HTTP server, hook installer, update checker
├── Stores/          # Observable state (sessions, notifications)
├── Views/           # SwiftUI views (overlay, permission prompt, dashboard)
├── Utilities/       # Helpers
└── Resources/       # Assets, images, app icon
scripts/             # DMG packaging scripts
vscode-extension/    # VS Code click-to-focus extension
```

## License

Copyright 2026 Masko. All rights reserved.
