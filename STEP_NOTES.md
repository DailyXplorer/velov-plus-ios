# Step notes

## Stage 1 (done)

- Project skeleton: xcodegen `project.yml`, `Makefile`, app target, `VelovCore` package with tests, widget extension stub (booking Live Activity UI, not started by the app yet).
- Design system matching `app/globals.css`: bundled fonts (registered at launch, variable axes set in code), palette, pill buttons, CircleArrow, Eyebrow and CardTag, red dotted summary cards, SectionHeading, custom SelectField dropdown, detail rows, skeletons, empty states, error notice with « Réessayer ».
- Core logic with tests (`make test`): 68 tests, 1 live test skipped by default.
- Read screens on real data paths: Vue d’ensemble, Trajets and trip sheet, Points, Stations (MapKit, pins, search, filters, Autour de moi, station sheet, live bike list, bike sheet with verdict), Compte.
- Live smoke test (`make smoke`): GBFS stations and bikes of station 2002 with the app token and a browser User-Agent. The app token itself is the anonymous `POST /auth/environments/PRD/client_tokens`; no account call was made.
- Snapshots (`make snapshots`): 8 PNGs in `snapshots/`.

### Deviations to know

- Reads retry only 502/503/504 as the spec asks. The web client also retries connection failures; the native client does not.
- The id token from the login is verified (RS256 against the realm’s JWKS, issuer, audience, nonce, expiry), like the web client.
- `Trier par` on Trajets is new on the phone (Plus récents, Plus anciens, Plus longs, Plus chers).
- The web `lib/guesses.ts` was not in the reference copy at stage 1; stage 2 aligned `Guesses.swift` with it.

## To run in the GUI session (signing is impossible over ssh)

Over ssh, Xcode sees no Apple account (« No Accounts »), so automatic signing cannot create the profiles. From a Terminal on the Mac desktop:

```sh
cd ~/Documents/Projets/Apps/velov-ios
make build      # first time: Xcode > Settings > Accounts must list the personal team
make install    # iPhone unlocked, Developer Mode on; trust the certificate in Réglages > Général > VPN et gestion de l’appareil
```

If `make build` still reports missing profiles, open `VelovCompagnon.xcodeproj` once, select the VelovCompagnon and VelovWidgets targets, Signing & Capabilities, and pick the personal team; then rerun `make build`. Two app IDs are used (app and widgets).

## Stage 2 (done)

- Display name « Vélo’v+ » (app and widget extension). No one-device wording left: a login refusal shows the server's message (`DECISIONS.md`).
- Every action is wired: a confirmation sheet sized to its content, a haptic on « Confirmer », exactly one request, a success state, the raw status line on failure only. Rate (+5 points, within 3 h of the trip end), book (15 min · 10 points), unlock (vélo/borne/station, the 60-second instruction, a warning beyond 200 m when the position is already allowed, no hard block), the red booking banner on every tab, favourites, auto-spend, profile coordinates, receipts PDF via the share sheet, and the auto-renewal, « 15 minutes de plus », customer-service message and invite code (no badge, still one attempt each) (written locally before anything else).
- `Guesses.swift` mirrors the refreshed `lib/guesses.ts` constant for constant. The core writes and their orchestration (`Writes.swift`, `ExperimentalWrites.swift`, `VelovAPI+Writes.swift`, `PromoStore.swift`) are ported from `lib/cyclocity.ts`, `velov.ts`, `promo*.ts`, `renewal-models.ts`, `via-models.ts`, `contact-*.ts`.
- Tests (`make test`): 107 tests, 1 live test skipped, 0 failures. Every write is checked against the mocked `URLProtocol` for method, URL, headers, body and a single call, including refusals, gateway errors, lost answers and 401. No request was sent to Cyclocity by this stage.
- Lead's snapshot fixes: the bike sheet's two actions stack full width; the station sheet is as tall as its content; the tab bar is opaque and insets the pages, so the overview's map card and « Toucher pour explorer » end above it (`01b-overview-map.png`).
- Snapshots (`make snapshots`): 16 PNGs, adding the booking banner, the Live Activity on the Lock Screen and in the expanded Dynamic Island, the unlock confirmation and success, the rate card and the coordinates form.

### Live Activity and the free personal team

- Started on a successful booking and when `GET bookings` returns a running one (launch, foreground, refresh); ended after a successful unlock, at expiry while the app runs, and otherwise at the next `sync` (the activity carries `staleDate` = end of booking and shows « EXPIRÉE » once stale). Lock Screen, compact, minimal and expanded presentations; `Text(timerInterval:)` in monospaced digits.
- ActivityKit needs no entitlement for local updates; only push updates need the push capability, which a personal team lacks and which the app never asks for. The widget extension is the second app ID of the build. Nothing here could be checked on the iPhone over ssh: if ActivityKit refuses (Live Activities off in Réglages, or not allowed for this signing), the refusal is logged (`live-activity` category) and the in-app banner keeps working.

### Not verified over ssh

- The signed build: `make build` stops at « No Accounts » / « No profiles » over ssh; `make build-unsigned` (same sources, device SDK) succeeds. The signed build, the install and a real booking on the phone are for the lead (`INSTALL.md`, `scripts/install.command`).
