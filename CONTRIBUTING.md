# Contributing to VoidNotch

Thanks for helping improve VoidNotch.

## Setup

- macOS 14+
- Full Xcode (not Command Line Tools only)
- Clone, then:

```bash
swift test
swift run vn-selftest
./scripts/make_app.sh --run   # optional end-to-end app smoke
```

## Pull requests

- Prefer small, reviewable diffs
- Match existing Swift style and module boundaries (`SystemMonitor` / `VoidNotchKit` stay UI-free)
- Add or update tests when behavior changes
- Do not commit personal notes, local docs dumps, credentials, or machine samples

## Reporting bugs

Include:

- macOS version and chip (e.g. M4 Pro)
- VoidNotch build method (`make_app.sh` / Xcode)
- Steps to reproduce
- Whether the issue is system metrics, token providers, or notch UI

## License

By contributing, you agree that your contributions are licensed under the same [MIT License](LICENSE) as the project.
