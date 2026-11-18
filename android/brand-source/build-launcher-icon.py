#!/usr/bin/env python3
"""Generate both adaptive and legacy launcher PNGs from the supplied artwork."""
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "brand-source" / "Gold-Pirate-Ship-Original.png"
BACKGROUND = (6, 25, 32, 255)
DENSITIES = (
    ("mdpi", 48, 108),
    ("hdpi", 72, 162),
    ("xhdpi", 96, 216),
    ("xxhdpi", 144, 324),
    ("xxxhdpi", 192, 432),
)


def main():
    with Image.open(ART) as source:
        artwork = source.convert("RGBA")
    visible = artwork.getchannel("A").point(lambda a: 255 if a >= 100 else 0)
    bounds = visible.getbbox()
    if bounds is None:
        raise SystemExit("The artwork has no visible pixels")
    badge = artwork.crop(bounds)
    for density, legacy_px, layer_px in DENSITIES:
        legacy_dir = ROOT / "res" / f"mipmap-{density}"
        layer_dir = ROOT / "res" / f"drawable-{density}"
        legacy_dir.mkdir(parents=True, exist_ok=True)
        layer_dir.mkdir(parents=True, exist_ok=True)
        legacy = Image.new("RGBA", (legacy_px, legacy_px), BACKGROUND)
        legacy.alpha_composite(badge.resize((legacy_px, legacy_px), Image.Resampling.LANCZOS))
        legacy.convert("RGB").save(legacy_dir / "pyrate_launcher.png", optimize=True)
        badge_px = round(layer_px * 74 / 108)
        layer = Image.new("RGBA", (layer_px, layer_px))
        inset = (layer_px - badge_px) // 2
        layer.alpha_composite(badge.resize((badge_px, badge_px), Image.Resampling.LANCZOS), (inset, inset))
        layer.save(layer_dir / "pyrate_launcher_foreground.png", optimize=True)


if __name__ == "__main__":
    main()

