"""Independently inspect the known synthetic two-colour JPEG on native PNGs.

This is read-only pixel verification, never an image rewrite. AX Form row bounds
include padding; they cannot establish the rendered image's exact aspect ratio.
"""
import argparse
import hashlib
import json
from pathlib import Path
from PIL import Image, ImageOps

parser = argparse.ArgumentParser()
parser.add_argument('--image', required=True)
parser.add_argument('--jpeg', required=True)
parser.add_argument('--frame', required=True)
parser.add_argument('--output', required=True)
args = parser.parse_args()
image_path, jpeg_path, frame_path = map(Path, [args.image, args.jpeg, args.frame])
image = Image.open(image_path).convert('RGB')
source = Image.open(jpeg_path)
assert source.format == 'JPEG' and source.getexif().get(274) == 6
expected = ImageOps.exif_transpose(source).convert('RGB')
width, height = image.size
rows = []
for y in range(height):
    positions = []
    for x in range(width):
        r, g, b = image.getpixel((x, y))
        if (r < 130 and g > 100 and b > 120) or (r > 220 and 70 < g < 210 and b < 130):
            positions.append(x)
    if len(positions) > width * 0.6:
        rows.append((y, min(positions), max(positions) + 1))
assert rows, 'No large synthetic image colour area'
bounds = [min(r[1] for r in rows), rows[0][0], max(r[2] for r in rows), rows[-1][0] + 1]
w, h = bounds[2] - bounds[0], bounds[3] - bounds[1]
assert abs(h / w - expected.height / expected.width) < 0.01
samples = []
for fraction in [0.25, 0.75]:
    actual = image.getpixel((bounds[0] + w // 2, bounds[1] + int(h * fraction)))
    wanted = expected.getpixel((expected.width // 2, int(expected.height * fraction)))
    error = max(abs(a - b) for a, b in zip(actual, wanted))
    assert error <= 25, 'Photo orientation/colour order differs from the actual JPEG'
    samples.append({'fractionFromTop': fraction, 'renderedRGB': actual, 'sourceRGB': wanted, 'maxChannelError': error})
frame = json.loads(frame_path.read_text())
assert frame['width'] > 0 and frame['height'] > frame['width']
result = {
    'status': 'rendered aspect and colour order match actual EXIF-oriented source',
    'inputs': {str(p): {'bytes': p.stat().st_size, 'sha256': hashlib.sha256(p.read_bytes()).hexdigest()}
               for p in [image_path, jpeg_path, frame_path]},
    'verifierSHA256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
    'pixelBounds': bounds, 'pixelWidth': w, 'pixelHeight': h, 'pixelAspect': h / w,
    'sourceOrientation': 6, 'sourceSize': source.size, 'orientedSourceSize': expected.size,
    'samples': samples, 'AXFrame': frame,
    'scope': 'Known synthetic JPEG only. Read-only original-pixel/source comparison, not actual customer-photo or device acceptance.'
}
Path(args.output).write_text(json.dumps(result, indent=2) + '\n')
print('PASS:', bounds, 'rendered aspect', h / w, 'and both source colour positions')
