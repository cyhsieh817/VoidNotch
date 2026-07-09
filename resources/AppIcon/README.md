# VoidNotch App Icon

| File | Use |
|:--|:--|
| `AppIcon-1024.png` | Master artwork (1024×1024) |
| `logo-mark-1024.png` | Same mark for docs / marketing |
| `AppIcon.icns` | Bundled into `VoidNotch.app` by `scripts/make_app.sh` |
| `AppIcon.iconset/` | Source sizes for `iconutil` |

## Concept

**Selected 2026-07-09: logo candidate E** — monochrome black/white abstract notch mark  
(source: vault `APPs/VoidNotch/logo-candidates/E_mono-notch-mark.jpg`).

## Rebuild

If you regenerate PNGs into `AppIcon.iconset/`:

```bash
iconutil -c icns resources/AppIcon/AppIcon.iconset -o resources/AppIcon/AppIcon.icns
./scripts/make_app.sh
```
