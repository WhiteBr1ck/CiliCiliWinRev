"""Generate the app's vector-style launch icon using Pillow."""
from pathlib import Path
from PIL import Image, ImageDraw

size = 1024
image = Image.new('RGBA', (size, size))
draw = ImageDraw.Draw(image)
draw.rounded_rectangle((32, 32, 992, 992), radius=248, fill='#30234D')
draw.arc((176, 176, 848, 848), 42, 318, fill='#CDBDFF', width=112)
draw.arc((356, 356, 668, 668), 42, 318, fill='#A8E9D3', width=76)
draw.polygon([(700, 426), (700, 598), (844, 512)], fill='#A8E9D3')
target = Path(__file__).resolve().parent.parent / 'windows/runner/resources/app_icon.ico'
image.save(target, format='ICO', sizes=[(s, s) for s in (16, 24, 32, 48, 64, 128, 256)])

image.resize((256,256), Image.Resampling.LANCZOS).save(Path(__file__).resolve().parent.parent / 'assets/logo.png')
