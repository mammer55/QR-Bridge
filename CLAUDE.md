# QR-Bridge (Clip)

Single page web app that moves clipboard text between a PC, a Mac, and an iPhone
through a Supabase table. One file, no build step, no framework.

Live at https://mammer55.github.io/QR-Bridge/ served by GitHub Pages from `main` at
the repo root, so **anything merged to `main` is deployed immediately**. There is no
staging environment.

## Layout

```
index.html      the entire app: markup, CSS, and JS in one file
package.json    only a live-server dev script, no build and no runtime deps
```

`node_modules/` is gitignored. The Supabase client is loaded from a jsdelivr CDN
`<script>` tag, not from npm.

## Running it

```
npm run dev     live-server on port 3000, opens a browser
npm start       live-server on port 3000, no browser
```

## How it works

Backend is a single Supabase table, `clips`, with columns `id`, `content`,
`expires_at`, `created_at`, `source`. Project ref `owcukwsouruowulhohyq`, hardcoded
in `index.html` along with the anon key. That key is public by design and anyone holding it
can read and write the table, so **never put anything secret in this repo**. The
encryption below is what protects clips, not the key or row level security.

Pushed clips get `expires_at` 24 hours out (a Supabase trigger clamps it to 15
minutes) and `source: 'pc-to-mac'`, which only the Mac app reads. Every read filters
on `expires_at > now()`.

Delivery is two layered paths:

1. **Realtime** is primary. A `postgres_changes` subscription on INSERT into `clips`
   drives the status dot to "Live".
2. **A 15 second poll** is the fallback and it is not redundant. Realtime silently
   misses events while a tab is backgrounded, which is the normal state on iOS. Do
   not remove the poll because realtime "already works".

Both paths dedupe on `lastSeenId`, so touching one and not the other causes clips to
show twice.

## Encryption (since 28 Oct 2026)

Clips are encrypted in the browser before insert, in the `cb1` format documented in
ClipBridge's `shared/cbcrypt.py`. The block between `// --- cb1 crypto` and
`// --- end cb1 crypto ---` in `index.html` must match that file exactly; run
`node test/cb1_compat.mjs` after touching either. Rows that do not decrypt are
ignored, and since every client now encrypts (the Mac's clips to the work computer
included, `encrypt_to_pc` in its config), `ACCEPT_PLAINTEXT` is false: unencrypted
rows are forgeries or the iPhone's old plaintext Shortcut.

The header's Locked / Unlocked button opens the passphrase panel. `clipKey` is a non
extractable `CryptoKey`; `clipRaw` holds the same key's bytes only where they may be
handed on (typed here, or remembered). "Remember on this device" stores those raw
bytes in IndexedDB, readable by any page on the mammer55.github.io origin. The
passphrase itself is never stored. Unlock checks the key against up to 20 fresh
encrypted clips and passes if any opens; a second press with the same words goes
through anyway, because anyone can insert junk that looks encrypted and that must
never lock anyone out.

## QR pairing

"Pair with phone" in the passphrase panel unlocks a borrowed computer without typing
the passphrase on it. The computer makes an ECDH P-256 key pair whose private half
never leaves the tab and shows `#pair=<id>.<publicKey>` as a QR (qrcode-generator
from jsdelivr, pinned with an SRI hash). The phone's camera opens that link; the page
clears the hash at once, asks to unlock if it holds no raw key, then "Send key" seals
the raw clip key under ECDH + HKDF and inserts it as a `source: 'pair'` row
(`cbp1.<id>.<phonePublicKey>.<iv>.<ciphertext>`). The computer polls for it every 2
seconds for 5 minutes. A photo of the code gives only the public key, which opens
nothing. Pair rows are excluded from every pull query and from `openRow`, and the
Mac app never selects them. `node test/pair.mjs` exercises the block between
`// --- pair crypto` and `// --- end pair crypto ---`. On iOS the camera opens Safari,
whose storage is separate from the Home Screen web app, so the phone must be unlocked
and remembered in Safari itself. A link that only changes the hash of an open page is
caught by the `hashchange` listener.

## Auto copy is deliberately conservative

`tryAutoCopy` only writes to the clipboard when the current clipboard content still
matches `lastAutoCopied`, meaning the app still owns it. Once you copy something else
yourself, it backs off until the next new clip. This is intentional. Making it write
unconditionally would clobber whatever the user just copied.

## Theming

Dark by default since 2.5.0. Five presets (Night, Ink, Day, Sky, Peach) plus a custom
picker, all driven by CSS custom properties on `:root`, whose defaults are Night. Custom
themes derive text, muted, dim, border, and input colors from the background luminance
so contrast survives a dark background; `applyTheme` also sets `color-scheme`, the
ok and error colors, and the `theme-color` meta from it. Persisted in localStorage under
`clip-theme-v2` and `clip-theme-name-v2`; the keys changed in 2.5.0 so every device
started on Night once. Ctrl+Shift+T opens the picker.

Type is IBM Plex Sans for the interface and IBM Plex Mono for clip text, from Google
Fonts. The two panes fill the window on a computer and stack on a phone.

## Cache busting

`BUILD_VERSION` at the very top of `index.html` is compared against localStorage on
load and forces a reload when it changes. **Bump it on every deploy.** A Home Screen
web app caches hard, so without a bump the phone keeps showing the old page and the
change looks like it did not work.

## iPhone constraints

This is opened as a Home Screen web app on iOS, so `~/.claude/reference/ios-web-apps.md`
applies to any change in `<head>` or to layout. In particular: no `viewport-fit=cover`,
form controls at 16px minimum, and the `apple-touch-icon` is inlined as a data URI
rather than a file, which matters because several apps share a GitHub Pages origin.

## Git identity

This repo belongs to the **mammer55** account, not the UKY one. `user.name` and
`user.email` are set locally to `mammer55 <83394881+mammer55@users.noreply.github.com>`
so commits do not inherit the global UKY identity. Do not override them, and do not
add Claude co-author trailers.

## Related

The iOS app that used to live in `ios-keyboard/` was split out on 20 Aug 2026 and now
lives in its own repo at `~/Code/ClipKeyboard` (`mammer55/ClipKeyboard`, private).
Nothing in this repo depends on it, but the two share the same Supabase `clips` table,
so a schema change here affects that app too.
