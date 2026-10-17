<p align="center"><img src="docs/icon.png" width="128" alt="Kaspi in English icon"></p>

# Kaspi in English

A free, open-source Mac menu-bar app that puts **English labels on top of the Kaspi.kz iPhone app** while you use it through macOS **iPhone Mirroring**. The Kaspi app is only in Russian and Kazakh. This app reads the mirrored screen on your Mac and shows a small dark English label over each line of text.

> **Unofficial helper.** Not affiliated with, endorsed by, or connected to Kaspi.kz. "Kaspi" is used only to describe what the app works with. Translations can be wrong: **always double-check amounts and recipients before you confirm a payment or transfer.**

- 🔒 **Private:** no network access (the app is sandboxed with no network permission, so macOS blocks it), no accounts, no analytics. **Nothing is stored**: no screenshots, no logs, no history. Translations are cached in memory only and disappear when you quit.
- 📖 **Kaspi glossary built in:** about 900 Kaspi banking and shopping terms (Russian + Kazakh), e.g. *Переводы → Transfers*, *Мой Банк → My Bank*, *Рассрочка → Installments (0%)*.
- 🍎 **Everything else uses Apple's on-device Translation** (Russian → English, macOS 15+).
- 💻 Universal app (Apple silicon + Intel). **Requires macOS 15 Sequoia or newer** (iPhone Mirroring needs it too).

## Install

1. **Download** `Kaspi-in-English-1.0.0.dmg` from the [latest release](https://github.com/gofordylan/kaspi-english/releases/latest). The `.zip` works too.
2. Open the `.dmg` and **drag "Kaspi in English" into Applications**.
3. **Open it the first time.** The app is free, so it isn't signed with a paid Apple Developer ID, and macOS will warn you. Use any **one** of these:
   - **Right-click (or Control-click) the app in Applications → Open → Open.**
   - Or double-click it, click **Done** on the warning, then go to **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to "Kaspi in English" (enter your password and click **Open Anyway** again).
   - Or run this in Terminal:
     ```bash
     xattr -dr com.apple.quarantine "/Applications/Kaspi in English.app"
     ```
4. A speech-bubble icon appears in the **menu bar** (top-right of the screen). The app has no Dock icon.

## Allow Screen Recording (one time)

The app has to see the iPhone Mirroring window to read its text. The welcome window walks you through this:

1. Click **Allow Screen Recording…**. macOS shows a prompt. Click **Open System Settings**.
2. In **System Settings → Privacy & Security → Screen & System Audio Recording**, turn on **Kaspi in English** (if it isn't listed, click **+** and pick it from Applications).
3. macOS asks you to quit and reopen the app. Click **Quit & Reopen**, or use **Relaunch App** in the welcome window.

macOS Sequoia sometimes asks again later whether the app may keep recording your screen. Click **Allow**. After you install a new version, you may have to turn the switch off and on again, because each free (ad-hoc signed) build looks like a new app to macOS.

## Turn on Apple Translation (recommended)

The glossary covers Kaspi's menus and buttons. For everything else (promotions, product names, messages) the app uses Apple's on-device translator, which needs the Russian language pack once:

- In the welcome window (menu bar icon → **Setup & Permissions…**), click **Download Russian → English** and accept the macOS prompt, **or**
- Go to **System Settings → General → Language & Region → Translation Languages…** and download **Russian** (and **English** if it's listed).

macOS downloads the pack itself. The app never connects to the internet.

## Use it with iPhone Mirroring

1. Open **iPhone Mirroring** on your Mac (Applications or Spotlight). Your iPhone has to be locked and nearby.
2. Open **Kaspi.kz** on the mirrored iPhone. Tip: set Kaspi's language to **Russian** (Сервисы → Настройки). Apple's translator doesn't support Kazakh, so Kazakh screens only get the glossary.
3. English labels appear on top of the Kaspi screen and update about once a second after the screen changes. The labels are click-through, so you can keep tapping Kaspi normally.

| Shortcut | What it does |
|---|---|
| **⌃⌥T** (Control-Option-T) | Show / hide the overlay |
| **⌃⌥P** | Side panel listing each Russian line next to its English translation (you can select and copy) |
| **⌃⌥R** | Refresh now |

You can do the same from the menu bar icon, which also has **Pause**, **Choose Window…** (use this if iPhone Mirroring isn't detected automatically), and **Hide Overlay When Window Is Covered**.

Labels with a thin red outline came from the Kaspi glossary. Labels with a grey outline came from Apple Translation.

## Troubleshooting

- **"iPhone Mirroring window not found"**: make sure iPhone Mirroring is open and visible (not minimized), or choose it with **Choose Window…**.
- **No labels at all**: check Screen Recording (above), then quit and reopen the app.
- **Labels in the wrong place after moving the window**: they follow the window within a fraction of a second and refresh after the next screen change. Press ⌃⌥R to force a refresh.
- **Kaspi shows "Снимок экрана недоступен" or a black screen**: Kaspi has hidden that screen from mirroring and recording, so there's nothing to read.

## How it works

1. **ScreenCaptureKit** finds the window owned by iPhone Mirroring (bundle id `com.apple.ScreenContinuity`, with name/title fallbacks) and grabs a frame of that window only, about once a second.
2. If the frame changed, **Apple Vision** (`VNRecognizeTextRequest`, accurate, `ru-RU` plus Kazakh if your macOS supports it) finds each text line.
3. Each line is looked up in [`Resources/glossary.json`](Resources/glossary.json). Lines the glossary doesn't know go to Apple's **Translation** framework (`TranslationSession`, ru → en, on-device). Results are cached in memory.
4. A transparent, click-through, always-on-top window follows the iPhone Mirroring window and draws the labels.

## Build from source

```bash
# macOS 15+, Xcode 16+
swift build                      # debug build
scripts/build-app.sh 1.0.0       # universal .app + .zip + .dmg in ./dist
```

Releases are built by GitHub Actions ([`.github/workflows/release.yml`](.github/workflows/release.yml)) on `macos-15` whenever a `v*` tag is pushed.

To improve the glossary, edit `scripts/glossary_ru.txt` / `scripts/glossary_kk.txt` (`Russian | English`, one per line) and run `python3 scripts/build_glossary.py`. Pull requests are welcome. [`docs/kaspi-cheatsheet.md`](docs/kaspi-cheatsheet.md) lists the sources for the core terms.

## License

MIT. The icon is original artwork and isn't Kaspi's logo.
