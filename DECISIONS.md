# Decisions (override SPEC.md)
- App display name: "Vélo'v+" (CFBundleDisplayName), widget/Live Activity labels too.
- One-device rule is NOT confirmed (owner sees several sessions working). Do not assume it: no special "autre appareil" wording in the UI, show the server's own error message; never force a logout of other sessions; never auto-retry logins.
- Owner wants autonomy: decide technical points yourself, pick the safest option, record it here.

## Stage 2 (recorded by the build agent)
- The display name is written with the typographic apostrophe, "Vélo’v+", like every other string of the app.
- A login refusal shows the Keycloak page's own message (`kc-feedback-text`, `alert-error`, `#input-error`), or the page text when short; "Vélo’v a refusé la connexion." when there is none. The device id stays stable.
- Every write has a confirmation sheet except the receipt PDF: its POST only reads, so (like the web) one tap sends one request and hands the PDF to the share sheet.
- A failed rating shows the message only, like the web: the core reports it without the raw answer.
- Experimental flows follow the web exactly: `lib/guesses.ts` constants, one attempt, no fallback body. Auto-renewal reads the state before (no write if not allowed) and after; a failed re-read never repeats the PATCH.
- Invite codes are written to `Application Support/PromoCodes/<sha256 of the account email>` before anything else; storage is checked before the debit. Copy says « ce téléphone » where the web says « ce navigateur ».
- « 15 minutes de plus » picks the full station from a tappable list (the web's dropdown, as rows); the core rechecks the station before the one POST.
- The tab bar is opaque and insets the pages (`safeAreaInset`): a scroll view ends above it, nothing sits under it.
- Live Activity: no push, no App Group. The widget uses SF Symbols and system fonts (monospaced digits); the extension bundles neither Phosphor nor the web fonts. The snapshots of the Lock Screen and the expanded Dynamic Island draw the widget's own views on a mock, because the simulator cannot be locked from a script.
