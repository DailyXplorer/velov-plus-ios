# Vélo’v Compagnon (iOS)

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

## Rules the code keeps

- Reads retry only on 502, 503 and 504, at most three attempts, 8 s each; never after a timeout.
- A state-changing call goes out exactly once per user confirmation and is never retried.
- The device id is created once, stored in the Keychain and kept across logouts: the service allows one connected device per account.
- Light mode only; red is the only accent colour.

Fonts: Faculty Glyphic, DM Sans and Azeret Mono (SIL Open Font License). Icons: Phosphor (MIT). Licences are in `App/Resources/Licenses`.
