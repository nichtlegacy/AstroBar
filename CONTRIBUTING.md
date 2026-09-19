# Contributing to AstroBar

Thanks for your interest in improving AstroBar — contributions, feedback and hardware
reports are very welcome.

AstroBar is a native macOS menu bar app for the **Astro A50 (Gen 4)** wireless headset
and base station. It talks to the base station directly over USB HID; the wire protocol
was reverse-engineered by [tdryer/eh-fifty](https://github.com/tdryer/eh-fifty), and the
app architecture is inspired by [steipete/CodexBar](https://github.com/steipete/CodexBar).

## Requirements

- macOS 14.0 (Sonoma) or later
- Swift 6.2 toolchain (ships with Xcode 16) — the project is pure SwiftPM, no `.xcodeproj`
- Optional: an Astro A50 Gen 4 base station. The app and the unit tests run fine without
  any hardware connected; only live device reads/writes need the real thing.

## Getting started

```sh
git clone <your-fork-url> astro
cd astro

swift build                 # debug build of every product
swift test                  # unit + render tests (no hardware required)

swift run astrobar-cli dump # read-only dump of every device value (needs hardware)

make app                    # assemble a release AstroBar.app (ad-hoc signed)
make run                    # build + launch the app
make install                # install into /Applications and launch
make dmg                    # create a distributable disk image
make icon                   # regenerate the app icon (.icns)
```

## Project layout

| Path          | Contents |
|---------------|----------|
| `Sources/AstroBarCore` | HID transport, A50 protocol, models — no UI, fully unit-testable |
| `Sources/AstroBar`     | The SwiftUI/AppKit menu bar app (popover, settings, status item) |
| `Sources/AstroBarCLI`  | `astrobar-cli` diagnostic tool (`dump`, `get-eq`, `set-eq`, `selftest-write`) |
| `Tests`        | `AstroBarCoreTests` (decoding/logic) and `AstroBarUITests` (offscreen render snapshots) |
| `scripts/`     | `package_app.sh` (bundle + ad-hoc signing), `build_icon.sh` |

## How to contribute

1. Fork the repository and create a branch for your change.
2. Keep pull requests small and focused — one feature or fix per PR.
3. Make sure `swift build`, `swift test` and `swiftlint lint` all pass (CI runs them on
   every push and pull request).
4. Open a pull request against `main` describing what changed and why.

Commit messages: use a short imperative subject line — `Add side-tone slider`,
`Fix EQ preset restore`, not `added some sliders` or `update`.

## Code style

- A SwiftLint configuration lives in `.swiftlint.yml`; `swiftlint lint` must report no
  violations.
- 4-space indentation, no tabs, no trailing whitespace.
- Use `///` Swift doc comments for public API in `AstroBarCore` — it is the reusable,
  UI-free layer other tools may build on.
- New decoding/packet logic belongs in `AstroBarCore` with a unit test in
  `AstroBarCoreTests`.

## Hardware testing notes

**Writes go to the real device.** Anything that changes EQ presets, sliders, balance or
mic settings sends actual HID write reports to the base station.

- Safe without thinking: `astrobar-cli dump` (or `make dump`) is strictly read-only.
- `astrobar-cli set-eq <1-3>` writes the active EQ preset.
- `astrobar-cli selftest-write` verifies writes end-to-end: it toggles the active EQ
  preset, reads the value back and then restores the original preset.
- Test EQ and slider changes in the app UI only with a base station connected that you
  are okay with being reconfigured.
- Remember: with the headset docked on the base station the full feature set works; over
  a direct USB cable the device enumerates in cable mode and only charging works.

## Reporting issues

When reporting a bug, please include:

- Headset and base station firmware versions (visible in the dump output).
- The output of `swift run astrobar-cli dump` (safe, read-only).
- Whether the headset is connected via base station or USB cable.
- macOS version and AstroBar version/commit.

## License

AstroBar is released under the MIT License. By contributing, you agree that your
contributions will be licensed under the MIT License as well. No contributor license
agreement (CLA) is required.
