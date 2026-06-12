# Darkbloom Monitor

A native macOS menu bar app for [Darkbloom](https://www.darkbloom.dev) providers.
A green or red leaf in the menu bar shows at a glance whether your Mac is
selling compute; clicking it opens a native dropdown with earnings, fleet
status, and start/stop controls.

![status: green = serving, red = stopped]

## What it shows

- **Menu bar leaf** — green when the provider is online and trusted, orange
  while connecting, red when stopped.
- **Earnings** — account balance, today / 7 days / lifetime totals, and job
  counts, straight from the Darkbloom coordinator.
- **This Mac** — model currently being served, warm models, requests served,
  tokens generated, GPU memory in use, uptime, and trust level.
- **Recent jobs** — the latest paid inference jobs with model, time, and
  payout.
- **My Macs** — shown only when more than one of your machines is online,
  with the models each is serving.
- **Controls** — Stop, Start, and Restart the provider, plus a link to the
  web console.

## Install

```sh
./scripts/build-app.sh
```

Copy `dist/Darkbloom Monitor.app` to `/Applications` and double-click it.
The app has no dock icon (`LSUIElement`); it lives only in the menu bar.
To start it at login: System Settings → General → Login Items → add the app.

Requires the [darkbloom CLI](https://github.com/Layr-Labs/d-inference) to be
installed and logged in (`darkbloom login`). The app reuses the CLI's
credentials and state — no separate setup.

## How it works

No private APIs and no extra auth — the app interfaces with exactly the same
data the CLI uses:

| Data | Source |
|------|--------|
| Local provider status | `~/.darkbloom/daemon-state.json`, rewritten by the provider every heartbeat and considered stale after 90s (same rule as `darkbloom status`); liveness via `kill(pid, 0)` |
| Earnings + balance | `GET https://api.darkbloom.dev/v1/provider/account-earnings`, authenticated with the CLI's device-login token from `~/.darkbloom/auth_token` |
| Fleet (which Macs online, models served) | public `GET /v1/providers/attestation`, filtered to providers whose ids appear in the account's recent earnings (or whose serial matches this Mac) |
| Start / Stop / Restart | shells out to `~/.darkbloom/bin/darkbloom`, which manages the `io.darkbloom.provider` LaunchAgent via `launchctl` |

Both `provider_id` and `provider_key` rotate when the provider restarts, so
offline machines can't be enumerated from the public API — the fleet list
only includes machines that are verifiably yours and online right now. (A
true offline fleet view would need the web console's `/v1/me/providers`,
which only accepts interactive browser sessions.)

`darkbloom start` normally opens an interactive model picker; the app instead
replays the `--model` flags recorded in the LaunchAgent plist from your last
`darkbloom start`, so the same models come back up. If no plist exists yet
(fresh install), run `darkbloom start` once in Terminal to pick models.

Polling: local state every 3s, coordinator every 30s (the earnings endpoint
is server-cached for 20s anyway).

## Development

```sh
swift build            # debug build
./scripts/build-app.sh # release build + .app bundle + zip in dist/
```

Swift 5.10+, macOS 14+. No dependencies.
