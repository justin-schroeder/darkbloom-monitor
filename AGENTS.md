# Agent guide — Darkbloom Monitor

macOS menu bar app (SwiftUI `MenuBarExtra`) that monitors and controls the
[Darkbloom](https://www.darkbloom.dev) provider. No dependencies, no Xcode
project — plain SwiftPM.

## Commands

```sh
swift build                 # debug build
swift test                  # run the test suite (always run before committing)
./scripts/build-app.sh      # release build → dist/Darkbloom Monitor.app
./scripts/make-dmg.sh       # dist/*.app → dist/Darkbloom-Monitor.dmg
./scripts/release.sh patch  # tag + push a release (CI builds & publishes)
```

## Architecture

- `Sources/DarkbloomCore/` — library target; everything testable lives here.
  - `DaemonState.swift` — decodes `~/.darkbloom/daemon-state.json` (the
    provider rewrites it every heartbeat; stale after 90s). `DarkbloomPaths`
    centralizes file locations.
  - `CoordinatorAPI.swift` — REST client for `api.darkbloom.dev`. Auth reuses
    the CLI's device token (`~/.darkbloom/auth_token`) as a Bearer header.
    Decode functions are separate from network functions so tests cover them.
  - `EarningsMath.swift` — pure logic: earnings windows, hourly chart
    buckets, fleet identification.
  - `Fmt.swift` — display formatting.
- `Sources/DarkbloomMenu/` — thin executable: `AppState` (polling + CLI
  control), `MenuView` (the dropdown), `App`/`StatusIcon` (menu bar glyph).
- `Tests/DarkbloomCoreTests/` — XCTest suite over DarkbloomCore.

## Domain gotchas (hard-won, don't rediscover)

- Both `provider_id` AND `provider_key` rotate every provider restart. The
  only stable machine identity is `serial_number`, visible only while a
  machine is connected. Never group earnings history by either id.
- `/v1/me/*` coordinator endpoints require interactive Privy JWTs (web
  console sessions); the CLI device token does NOT work there. It does work
  on `/v1/provider/account-earnings`.
- `darkbloom start` with no `--model` flags blocks forever on an interactive
  picker — always pass `--model` (AppState replays them from the LaunchAgent
  plist, which survives `darkbloom stop`).
- `daemon-state.json` stats (`requests_served`, `tokens_generated`) are
  per-session counters that reset on provider restart.
- The `MenuBarExtra(.window)` panel sizes to the content's ideal height; a
  bare `ScrollView` reports zero, hence the GeometryReader measurement in
  `MenuView`.

## Conventions

- Conventional commits (`feat:`, `fix:`, `chore:`, `docs:`, `test:`,
  `refactor:`, `ci:`…) — the release changelog is generated from them.
- Releases are cut with `scripts/release.sh` from an up-to-date `main`; the
  `v*.*.*` tag triggers `.github/workflows/release.yml` (build → sign →
  notarize if secrets present → .dmg → GitHub Release).
- Never commit build artifacts (`.build/`, `dist/`), logs, or `.claude/`.
- Target macOS 14+, Swift 5.10+. Match existing code style; keep UI strings
  sentence-cased; section labels uppercase via `sectionLabel`.
