"""Read-only comparison of the fixed synthetic JPEG and native photo stills."""
import argparse
import hashlib
import json
from pathlib import Path
from PIL import Image

p = argparse.ArgumentParser()
p.add_argument('--before', required=True)
p.add_argument('--after', required=True)
p.add_argument('--jpeg', required=True)
p.add_argument('--output', required=True)
a = p.parse_args()
source = Image.open(a.jpeg)
assert source.format == 'JPEG' and source.width == source.height
assert source.getexif().get(274, 1) == 1
source = source.convert('RGB')

def inspect(path):
    image = Image.open(path).convert('RGB')
    rows = []
    for y in range(image.height):
        xs = []
        for x in range(image.width):
            r, g, b = image.getpixel((x, y))
            if (r < 130 and g - r > 60 and b - r > 60) or (r > 220 and 70 < g < 210 and b < 130 and r - g > 40 and g - b > 40):
                xs.append(x)
        if len(xs) > image.width * 0.6:
            rows.append((y, min(xs), max(xs) + 1))
    assert rows
    bounds = [min(v[1] for v in rows), rows[0][0], max(v[2] for v in rows), rows[-1][0] + 1]
    return image, bounds

before, before_bounds = inspect(a.before)
after, bounds = inspect(a.after)
w, h = bounds[2] - bounds[0], bounds[3] - bounds[1]
assert abs(h / w - 1) < 0.01
assert bounds[1] > 0 and bounds[3] < after.height
samples = []
for fraction in [0.25, 0.75]:
    actual = after.getpixel((bounds[0] + int(w * fraction), bounds[1] + h // 2))
    expected = source.getpixel((int(source.width * fraction), source.height // 2))
    error = max(abs(x - y) for x, y in zip(actual, expected))
    assert error <= 25
    samples.append({'fractionFromLeft': fraction, 'renderedRGB': actual,
                    'sourceRGB': expected, 'maxChannelError': error})
files = [Path(a.before), Path(a.after), Path(a.jpeg)]
out = {'status': 'complete square aspect and left/right colours match actual synthetic JPEG after native pan',
       'inputs': {str(f): {'bytes': f.stat().st_size, 'sha256': hashlib.sha256(f.read_bytes()).hexdigest()} for f in files},
       'beforeVisibleColourBounds': before_bounds, 'afterColourBounds': bounds,
       'afterColourSize': [w, h], 'sourceSize': list(source.size), 'samples': samples,
       'verifierSHA256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
       'scope': 'Known synthetic Source51 square JPEG only, using unchanged application bytes. '
                'Before-pan PNG is the repeat, not an original of the earlier uncaptured Source50 failure. '
                'No image rewrite, layout change, physical-device or whole recovery acceptance.'}
Path(a.output).write_text(json.dumps(out, indent=2) + '\n')
print('PASS:', bounds, 'square aspect', h / w, 'and source colour order')
