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
in `index.html` along with the anon key. That key is public by design; access is
governed by row level security in Supabase, so **never put anything secret in this
repo and never assume the anon key protects the table**.

Pushed clips get `expires_at` 24 hours out and `source: 'pc'`. Every read filters on
`expires_at > now()`, so expiry is enforced by the query, not by a cleanup job.

Delivery is two layered paths:

1. **Realtime** is primary. A `postgres_changes` subscription on INSERT into `clips`
   drives the status dot to "Live".
2. **A 15 second poll** is the fallback and it is not redundant. Realtime silently
   misses events while a tab is backgrounded, which is the normal state on iOS. Do
   not remove the poll because realtime "already works".

Both paths dedupe on `lastSeenId`, so touching one and not the other causes clips to
show twice.

## Auto copy is deliberately conservative

`tryAutoCopy` only writes to the clipboard when the current clipboard content still
matches `lastAutoCopied`, meaning the app still owns it. Once you copy something else
yourself, it backs off until the next new clip. This is intentional. Making it write
unconditionally would clobber whatever the user just copied.

## Theming

Five presets plus a custom picker, all driven by CSS custom properties on
`:root`. Custom themes derive text, muted, dim, border, and input colors from the
background luminance so contrast survives a dark background. Persisted in
localStorage under `clip-theme` and `clip-theme-name`. Ctrl+Shift+T opens the picker.

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
