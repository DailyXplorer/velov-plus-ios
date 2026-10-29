# Vélo’v+ (iOS)

A native SwiftUI client for the Lyon bike-share account, a port of the companion web app with the same design and copy. It talks to Cyclocity directly; there is no backend.

## Layout

| Path | Content |
| --- | --- |
| `Packages/VelovCore` | Business logic as a Swift package: models, normalisation, dates, bike score, error maps, guessed request shapes, networking (app token, retry rules, single-flight), auth (PKCE login, Keychain, stable device id, refresh, logout), reads and the one-shot writes. |
| `App` | The SwiftUI app: design system (`App/Design`), screens (`App/Screens`), app state and sample data (`App/Model`). |
| `Widgets` | Widget extension with the booking Live Activity. |
| `Shared` | Code compiled into both the app and the extension. |
| `scripts` | Asset download, app icon, simulator snapshots. |

## Commands

| Command | Effect |
| --- | --- |
| `make project` | Downloads fonts and icons if missing, draws the app icon, generates the Xcode project with xcodegen. |
| `make build` | Device build, signed with the personal team (run it from the GUI session). |
| `make build-unsigned` | Device build without signing. |
| `make test` | Runs the `VelovCore` tests on the macOS host. Every network call goes through a mocked `URLProtocol`. |
| `make smoke` | Public GETs against the real service: GBFS stations and the bikes of station 2002. |
| `make install` | Installs the last device build on the paired iPhone. |
| `make snapshots` | Renders the key screens with sample data in the simulator to `snapshots/`. |
| `scripts/install.command` | `make build && make install` from the GUI session, output appended to `~/.velov-ios-install.log` (ends with `DONE`). See `INSTALL.md`. |

## Rules the code keeps

- Reads retry only on 502, 503 and 504, at most three attempts, 8 s each; never after a timeout.
- A state-changing call goes out exactly once per user confirmation and is never retried.
- Every write sits behind a confirmation sheet; a failure shows Vélo’v's message and the raw status line, nothing is resent without a new confirmation.
- The device id is created once, stored in the Keychain and kept across logouts. No one-device rule is assumed: a login refusal shows the server's own message.
- The booking Live Activity is started and ended by the app only (no push).
- Light mode only; red is the only accent colour.

Fonts: Faculty Glyphic, DM Sans and Azeret Mono (SIL Open Font License). Icons: Hugeicons free set (MIT), built by `scripts/fetch-assets.py` from the pinned `@hugeicons/core-free-icons` npm package. Licences are in `App/Resources/Licenses`.
