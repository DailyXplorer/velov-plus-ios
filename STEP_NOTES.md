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
- The web `lib/guesses.ts` is not in the reference copy; `Guesses.swift` collects the guessed shapes from the API docs instead.

## To run in the GUI session (signing is impossible over ssh)

Over ssh, Xcode sees no Apple account (« No Accounts »), so automatic signing cannot create the profiles. From a Terminal on the Mac desktop:

```sh
cd ~/Documents/Projets/Apps/velov-ios
make build      # first time: Xcode > Settings > Accounts must list the personal team
make install    # iPhone unlocked, Developer Mode on; trust the certificate in Réglages > Général > VPN et gestion de l’appareil
```

If `make build` still reports missing profiles, open `VelovCompagnon.xcodeproj` once, select the VelovCompagnon and VelovWidgets targets, Signing & Capabilities, and pick the personal team; then rerun `make build`. Two app IDs are used (app and widgets).

## Stage 2

- Actions behind a confirmation, one attempt each, raw status line on failure: rate (+5 points), book (15 min, 10 points), unlock (vélo/borne/station, « appuyez sur le bouton de la borne dans les 60 secondes », warning beyond 200 m), favourites, auto-spend, profile edit, receipts PDF via the share sheet, auto-renewal, « 15 minutes de plus », invite a friend, customer service mail. The request code exists and is tested in `Writes.swift`; the screens still show the buttons disabled.
- Live Activity: start on a successful booking or on an active booking found at launch, end at expiry or after an unlock.
- Signed build and install on the iPhone.
