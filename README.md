# VoidNotch

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue.svg)](#requirements)
[![Swift](https://img.shields.io/badge/Swift-6-orange.svg)](Package.swift)
[![Website](https://img.shields.io/badge/website-voidnotch.com-black.svg)](https://voidnotch.com)

**See which AI agent is waiting, how much quota is left, and how your Mac is doing. In the notch.**

macOS 瀏海 HUD：系統監控、AI 用量與 agent 動態。把瀏海變成可展開的即時儀表板。

> **Just want to use it?** Download the current Apple-notarized build (free, Apple Silicon, macOS 14+) from
> **[voidnotch.com](https://voidnotch.com)**. No Xcode, no build step.
> This repository holds the MIT-licensed source snapshots, published at release tags. The latest snapshot is `v0.10.0`.

---

## What is in this source

| Area | What you get |
|:--|:--|
| **System** | CPU, RAM, disk, network, battery, health score, top processes, optional temperatures and GPU utilisation |
| **AI usage** | Quota and usage snapshots via [CodexBarCore](https://github.com/steipete/CodexBar) for Claude, Codex, Gemini (Antigravity) and Grok, read from local CLI and session data on a best-effort basis. Daily usage view with heatmap and cost trend |
| **Multi-account** | Account pool for Gemini (Antigravity): import, switch, per-account quota |
| **Agent activity** | Live status from Claude Code, Codex, Grok, pi and Hermes hooks: notch alerts, voice alerts, one-click hook wiring and connection diagnostics |
| **Scheduled** | launchd schedule overview: running, paused and archived jobs, with safe removal |
| **Notch UI** | Compact strip and expanded dashboard, menu bar mode for displays without a notch, and a draggable Floating Gauge with Seven Segment, Rings and Glass styles |
| **Customisation** | Choose widgets per side, compact width and height, which metrics to show |
| **Language** | Traditional Chinese and English |

Unsupported providers are labelled clearly, never shown as 0% usage. There is no VoidNotch account, no telemetry and no analytics backend.

## This source and the current app

The download on [voidnotch.com](https://voidnotch.com) is built from newer sources than the latest snapshot here. The MIT licence applies to the code published in this repository.

| | **This source (`v0.10.0`)** | **Current app, Free** | **Current app, Pro** |
|:--|:--:|:--:|:--:|
| System monitoring, AI usage and quotas | ✅ | ✅ | ✅ |
| Agent status, voice alerts, hook wiring | ✅ | ✅ | ✅ |
| Floating Gauge, menu bar mode, launchd schedule overview | ✅ | ✅ | ✅ |
| Providers dashboard, token stats with charts, reset credits | n/a | ✅ | ✅ |
| Quota threshold alerts and the Agent Attention inbox | n/a | ✅ | ✅ |
| Device cleanup and keyword cleanup | n/a | ✅ | ✅ |
| Virtual notch or Dynamic Island shape on displays without a notch | n/a | ✅ | ✅ |
| Six interface languages | n/a | ✅ | ✅ |
| Answer agent prompts from the notch | n/a | n/a | ✅ |
| Quota runway forecast, daily usage CSV export, cleanup history | n/a | n/a | ✅ |

Pro is a one-time licence for up to 3 Macs, not a subscription. Details, release notes and the download are on [voidnotch.com](https://voidnotch.com).

## Requirements

- macOS 14+ (Sonoma or later)
- Full **Xcode** app (not Command Line Tools only). DynamicNotchKit needs SwiftUI `@Entry`
- Apple Silicon recommended. Intel Macs can build and run this source, without temperature readings

## Install (build from source)

```bash
git clone https://github.com/cyhsieh817/VoidNotch.git
cd VoidNotch

# Build an ad-hoc signed VoidNotch.app (no Xcode GUI required)
./scripts/make_app.sh --run

# Or install into /Applications
./scripts/make_app.sh --install
```

Open `VoidNotch.xcodeproj` if you prefer Xcode Previews and debugging. Dependencies resolve from the root `Package.swift`.

On first launch, allow macOS prompts only for the features you enable. Token usage reads **local CLI and session data**, and for some providers browser session cookies.

## Usage

1. Start the app. It lives in the **menu bar** (no Dock icon by default).
2. **Compact**: system metrics and an AI summary on the notch sides (configurable).
3. **Left-click** the notch area to expand the dashboard.
4. **Right-click** for Settings (providers, layout, metrics, alerts, schedules, language).
5. Menu bar → Refresh Token Usage when quotas look stale.

## Develop & test

```bash
swift run vn-selftest    # smoke tests (no XCTest host required for the harness)
swift test              # full XCTest suite
swift run vn-probe 5    # print live samples for 5 seconds
swift build --product VoidNotch
```

## Project layout

| Path | Role |
|:--|:--|
| `Sources/SystemMonitor` | Pure data layer (CPU/RAM/disk/net/battery/…) |
| `Sources/VoidNotchKit` | UI-free token/agent/layout models |
| `Sources/CSensors` | Apple Silicon thermal bridge (best-effort) |
| `App/` | SwiftUI shell (DynamicNotchKit) |
| `resources/hooks` | Agent hook relay scripts |
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

[MIT](LICENSE) © 2026 CYHsieh

You are free to use, modify, and redistribute under the MIT terms. Attribution via the license notice is appreciated.

## Versioning & Changelog

- **This snapshot:** see root [`VERSION`](VERSION).
- **Rules:** [`VERSIONING.md`](VERSIONING.md) (SemVer; 0.x pre-stable).
- **Release notes for the app:** [voidnotch.com/en/changelog](https://voidnotch.com/en/changelog).
