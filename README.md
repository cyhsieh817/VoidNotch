# VoidNotch

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue.svg)](#requirements)
[![Swift](https://img.shields.io/badge/Swift-6-orange.svg)](Package.swift)

**Turn your MacBook notch into a live dashboard** for system health, AI coding-provider usage, and agent activity.

macOS Notch 系統監控 + AI Token 用量 + Agent 活動 HUD。把瀏海變成可展開的即時儀表板。

---

## Features

| Area | What you get |
|:--|:--|
| **System** | CPU, RAM, disk, network, battery, health score, top processes, optional temps / GPU util |
| **AI usage** | Live / quota-style snapshots via [CodexBarCore](https://github.com/steipete/CodexBar) (Claude, Codex, Copilot, Gemini/Agy, Grok, …) |
| **Multi-account** | Account pool for Gemini/Agy — import, switch, per-account quota, apply back to the agy CLI |
| **Agent activity** | Live lifecycle feed from Claude Code / Codex / Gemini / Grok / pi / hermes hooks — notch alerts, per-event TTS voice alerts (zh-TW / en-US), connection diagnostics |
| **Scheduled** | launchd schedule overview across agent harnesses — run / paused / archived, with safe removal |
| **Notch UI** | Compact strip + expanded dashboard; floating gauge with selectable skins; click to expand, right-click for settings |
| **Customization** | Choose widgets per side, compact width/height, metrics selection, gauge scale & skins |
| **Language** | Traditional Chinese & English |

Unsupported providers are labeled clearly (not shown as 0% usage).

## Requirements

- macOS 14+ (Sonoma or later)
- Full **Xcode** app (not Command Line Tools only) — DynamicNotchKit needs SwiftUI `@Entry`
- Apple Silicon recommended (notch machines); non-notch Macs run but compact UX is secondary

## Install (build from source)

```bash
git clone https://github.com/cyhsieh817/VoidNotch.git
cd VoidNotch

# Build → ad-hoc signed VoidNotch.app (no Xcode GUI required)
./scripts/make_app.sh --run

# Or install into /Applications
./scripts/make_app.sh --install
```

Open `VoidNotch.xcodeproj` if you prefer Xcode Previews / debugging. Dependencies resolve from the root `Package.swift` (same pins as CLI).

First launch: allow any macOS prompts for local network / accessibility only if you enable features that need them. Token usage reads **local CLI/session data** — no VoidNotch cloud account, no telemetry.

## Usage

1. Start the app — it lives in the **menu bar** (no Dock icon by default).
2. **Compact**: system metrics and/or AI summary on the notch sides (configurable).
3. **Left-click** the notch area to expand the dashboard.
4. **Right-click** for Settings (providers, layout, metrics, alerts, schedules, language).
5. Menu bar → Refresh Token Usage when quotas look stale.

## Free vs Pro

This repository is the free, MIT-licensed Community Edition — the full observability app, no time limit, no account.

| | **Free (this repo)** | **Pro** |
|:--|:--:|:--:|
| System monitoring (CPU / RAM / temps / processes) | ✅ | ✅ |
| AI provider usage & quotas (Claude, Codex, Gemini, Grok, …) | ✅ | ✅ |
| Multi-account pool for Gemini/Agy (import, switch, per-account quota) | ✅ | ✅ |
| Agent activity feed + voice alerts + connection diagnostics | ✅ | ✅ |
| launchd schedule overview with safe removal | ✅ | ✅ |
| Floating gauge, skins, bilingual UI | ✅ | ✅ |
| **Answer agent prompts from the notch** (approve Codex commands, reply to Claude Code questions) | — | ✅ |
| Voice answering & answer-card system notifications | — | ✅ |

**Pro is a one-time purchase — US$15 for up to 3 Macs, no subscription.**
Get it at **[voidnotch.labgrimoire.com](https://voidnotch.labgrimoire.com)** —
the site also hosts a **pre-built, notarized download** (free tier included) if you'd rather skip building from source.

## Develop & test

```bash
swift run vn-selftest    # smoke tests (no XCTest host required for the harness)
swift test               # full XCTest suite
swift run vn-probe 5     # print live samples for 5 seconds
swift build --product VoidNotch
```

## Project layout

| Path | Role |
|:--|:--|
| `Sources/SystemMonitor` | Pure data layer (CPU/RAM/disk/net/battery/…) |
| `Sources/VoidNotchKit` | UI-free token/agent/launchd/layout models |
| `Sources/CSensors` | Apple Silicon thermal bridge (best-effort) |
| `App/` | SwiftUI shell (DynamicNotchKit) |
| `scripts/make_app.sh` | CLI package to `.app` |
| `Tests/` | Unit tests |

## Credits

Built with and inspired by:

| Project | Role |
|:--|:--|
| [DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit) | Notch UI shell |
| [Stats](https://github.com/exelban/stats) | System monitoring patterns (MIT) |
| [CodexBar](https://github.com/steipete/CodexBar) | Provider usage / CodexBarCore |
| [boring.notch](https://github.com/TheBoredTeam/boring.notch) | Architecture reference only (GPL — not vendored) |

See [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) for license texts.

## Contributing

Issues and pull requests are welcome.

1. Fork and create a branch from `main`
2. Keep changes focused; run `swift test` and `swift run vn-selftest` before opening a PR
3. Describe what you changed and how you verified it

Please do not commit secrets (API keys, OAuth tokens, `auth.json`, etc.).

## License

[MIT](LICENSE) © 2026 CYHsieh — source only; the **VoidNotch name and logo are trademarks** and are not covered by the MIT grant.

You are free to use, modify, and redistribute the source under the MIT terms. Attribution via the license notice is appreciated.

## Versioning & Changelog

- **Current:** see root [`VERSION`](VERSION) (`0.8.0`).
- **Rules:** [`VERSIONING.md`](VERSIONING.md) (SemVer; 0.x pre-stable; 1.0 gates).
- **History:** [CHANGELOG.md](CHANGELOG.md) (rebaselined from `0.1.0` on 2026-07-09).
