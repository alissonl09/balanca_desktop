"""Development-only synthetic fixtures. Requires Pillow; no runtime download.

These are NOT webcam photographs. Uses the project's existing DS-Digital font.
Run from the repository root: python tool/generate_seven_segment_fixtures.py
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

root = Path(__file__).resolve().parents[1]
destination = root / "test/fixtures/seven_segment"
destination.mkdir(parents=True, exist_ok=True)
font = ImageFont.truetype(str(root / "assets/fonts/DS-Digital.ttf"), 100)
for name, text in [("12190", "12190"), ("570_decimal", "570.0"), ("zero", "0.00")]:
    image = Image.new("RGB", (480, 140), "black")
    ImageDraw.Draw(image).text((20, 6), text, font=font, fill=(30, 240, 95), stroke_width=1)
    image.save(destination / f"{name}.png")
