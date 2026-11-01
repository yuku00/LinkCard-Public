"""Original WebClipManager icon, drawn from geometry only; no external artwork.
Run with Pillow to regenerate the RGB PNGs. Artwork licensed under project MIT.
"""
from pathlib import Path
import json
from PIL import Image, ImageDraw

root = Path(__file__).resolve().parents[1] / 'Assets.xcassets'
icons = root / 'AppIcon.appiconset'
icons.mkdir(parents=True, exist_ok=True)
image = Image.new('RGB', (1024, 1024))
pixels = image.load()
for y in range(1024):
    for x in range(1024):
        t = (x + y) / 2046
        pixels[x, y] = tuple(round(a + (b - a) * t) for a, b in zip((24, 190, 177), (13, 104, 143)))
d = ImageDraw.Draw(image)
# An uncluttered browser card, with a globe and a bookmark corner.
d.rounded_rectangle((198, 226, 846, 846), radius=100, fill=(14, 114, 139))
d.rounded_rectangle((182, 178, 842, 806), radius=92, fill=(248, 254, 253))
d.line((222, 320, 802, 320), fill=(212, 238, 236), width=12)
for x in (252, 300, 348):
    d.ellipse((x-10, 245, x+10, 265), fill=(56, 165, 164))
d.ellipse((320, 386, 704, 770), outline=(19, 137, 150), width=24)
d.ellipse((420, 386, 604, 770), outline=(19, 137, 150), width=18)
d.line((330, 578, 694, 578), fill=(19, 137, 150), width=18)
d.arc((323, 460, 701, 636), 0, 180, fill=(19, 137, 150), width=16)
d.polygon([(680, 178), (768, 178), (768, 370), (724, 338), (680, 370)], fill=(255, 190, 94))
slots = [('iphone', '20', [2,3]), ('iphone', '29', [2,3]), ('iphone', '40', [2,3]),
         ('iphone', '60', [2,3]), ('ipad', '20', [1,2]), ('ipad', '29', [1,2]),
         ('ipad', '40', [1,2]), ('ipad', '76', [1,2]), ('ipad', '83.5', [2]),
         ('ios-marketing', '1024', [1])]
entries = []
for idiom, size, scales in slots:
    for scale in scales:
        px = int(float(size) * scale)
        filename = 'AppIcon-%d.png' % px
        image.resize((px, px), Image.Resampling.LANCZOS).save(icons / filename)
        entries.append({'idiom': idiom, 'size': size+'x'+size, 'scale': str(scale)+'x', 'filename': filename})
(icons / 'Contents.json').write_text(json.dumps({'images': entries, 'info': {'author': 'xcode', 'version': 1}}, indent=2)+'\n')
(root / 'Contents.json').write_text(json.dumps({'info': {'author': 'xcode', 'version': 1}}, indent=2)+'\n')
print('Generated original opaque RGB icons:', len(set(e['filename'] for e in entries)))
