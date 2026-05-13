#!/usr/bin/env pwsh
# Regenerate Android + iOS app icons from `assets/icon.png`.
#
# Run any time the source icon changes:
#
#     pwsh scripts/regenerate_app_icons.ps1
#
# What it produces:
#
#   Android (android/app/src/main/res/):
#     mipmap-{m,h,xh,xxh,xxxh}dpi/
#       ic_launcher.png             — legacy raster icon (pre-API-26 fallback)
#       ic_launcher_round.png       — circular-masked variant of the above
#       ic_launcher_foreground.png  — adaptive-icon foreground (108dp canvas
#                                     filled edge-to-edge by the source icon)
#
#   iOS (ios/McController/Resources/Assets.xcassets/):
#     AppIcon.appiconset/icon-1024.png      — 1024×1024 sRGB, no alpha
#                                             (Apple rejects alpha channels)
#     AppIconAbout.imageset/icon-256.png    — used by the in-app About card
#     AppIconAbout.imageset/icon-512.png
#
# Sizes follow the official platform specs:
#
#   Android adaptive icons: 108dp foreground canvas, full-bleed source icon.
#     Densities: mdpi (108px), hdpi (162), xhdpi (216), xxhdpi (324),
#                xxxhdpi (432).
#     The launcher mask crops up to ~17% off each corner; the source icon's
#     central composition (gamepad) stays inside the 72dp safe zone.
#   Android legacy icons:   48dp launcher icon.
#     Densities: mdpi (48px), hdpi (72), xhdpi (96), xxhdpi (144),
#                xxxhdpi (192).
#   iOS AppIcon:            single 1024×1024 sRGB PNG, no alpha.
#                           Xcode 14+ auto-derives every device size from this.
#
# The adaptive-icon BACKGROUND layer (a flat colour) is declared in
# `android/app/src/main/res/values/colors.xml` (`ic_launcher_background`),
# not here.

[CmdletBinding()]
param(
    [string]$Source,
    [string]$RepoRoot,
    # Fraction of the 108dp adaptive-icon canvas occupied by the source
    # artwork.
    #
    # The canonical `assets/icon.png` is authored Apple-style: full-bleed
    # 1024×1024 with its own built-in margins (the gamepad sits well inside
    # the canvas, the outer ~15% is just decorative green padding). For
    # that style 1.0 is correct — the OEM launcher mask crops into the
    # source icon's own padding, never touching the symbol.
    #
    # If you ever swap in a different source PNG that draws meaningful
    # content all the way to the edges (no built-in margin), pass
    # `-ForegroundScale 0.666` to centre-scale the artwork into Google's
    # guaranteed safe zone instead.
    [double]$ForegroundScale = 1.0
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

# Default to the repo root by walking up one level from this script.
# Done in the script body (not the param block) so it works on Windows
# PowerShell 5.1, which doesn't populate $PSScriptRoot before default
# parameter values are evaluated.
if (-not $RepoRoot) {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}
if (-not $Source) {
    $Source = Join-Path $RepoRoot "assets/icon.png"
}

if (-not (Test-Path $Source)) {
    throw "Source icon not found: $Source"
}

$src = [System.Drawing.Image]::FromFile((Resolve-Path $Source))
Write-Host "Source: $Source ($($src.Width)x$($src.Height))"

function Save-Resized {
    param(
        [System.Drawing.Image]$Image,
        [int]$Size,
        [string]$OutputPath,
        # If set <1.0, the source is scaled down to that fraction of the
        # canvas and centered, with transparent margins around it. This is
        # how the adaptive-icon FOREGROUND is supposed to be authored —
        # the inner 66.6% is the launcher safe zone, the outer 33% is
        # decorative and may be cropped by the OEM mask shape.
        [double]$ContentScale = 1.0,
        [bool]$DropAlpha = $false,
        [bool]$RoundMask = $false
    )

    $dir = Split-Path -Parent $OutputPath
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    if ($DropAlpha) {
        $pixelFormat = [System.Drawing.Imaging.PixelFormat]::Format24bppRgb
    } else {
        $pixelFormat = [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
    }

    $bmp = New-Object System.Drawing.Bitmap($Size, $Size, $pixelFormat)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $g.InterpolationMode  = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.SmoothingMode      = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $g.PixelOffsetMode    = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

        if ($DropAlpha) {
            $g.Clear([System.Drawing.Color]::White)
        } else {
            $g.Clear([System.Drawing.Color]::Transparent)
        }

        if ($RoundMask) {
            $path = New-Object System.Drawing.Drawing2D.GraphicsPath
            $path.AddEllipse(0, 0, $Size, $Size)
            $g.SetClip($path)
        }

        $contentSize = [int][Math]::Round($Size * $ContentScale)
        $offset      = [int][Math]::Round(($Size - $contentSize) / 2.0)
        $destRect    = New-Object System.Drawing.Rectangle $offset, $offset, $contentSize, $contentSize
        $g.DrawImage($Image, $destRect)
    } finally {
        $g.Dispose()
    }

    $bmp.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()

    $info = Get-Item $OutputPath
    $rel = Resolve-Path -Relative $OutputPath
    "  {0,-78}  {1,5}x{1,-5}  {2,6:N1} KB" -f $rel, $Size, ($info.Length / 1KB) | Write-Host
}

# Android adaptive-icon foreground (108dp canvas) + legacy launcher icons (48dp).
# Densities and their pixel multipliers per the Android density spec.
$androidRes = Join-Path $RepoRoot "android/app/src/main/res"
$densities = @(
    @{ Name = "mdpi";    Scale = 1.0 },
    @{ Name = "hdpi";    Scale = 1.5 },
    @{ Name = "xhdpi";   Scale = 2.0 },
    @{ Name = "xxhdpi";  Scale = 3.0 },
    @{ Name = "xxxhdpi"; Scale = 4.0 }
)

Write-Host ""
Write-Host "== Android =="
Write-Host ("(adaptive foreground content scale = {0:P0} of the 108dp canvas)" -f $ForegroundScale)
foreach ($d in $densities) {
    $folder = Join-Path $androidRes ("mipmap-" + $d.Name)
    $fgSize     = [int][Math]::Round(108 * $d.Scale)
    $legacySize = [int][Math]::Round( 48 * $d.Scale)

    # Adaptive icon foreground: the symbol lives inside the 72dp safe zone,
    # the surrounding transparent margin lets the OEM launcher mask freely
    # crop the outer 33% without ever touching the artwork. The adaptive
    # icon background colour (declared in colors.xml) fills the rest.
    Save-Resized -Image $src -Size $fgSize -OutputPath (Join-Path $folder "ic_launcher_foreground.png") `
        -ContentScale $ForegroundScale

    # Legacy raster icons for API < 26. Full-bleed at the canonical 48dp
    # launcher icon size — no mask, no scaling, since pre-Oreo launchers
    # don't apply adaptive shapes.
    Save-Resized -Image $src -Size $legacySize -OutputPath (Join-Path $folder "ic_launcher.png")
    Save-Resized -Image $src -Size $legacySize -OutputPath (Join-Path $folder "ic_launcher_round.png") `
        -RoundMask $true
}

# iOS AppIcon (single 1024 source, no alpha) + in-app About card icons.
$iosAssets = Join-Path $RepoRoot "ios/McController/Resources/Assets.xcassets"

Write-Host ""
Write-Host "== iOS =="
Save-Resized -Image $src -Size 1024 -OutputPath (Join-Path $iosAssets "AppIcon.appiconset/icon-1024.png") -DropAlpha $true
Save-Resized -Image $src -Size  256 -OutputPath (Join-Path $iosAssets "AppIconAbout.imageset/icon-256.png")
Save-Resized -Image $src -Size  512 -OutputPath (Join-Path $iosAssets "AppIconAbout.imageset/icon-512.png")

$src.Dispose()

Write-Host ""
Write-Host "Done."
