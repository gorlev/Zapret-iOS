# Security policy

ZapretiOS runs a VPN extension that sees every app's traffic on your iPhone. Security reports are taken seriously.

## Reporting a vulnerability

**Please do not open a public issue.** Report it privately instead:

1. Go to the [Security tab](https://github.com/gorlev/Zapret-iOS/security) of this repository.
2. Click **Report a vulnerability**.

Include what you found, the steps to reproduce it, the ZapretiOS version or commit, and your iOS version. You will get a reply as soon as possible. The fix is published before the details are made public, and you are credited in the release notes unless you prefer not to be.

## Supported versions

Only the latest commit on the default branch receives security fixes.

## What is in scope

Especially welcome:

- **The tunnel extension** (`Tunnel/`): traffic sent somewhere it should not go, or leaking around the tunnel while the bypass is on.
- **Network sharing**: the shared SOCKS5 listener reachable from outside the local Wi-Fi network, or still listening after sharing is turned off.
- **Local data**: site lists, settings, or logs exposed to other apps.

Bugs in `tpws` itself belong to the [zapret project](https://github.com/bol-van/zapret), and bugs in the packet layer to [hev-socks5-tunnel](https://github.com/heiher/hev-socks5-tunnel).
