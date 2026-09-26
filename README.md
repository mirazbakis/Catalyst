<p align="center"><img src="docs/icon.png" width="128" alt="Catalyst icon"></p>

# Catalyst

> By [mirazbakis](https://github.com/mirazbakis). An on-device app store for iOS, forked from [SideStore](https://github.com/SideStore/SideStore), with **Enterprise signing** built in.

Catalyst does everything SideStore does (sideloading and refreshing apps with your Apple ID over the LocalDevVPN loopback, no computer needed) and adds a second signing mode.

## Signing modes

| | Apple ID (SideStore mode) | Enterprise |
|---|---|---|
| What you need | An Apple ID | Your organization's certificate (`.p12`) and provisioning profile (`.mobileprovision`) |
| Apple ID sign-in | Required | Not needed |
| App limit | 3 active apps on free accounts | None |
| Refresh | Every 7 days (free) | When the profile expires (usually 1 year) |
| Bundle IDs | Team ID is appended | Kept as-is with wildcard profiles |

Switch in **Settings → Advanced Settings → Enterprise Signing**:

1. Pick your `.p12`, enter its password, and pick the matching `.mobileprovision`.
2. Tap **Import & Enable**. Catalyst checks that the certificate is inside the profile, that the profile can be used outside the App Store, and asks Apple's OCSP responder whether the certificate is revoked.
3. Install apps as usual. After the first install, trust the developer in **Settings → General → VPN & Device Management**.

Turn the switch off to go back to Apple ID signing. Apps keep the identity they were signed with until you reinstall them.

Enterprise, Ad Hoc and Development profiles all work. Wildcard profiles (`TEAMID.*`) work best, because apps keep their own bundle IDs and extensions.

> [!IMPORTANT]
> Catalyst never ships, downloads or shares certificates. Only import a certificate your organization issued to you. Apple revokes enterprise certificates that are distributed publicly, and every app signed with a revoked certificate stops opening.

### No 7-day timer for enterprise-signed apps

Apps signed with an enterprise (In-House) profile, including Catalyst itself when it was installed with an enterprise certificate by another signing tool, show **SIGNED** instead of a countdown. They get no expiry notifications and are skipped by background refresh and the widgets. The countdown only comes back in the last 7 days before the profile really expires.

## Pair this device (no computer)

Catalyst needs a pairing file for your iPhone or iPad. Generate one on the device itself: **Settings › Pairing & Signing › Generate Pairing File** (also on the My Apps banner, and offered after importing an enterprise certificate).

1. Tap **Start Pairing** and allow Local Network access.
2. Open **Settings › Privacy & Security › Developer Mode**, scroll down and tap **Pair with Catalyst**.
3. Enter the code Catalyst shows (it's also sent as a notification).
4. The pairing file is saved and activated automatically, and you can export it.

This works no matter how Catalyst itself was signed (Apple ID, Enterprise or Ad Hoc). It needs iOS 27+ with Developer Mode, and uses minimuxer's built-in pairable-host service; the flow is modelled on StikPair's UX but contains no StikPair code.

## Choosing a certificate

**My Apps** shows a card explaining how new apps are signed, with a **Sign With…** menu: **Apple ID Certificate**, **Enterprise Certificate**, or **Ask Every Time** (Catalyst then asks on each install). The same choice is under **Settings › Pairing & Signing › Signing Method**. My Apps lists apps in separate **Apple ID Signed** and **Enterprise Signed** sections.

## Add the source

```
https://raw.githubusercontent.com/mirazbakis/Catalyst/master/source.json
```

It's Catalyst's built-in source. Every push to `master` publishes a new **nightly** prerelease and CI updates `source.json` to point at it, so Catalyst can update itself.

### How it works

| File | Role |
|---|---|
| `SideStore/Core/Enterprise/EnterpriseSigningManager.swift` | Imports and validates the identity, stores it through the existing Certificate/Profile managers, resolves the signing team without an Apple ID |
| `SideStore/Core/Enterprise/EnterpriseAppSigner.swift` | Signs bundles with wildcard profiles, resolving `application-identifier` per app and extension |
| `SideStore/Core/Enterprise/ProvisioningProfile+Signing.swift` | Profile type detection (Enterprise / Ad Hoc / Development / App Store), wildcard helpers |
| `SideStore/Views/Settings/Enterprise/EnterpriseSigningView.swift` | Settings screen |
| `SideStore/Core/Enterprise/InstalledApp+EnterpriseSigning.swift` | Detects enterprise-signed apps to hide the 7-day timer |
| `UpdateAppCertificateOperation` | Picks the enterprise identity for installs when the mode is on |
| `VerifyCertificateOperation` | Checks imported identities with OCSP only (the developer portal is skipped) |

## Building

Requires macOS with Xcode 26.

```sh
git clone --recurse-submodules <your Catalyst repo URL>
cd Catalyst
open AltStore.xcodeproj          # the Xcode target is still called "SideStore"
```

Unsigned IPA from the command line:

```sh
make build fakesign ipa          # produces Catalyst.ipa
```

For device builds from Xcode, copy `CodeSigning.xcconfig.sample` to `CodeSigning.xcconfig` and set your `DEVELOPMENT_TEAM`. The default bundle ID is `com.mirazbakis.Catalyst`. The app uses a black theme with a subtle dark-purple accent (`#6D40CC`); other accents are in Settings › User Customizations.

GitHub Actions (`.github/workflows/build.yml`) builds an unsigned `Catalyst.ipa`, refreshes the `nightly` prerelease and `source.json` on every push to `master`, and creates a release for `v*` tags. SideStore's original workflows are parked in `.github/upstream-workflows/`.

## Credits

Catalyst is built on the work of the [SideStore](https://github.com/SideStore) team and [AltStore](https://github.com/altstoreio/AltStore) by Riley Testut, plus [minimuxer](https://github.com/SideStore/minimuxer), [SideSign](https://github.com/SideStore/SideSign), [em_proxy](https://github.com/jkcoxson/em_proxy) and [LocalDevVPN](https://github.com/jkcoxson/LocalDevVPN). Catalyst is not affiliated with or endorsed by SideStore or AltStore.

## License

[AGPLv3](./LICENSE), same as SideStore. If you distribute Catalyst or run a modified version for others, you must publish its source code.
