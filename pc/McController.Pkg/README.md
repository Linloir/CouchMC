# McController.Pkg — MSIX packaging for the Microsoft Store

This Windows Application Packaging Project (.wapproj) wraps the unpackaged
[`pc/McController.App`](../McController.App) WinUI 3 server into an MSIX
that can be submitted to the Microsoft Store.

The existing Inno Setup installer (`installer/McController.iss` → `CouchMC-Setup-X.Y.Z.exe`)
is **not** affected — the two outputs live side by side. Use Inno Setup
for direct downloads from the website; use this project for Store
submissions.

## Layout

```
McController.Pkg/
├── McController.Pkg.wapproj       Project file (MSBuild)
├── Package.appxmanifest           App identity, capabilities, visual assets
├── Images/                        PNG icons referenced by the manifest
│   ├── StoreLogo.png + scale-100..-400
│   ├── Square150x150Logo.png + scales
│   └── Square44x44Logo.png + scales
└── scripts/
    └── gen-msix-icons.py          Regenerates everything in Images/
                                   from mac/.../icon_512x512@2x.png
```

The icons in `Images/` are version-controlled because they're slow to
re-generate on each clean build. Re-run `python scripts/gen-msix-icons.py`
whenever the source icon changes.

## Prerequisites

Visual Studio Build Tools 2022 + these components:

- **Workload**: Universal Windows Platform development (`Microsoft.VisualStudio.Workload.Universal`)
- **Individual component**: MSIX Packaging Tools (`Microsoft.VisualStudio.Component.MSIX.PackagingTools`)
- Windows 10/11 SDK matching `<TargetPlatformVersion>` in the wapproj

These add the `Microsoft.DesktopBridge.props/.targets` files the wapproj imports.

## Local test build

For local install / sideload:

```powershell
& "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe" `
    pc\McController.Pkg\McController.Pkg.wapproj `
    -p:Configuration=Release `
    -p:Platform=x64 `
    -p:AppxBundle=Never `
    -p:UapAppxPackageBuildMode=SideloadOnly `
    -t:Rebuild
```

Output: `pc/McController.Pkg/AppPackages/McController.Pkg_<version>_Test/McController.Pkg_<version>.msix`.

To install for testing you need a self-signed cert that matches the
manifest's `Publisher`. See **Code-signing for local testing** in
[`docs/microsoft-store.md`](../../docs/microsoft-store.md).

## Store-upload build

Once the app's Identity has been replaced with the Partner-Center-issued
values (see manifest comments), build the .msixupload bundle that gets
submitted:

```powershell
& "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe" `
    pc\McController.Pkg\McController.Pkg.wapproj `
    -p:Configuration=Release `
    -p:Platform=x64 `
    -p:UapAppxPackageBuildMode=StoreUpload `
    -p:AppxPackageSigningEnabled=False `
    -t:Rebuild
```

`AppxPackageSigningEnabled=False` is intentional: the Store re-signs
uploads with Microsoft's certificate. Output goes into
`AppPackages/McController.Pkg_<version>_Test/McController.Pkg_<version>_x64.msixupload`.

That `.msixupload` is what you upload to Partner Center → your app →
**Packages**.

## Caveats

- Microsoft Store gating for `runFullTrust`: new individual developer
  accounts often have this capability declared but rejected on first
  submission. Apple-Store-style review feedback usually arrives within
  one to three business days. See the submission guide for how to argue
  for it.
- The bundled `Tools/Adb/adb.exe` ships as part of CouchMC.App's
  publish output and gets included in the MSIX automatically (it sits
  under `CouchMC.exe`'s directory). MSIX virtualizes the working
  directory, but `AppContext.BaseDirectory` still resolves correctly,
  so `AdbDiscovery` finds adb without changes.
- `%APPDATA%\McController\config.json`: under MSIX, writes to
  `%APPDATA%\<package-family>\LocalState\McController\config.json` via
  the redirection layer. Existing v1.0.x unpackaged users will NOT see
  their settings inherit when they reinstall through the Store; this is
  documented for users in the Store listing.
- The "start at sign-in" HKCU\Run registry entry behaves similarly:
  MSIX redirects writes. The cleaner long-term replacement is
  declaring an `<Extension Category="windows.startupTask" …>` in the
  manifest — out of scope for the first Store submission.
