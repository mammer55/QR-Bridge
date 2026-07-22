# Clip — iOS Universal Clipboard Keyboard

A custom iPhone keyboard for your QR-Bridge project. Tap the globe, switch to
**Clip**, and you get a scrollable list of the most recent entries from your
Supabase `clips` table. Tap any one and its full text is typed straight into
whatever field you're in — no copy, no paste.

It reads from the **same** Supabase table your web app pushes to
(`owcukwsouruowulhohyq`), so anything you Push from your Windows window shows up
here within a refresh.

---

## What's in here

| File | What it is |
|------|------------|
| `ClipKeyboardExtension/KeyboardViewController.swift` | The whole keyboard. Already wired to your Supabase URL + anon key. |
| `ClipKeyboardExtension/Info.plist` | Extension config. `RequestsOpenAccess = true` enables the Full Access toggle. |

Xcode generates the rest (the container app + project file) when you follow the
steps below — those don't need to live in git.

---

## Build it (≈10 minutes, needs a Mac with Xcode)

### 1. Create the container app
1. Open **Xcode → File → New → Project… → iOS → App**.
2. Product Name: **ClipKeyboard**. Interface: **SwiftUI** (or Storyboard — doesn't
   matter, the container app is just a shell). Language: **Swift**.
3. Save it anywhere (e.g. `~/Developer/ClipKeyboard`).

> The container app doesn't need to do anything. It only exists because iOS
> won't install a keyboard extension on its own.

### 2. Add the keyboard extension target
1. **File → New → Target… → iOS → Custom Keyboard Extension**.
2. Product Name: **ClipKeyboardExtension**. Finish. If prompted to activate the
   scheme, say **Activate**.
3. Xcode creates a `ClipKeyboardExtension` group with a generated
   `KeyboardViewController.swift` and `Info.plist`.

### 3. Drop in the real files
1. **Replace** the generated `KeyboardViewController.swift` with the one in this
   folder (copy the whole file contents over it).
2. Open the extension's generated `Info.plist` and make sure
   `NSExtension → NSExtensionAttributes → RequestsOpenAccess` is set to **YES**.
   (The `Info.plist` in this folder shows exactly what it should look like — you
   can copy the `NSExtension` dict across, or just flip that one key.)

### 4. Run it on your phone
1. Plug in your iPhone, select it as the run destination.
2. Select the **ClipKeyboard** (container app) scheme and press **▶ Run**.
   - First time on a real device: **Signing & Capabilities → Team →** your Apple
     ID. A free Apple ID works but the app expires after ~7 days (see below).
3. The container app installs and launches. You can close it.

### 5. Enable the keyboard on the phone
1. **Settings → General → Keyboard → Keyboards → Add New Keyboard… → Clip**.
2. Tap **Clip** in that list again → turn on **Allow Full Access**.
   **This is required** — without it the keyboard has no network access and
   can't reach Supabase. (It's read-only network to your own Supabase; it can't
   see what you type on other keyboards.)

### 6. Use it
In any text field, tap 🌐 until you land on **Clip**. Your latest clips appear —
tap one to insert. **↻** re-pulls, **⌫** is backspace, 🌐 switches keyboards.

---

## The 7-day expiry (free Apple ID)

Apps signed with a free Apple ID stop working after ~7 days and must be
re-run from Xcode. Two ways around it:

- **Apple Developer Program ($99/yr)** → install via TestFlight/App Store, no expiry.
- **[SideStore](https://sidestore.io)** → auto-refreshes the app over Wi-Fi so it
  never expires, no paid account. A bit more setup.

If you just want to try it, the free 7-day route is fine — re-running from Xcode
takes a few seconds.

---

## Notes / tweaks

- **Show more/fewer clips:** change `fetchLimit` at the top of
  `KeyboardViewController.swift` (default 12).
- **No auto-refresh:** the list loads when the keyboard appears and on **↻**.
  iOS keyboards are short-lived, so an on-appear + manual refresh is the reliable
  pattern rather than live polling.
- **Security:** the anon key is the same public key already shipped in your web
  app's `index.html`, so nothing new is exposed. If you ever lock down the table
  with Row Level Security, the keyboard uses the identical REST call the web app
  does, so it'll keep working as long as the web app does.
