<p align="center">
  <img src="docs/icon-rounded.png" width="128" height="128" alt="Catalyst">
</p>

<h1 align="center">Catalyst</h1>

<p align="center">
  An on-device app store for iPhone and iPad, with Apple ID <b>and</b> Enterprise signing.<br>
  By <a href="https://github.com/mirazbakis">mirazbakis</a> · based on <a href="https://github.com/SideStore/SideStore">SideStore</a>
</p>

<p align="center">
  <a href="https://github.com/mirazbakis/Catalyst/releases/tag/nightly"><img src="https://img.shields.io/badge/download-nightly-6D40CC" alt="Nightly"></a>
  <a href="https://github.com/mirazbakis/Catalyst/actions/workflows/build.yml"><img src="https://github.com/mirazbakis/Catalyst/actions/workflows/build.yml/badge.svg" alt="Build"></a>
  <a href="./LICENSE"><img src="https://img.shields.io/badge/license-AGPLv3-blue" alt="AGPLv3"></a>
</p>

---

Catalyst installs and refreshes apps right on your device, no computer needed. It keeps everything SideStore does and adds a second way to sign apps: your own **Enterprise certificate**.

## Features

- **Two signing methods.** Sign with your Apple ID, with an Enterprise certificate, or let Catalyst ask each time you install.
- **No 7-day timer for Enterprise apps.** Enterprise-signed apps (including Catalyst itself when installed that way) show **SIGNED** instead of a countdown and are skipped by background refresh.
- **Separate lists in My Apps.** Apps are grouped into **Apple ID Signed** and **Enterprise Signed**.
- **On-device pairing.** Create this device's pairing file inside Catalyst, whichever certificate Catalyst was signed with.
- **Works without an App Group.** Catalyst still starts when an enterprise or ad hoc signer removes its App Group (widgets are unavailable in that case).
- **Black theme** with a subtle dark-purple accent.

## Signing methods

| | Apple ID | Enterprise |
|---|---|---|
| You need | An Apple ID | Your organization's `.p12` and `.mobileprovision` |
| Apple ID sign-in | Required | Not needed |
| App limit | 3 active apps (free accounts) | None |
| Refresh | Every 7 days (free accounts) | When the profile expires (usually 1 year) |
| Bundle IDs | Team ID appended | Kept as-is with wildcard profiles |

Choose one from the card at the top of **My Apps** (**Sign With…**) or in **Settings › Pairing & Signing › Signing Method**:

- **Apple ID Certificate**: every install uses your Apple ID.
- **Enterprise Certificate**: every install uses your imported certificate.
- **Ask Every Time**: Catalyst asks before each install, before anything else happens.

To set up Enterprise signing, open **Signing Method**, pick your `.p12`, enter its password, pick the matching `.mobileprovision`, then tap **Import & Use**. Catalyst checks that the certificate belongs to the profile and asks Apple whether it has been revoked. After the first install, trust the developer in **Settings › General › VPN & Device Management**.

Enterprise, Ad Hoc and Development profiles all work. Wildcard profiles (`TEAMID.*`) work best, because apps keep their own bundle IDs and extensions.

> [!IMPORTANT]
> Catalyst never ships, downloads or shares certificates. Only import a certificate your organization issued to you. Apple revokes enterprise certificates that are shared publicly, and every app signed with a revoked certificate stops opening.

## Pairing this device

Installing apps needs a pairing file for your device and LocalDevVPN, whichever certificate you use.

1. Open **Settings › Pairing & Signing › Generate Pairing File** and tap **Start Pairing**.
2. On the same device, go to **Settings › Privacy & Security › Developer Mode**, scroll down and tap **Pair with Catalyst**.
3. Enter the code Catalyst shows (it's also sent as a notification).
4. Come back to Catalyst. The pairing file is saved, activated and can be exported.

This needs iOS 27 or later with Developer Mode on. It uses minimuxer's built-in pairing host; the flow is modelled on StikPair's, but no StikPair code is included (its non-commercial license isn't compatible with AGPLv3).

## Source

```
https://raw.githubusercontent.com/mirazbakis/Catalyst/master/source.json
```

This is Catalyst's built-in source. Every push to `master` publishes a new **nightly** build and updates `source.json`, so Catalyst can update itself.

## Building

Requires macOS with Xcode 26.

```sh
git clone --recurse-submodules https://github.com/mirazbakis/Catalyst.git
cd Catalyst
make build fakesign ipa        # produces an unsigned Catalyst.ipa
```

Or open `AltStore.xcodeproj` (the Xcode target is still called `SideStore`). For device builds, copy `CodeSigning.xcconfig.sample` to `CodeSigning.xcconfig` and set your `DEVELOPMENT_TEAM`. The bundle ID is `com.mirazbakis.Catalyst`.

GitHub Actions builds `Catalyst.ipa` on every push, refreshes the `nightly` prerelease and `source.json` on `master`, and creates a release for `v*` tags.

<details>
<summary>Where the Catalyst code lives</summary>

| Path | What it does |
|---|---|
| `SideStore/Core/Enterprise/` | Enterprise identity import and validation, wildcard signer, enterprise-app detection |
| `SideStore/Views/Settings/Enterprise/EnterpriseSigningView.swift` | Signing Method screen |
| `SideStore/Views/Pairing/PairThisDeviceView.swift` | On-device pairing |
| `SideStore/Views/MyApps/SigningModeBannerView.swift` | Signing card in My Apps |
| `SideStore/Core/Operations/PipelineRunner.swift` | Asks for the signing method before an install starts |
| `Shared/Extensions/FileManager+SharedDirectories.swift` | Private-container fallback when the App Group is missing |

</details>

## Credits

Catalyst is built on the work of the [SideStore](https://github.com/SideStore) team and [AltStore](https://github.com/altstoreio/AltStore) by Riley Testut, together with [minimuxer](https://github.com/SideStore/minimuxer), [SideSign](https://github.com/SideStore/SideSign), [em_proxy](https://github.com/jkcoxson/em_proxy) and [LocalDevVPN](https://github.com/jkcoxson/LocalDevVPN). Catalyst is not affiliated with or endorsed by SideStore or AltStore.

## License

[AGPLv3](./LICENSE), same as SideStore. If you distribute Catalyst or run a modified version for others, you must publish its source code.
