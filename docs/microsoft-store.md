# Microsoft Store submission walkthrough

Reference for shipping CouchMC's Windows server through the Microsoft Store.
The packaging project that produces the .msixupload bundle lives at
[`pc/McController.Pkg`](../pc/McController.Pkg/). This document covers
everything **outside** that project: Partner Center registration, identity
reservation, capability approval, listing assets, and the submission +
review flow.

> Status: scaffolding committed, **not yet submitted**. Bring this doc up
> to date with your real timeline as you go through review the first time.

---

## 1. Developer account

1. Sign up at **<https://partner.microsoft.com/dashboard>** with the
   Microsoft account you want to own the publisher identity.
2. Choose **Individual** ($19 one-time) unless you've already incorporated
   — the Store listing's "Publisher" defaults to your account display
   name and you can change it later if you upgrade to a Company account.
3. Verification is automatic for Individual; takes ~1 working day. You'll
   get an email when you can submit apps.

## 2. Reserve the app name

In Partner Center, **Apps and games → New product → MSIX or PWA app**:

1. Choose **MSIX**.
2. Reserve the name `CouchMC` (or whichever variant Microsoft approves
   — they reject names that collide with existing apps, even ones that
   are unlisted).
3. After reservation, open the new app's dashboard. The reserved name's
   **Package identity** section gives you three values you'll need to
   paste into the manifest:

   ```
   Package/Identity/Name        e.g.  12345Linloir.CouchMC
   Package/Identity/Publisher   e.g.  CN=A1B2C3D4-1234-5678-9ABC-DEF012345678
   Package/Properties/Publisher e.g.  Linloir
   ```

4. Edit [`pc/McController.Pkg/Package.appxmanifest`](../pc/McController.Pkg/Package.appxmanifest):
   - `<Identity Name="…" Publisher="…" Version="1.0.1.0">` → replace
     `Name` and `Publisher`. Keep the version as `<major>.<minor>.<build>.<revision>`
     and bump `<build>` for every Store submission.
   - `<Properties><PublisherDisplayName>` → set to the
     "PublisherDisplayName" value from Partner Center.

> **Don't commit the real identity to a public repo if you'd rather not
> publish your developer GUID.** The values aren't secrets but they
> bind a build to your account; leaking them only matters if someone
> tries to phish around your developer brand.

## 3. Capability strategy

CouchMC's manifest declares `<rescap:Capability Name="runFullTrust" />`.
This is **gated**:

- Required, because we use `SendInput` / `SetCursorPos`, registry, raw
  Win32 process spawning of `adb.exe`, and direct `%APPDATA%` IO.
- Microsoft Store **does not auto-approve `runFullTrust` for individual
  publishers** on a first submission. The dashboard will warn you when
  you try to associate the .msixupload package; you submit anyway, and
  the review team manually evaluates your justification.

**What to write in the "Capability justification" submission field:**

> CouchMC is a desktop utility that lets a phone (Android / iOS) act
> as a touchscreen controller for Minecraft Java Edition running on the
> same PC. It needs `runFullTrust` because:
>
> 1. It injects keyboard and mouse input into the foreground game
>    using `SendInput` and `SetCursorPos`.
> 2. It reads the foreground window state (`GetForegroundWindow`,
>    `GetCursorInfo`) to switch between in-game, UI-interact, and
>    anti-mistouch modes.
> 3. It optionally spawns the bundled `adb.exe` to detect Android
>    devices connected via USB and forward TCP ports.
> 4. It writes its own configuration to `%APPDATA%\McController\`.
>
> All four require a desktop-bridge / full-trust environment; UWP
> sandboxing would prevent any of them from working.

Be prepared for review to email you and request a screencast showing
the app running benignly. Approval typically lands in **3–7 business
days** for the first submission with `runFullTrust`.

## 4. Listing assets you'll need before submission

Partner Center won't let you publish without these. Prepare ahead of
time:

| Asset | Min | Recommended | Source |
| --- | --- | --- | --- |
| App name | 1 | already reserved | step 2 |
| Short description | 1, max 200 chars | bilingual zh-CN + en-US | |
| Long description | 1, max 10 000 chars | bilingual | |
| Store screenshots | **at least 1 per device family**, 1366×768 minimum | 4–6 screenshots, 1920×1080 PNG | take fresh ones from a Release build |
| Store logo | 300×300 PNG | included | reused from existing app icon |
| Hero image | 1920×1080 PNG | optional, but it's the "featured" carousel art | |
| Category | 1 | "Utilities & tools" | |
| Privacy policy URL | required for any app that touches the network | <https://couchmc.linloir.cn/privacy> | already live |
| Support contact | required | GitHub Issues link | |
| Pricing | required | "Free" (with no IAP) | |
| Markets | required | unrestricted is fine; CN/US/JP/SG/KR cover most users | |
| Age rating | required | IARC-driven questionnaire; CouchMC is a productivity tool, all-ages | |

> The screenshots are the part that takes longest. Use the existing
> [`web/public/assets/features/`](../web/public/assets/features/)
> imagery as design inspiration but capture fresh PNGs from the actual
> Windows server with Minecraft running — Store policy disallows
> mock-ups that don't match the shipped app.

## 5. Build the .msixupload

After the manifest identity is updated and the icon script has been
run (see the [packaging project's README](../pc/McController.Pkg/README.md)):

```powershell
# Stop any running instance so the publish step can overwrite output.
Stop-Process -Name CouchMC -Force -ErrorAction SilentlyContinue

# Build a fresh Release of the App project (the .wapproj will pick it up).
& "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe" `
    pc\McController.App\McController.App.csproj `
    -p:Configuration=Release -p:Platform=x64 -p:RuntimeIdentifier=win-x64 -t:Rebuild

# Build the .msixupload for Store submission.
& "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe" `
    pc\McController.Pkg\McController.Pkg.wapproj `
    -p:Configuration=Release -p:Platform=x64 `
    -p:UapAppxPackageBuildMode=StoreUpload `
    -p:AppxPackageSigningEnabled=False `
    -t:Rebuild
```

`AppxPackageSigningEnabled=False` is correct here: the Store re-signs the
package on ingest. If you sign locally you'll see "package identity
mismatch" on upload.

Output lands at
`pc/McController.Pkg/AppPackages/McController.Pkg_<version>_Test/McController.Pkg_<version>_x64.msixupload`.

## 6. Upload + submit

1. Partner Center → CouchMC → **Packages** → **Drop your packages here**.
   Drag the `.msixupload`.
2. Wait for the validation crawl (60–120 seconds). Address any warnings
   it flags — `runFullTrust` will show up as one but is expected.
3. **Pricing and availability** → Free, choose markets, schedule
   "Manual publish" (so you can sanity-check after approval before
   releasing).
4. **Properties** → "Utilities & tools", set the age questionnaire,
   privacy URL.
5. **Store listings** → fill the localized descriptions, drop the
   screenshots, add a short tagline.
6. **Submit to the Store**.

## 7. Review timeline

- **Automated validation**: minutes.
- **Manual review** (always required when `runFullTrust` is declared):
  3–7 business days for the first submission; <2 days for subsequent
  updates that don't change capabilities.
- If review fails, Partner Center sends an email with the specific
  failure reason. Most common: "needs a screencast demonstrating the
  full-trust usage" — record a 30-second clip showing CouchMC pairing
  with a phone, injecting input into Minecraft, and exiting cleanly.

## 8. After publication

- Smoke-test the public Store install on a clean Windows VM. The
  package identity, registry virtualisation, and `%APPDATA%`
  redirection only really get exercised once the Store-signed build
  is running.
- Add an App Store-style badge to the website's `/download` page —
  same pattern as the iOS rollout in [`web/lib/downloads.ts`](../web/lib/downloads.ts):
  set `msStoreUrl` (would need to be added as a new field) to the
  Store product URL once live.
- Update the README badge row to make Windows clickable to the Store
  page.

## Code-signing for local testing

For local sideload (before submission), the MSIX needs to be signed
with a cert whose Subject CN matches the manifest's `<Identity Publisher="…">`.
Quick self-signed flow:

```powershell
# Create the cert (run once; cert lives in CurrentUser\My)
$cert = New-SelfSignedCertificate `
    -Type CodeSigningCert `
    -Subject "CN=Linloir, O=Linloir, C=CN" `
    -CertStoreLocation Cert:\CurrentUser\My `
    -KeyUsage DigitalSignature `
    -FriendlyName "CouchMC dev sideload cert" `
    -NotAfter (Get-Date).AddYears(3)

# Export it so you can sign with signtool
$pfxPwd = Read-Host -AsSecureString "PFX password"
Export-PfxCertificate -Cert $cert -FilePath couchmc-dev.pfx -Password $pfxPwd

# Trust it locally (otherwise Windows won't let you install the MSIX)
Import-PfxCertificate -FilePath couchmc-dev.pfx -CertStoreLocation Cert:\LocalMachine\TrustedPeople -Password $pfxPwd

# Sign the .msix produced by the SideloadOnly build above
& "C:\Program Files (x86)\Windows Kits\10\bin\10.0.22621.0\x64\signtool.exe" `
    sign /fd SHA256 /f couchmc-dev.pfx /p (Read-Host "pfx pw") `
    pc\McController.Pkg\AppPackages\McController.Pkg_*_Test\McController.Pkg_*.msix
```

Then double-click the signed `.msix` and Windows will offer to install it
normally.

Note: the self-signed cert is **for local testing only**. Don't try to
upload a locally signed package to the Store — the publisher CN won't
match what Partner Center assigned to your account.
