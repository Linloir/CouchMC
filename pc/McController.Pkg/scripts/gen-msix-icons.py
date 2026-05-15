"""Generate the PNG icon assets that Package.appxmanifest references.

Sources the highest-quality artwork we already have (the 1024×1024 macOS app
icon at `mac/McController/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png`)
and downscales it to every size MSIX expects. Output goes into the sibling
`Images/` directory next to this script's package.

Run from the repo root or from anywhere — paths are resolved relative to the
script itself.

    python pc/McController.Pkg/scripts/gen-msix-icons.py
"""

from __future__ import annotations

from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
SRC = ROOT / "mac" / "McController" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset" / "icon_512x512@2x.png"
OUT = ROOT / "pc" / "McController.Pkg" / "Images"

# Each tuple is (base_filename, base_size_px). Microsoft Store requires the
# scale-100 + scale-200 variants for tiles and the taskbar; scale-125/150/400
# are best-practice and don't cost much disk. The non-suffixed copy is what
# the Visual Studio designer drops when you click "Generate", and some tools
# (notably the older Store ingestion) still look it up by that name.
TARGETS = [
    ("StoreLogo", 50),
    ("Square44x44Logo", 44),
    ("Square150x150Logo", 150),
]
SCALES = [100, 125, 150, 200, 400]


def main() -> None:
    if not SRC.exists():
        raise SystemExit(f"source icon not found at {SRC}")
    OUT.mkdir(parents=True, exist_ok=True)

    base = Image.open(SRC).convert("RGBA")
    print(f"source: {SRC.name} {base.size}")

    for name, base_px in TARGETS:
        for scale in SCALES:
            px = round(base_px * scale / 100)
            small = base.resize((px, px), Image.LANCZOS)
            out_path = OUT / f"{name}.scale-{scale}.png"
            small.save(out_path, format="PNG", optimize=True)
        # Plain (unsuffixed) copy at the base size — matches the file name
        # the manifest references when no specific scale is present.
        plain = base.resize((base_px, base_px), Image.LANCZOS)
        plain.save(OUT / f"{name}.png", format="PNG", optimize=True)
        print(f"  {name}: scale-100..-400 + {base_px}px base")

    print(f"\nwrote {len(TARGETS) * (len(SCALES) + 1)} files into {OUT}")


if __name__ == "__main__":
    main()
