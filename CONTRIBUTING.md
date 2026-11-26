# Contributing to ZapretiOS

Thanks for helping. Bug reports, strategy reports, translations, and code are all welcome.

## Asking and reporting

- **Questions** ("does this strategy work on my provider?", "how do I…?") belong in [Discussions](https://github.com/gorlev/Zapret-iOS/discussions).
- **Bugs** and **feature ideas** belong in [Issues](https://github.com/gorlev/Zapret-iOS/issues/new/choose). The forms ask for what helps most: your iOS version, your device, and the log.
- **Security problems** must not go in a public issue. See [SECURITY.md](SECURITY.md).

ZapretiOS is a front end for zapret's `tpws`. If a strategy itself does not get past your provider's filter, try **Find a Strategy** first. If no `tpws` option works, the [zapret project](https://github.com/bol-van/zapret) is the right place to ask.

## Setting up

You need a Mac with Xcode 26 or later, XcodeGen (`brew install xcodegen`), and, to run the VPN on a device, a paid Apple Developer Program membership. See [Install](README.md#install) for signing and [Development](README.md#development) for how the code is laid out.

The interface runs in the simulator without signing; the VPN only runs on a real device.

## Making a change

1. **Shared logic goes in `Shared/`**, which every target compiles: the app, the tunnel, and the widget. Views go in `App/`.
2. **Follow iOS.** Use Apple's controls and system styles, SF Symbols, and the spacing and color tokens in `App/UI/Theme.swift`. Never hard-code colors; use `Palette` and the system colors.
3. **Mind the extension's limits.** The tunnel extension has about 50 MB of memory, and `tpws` starts once per extension process. Pass big lists to `tpws` as files; never build them in memory in the extension.
4. **Never edit the generated files.** The Xcode project comes from `project.yml`, and the String Catalogs from `Localization/`.

## Checking a change

Before you open a pull request:

| Check | Command | Expect |
|---|---|---|
| Simulator build | see [Development](README.md#development) | No warnings |
| Find a Strategy logic | `tools/check-finder.sh` | All pass |
| Screenshots (UI changes) | Run in the simulator; light and dark | Looked at |
| Translations (text changes) | `tools/l10n-extract.sh`, then `python3 tools/l10n.py check` | `PASS` |
| Device (tunnel changes) | `tools/build-ipa.sh --install`, then turn the bypass on | Sites open, the log shows `tpws` lines |

## Text and translations

ZapretiOS is in eight languages. UI text is a SwiftUI literal (`Text("…")`) or `String(localized: "…")`.

After adding or changing text, run `tools/l10n-extract.sh`, add the new strings to every file in `Localization/`, and run `python3 tools/l10n.py build`. Follow [Localization/BRIEF.md](Localization/BRIEF.md): write each language as a native speaker would, not word for word. If you only speak some of the languages, say so in the pull request and leave the rest for a native speaker.

Improving an existing translation is a great first contribution.

## Pull requests

- Keep each pull request to one change.
- Write the title as what a user can now do, for example "Import site lists from a URL".
- Add screenshots for visible changes, in light and dark mode.

By contributing, you agree that your contribution is licensed under the [MIT License](LICENSE).
