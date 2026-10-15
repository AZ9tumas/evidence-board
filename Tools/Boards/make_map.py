"""Schematic map of Vlora Bay for the Albania board. Positions approximate."""
import math
import random
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT = sys.argv[1]
W, H = 1000, 1300
TOP = 110  # title band
LON0, LON1 = 19.12, 19.62
LAT0, LAT1 = 40.70, 40.24
K = W / ((LON1 - LON0) * math.cos(math.radians(40.47)))


def xy(lat, lon):
    return ((lon - LON0) * math.cos(math.radians(40.47)) * K, TOP + (LAT0 - lat) * K)


SERIF = "/usr/share/fonts/truetype/dejavu/DejaVuSerif.ttf"
SERIF_B = "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf"
SERIF_I = "/usr/share/fonts/truetype/liberation/LiberationSerif-Italic.ttf"
SANS_B = "/usr/share/fonts/opentype/inter/Inter-Bold.otf"
SANS = "/usr/share/fonts/opentype/inter/Inter-Medium.otf"


def font(path, size):
    return ImageFont.truetype(path, size)


random.seed(7)
paper = (236, 226, 202)
img = Image.new("RGB", (W, H), paper)
d = ImageDraw.Draw(img)

# Sea
sea = (150, 178, 182)
d.rectangle([0, TOP, W, H], fill=sea)
for _ in range(900):  # ripples
    x, y = random.uniform(0, W), random.uniform(TOP, H)
    d.line([x, y, x + random.uniform(6, 16), y], fill=(165, 192, 195), width=1)

land = [
    (40.70, 19.36), (40.64, 19.32), (40.60, 19.335), (40.565, 19.36), (40.545, 19.372),
    (40.525, 19.38), (40.505, 19.384), (40.495, 19.395), (40.49, 19.42), (40.482, 19.445),
    (40.472, 19.47), (40.462, 19.488), (40.445, 19.495), (40.42, 19.493), (40.39, 19.488),
    (40.36, 19.478), (40.335, 19.47), (40.32, 19.455), (40.325, 19.43), (40.345, 19.405),
    (40.37, 19.375), (40.395, 19.345), (40.415, 19.315), (40.432, 19.295), (40.425, 19.284),
    (40.40, 19.30), (40.37, 19.325), (40.34, 19.35), (40.31, 19.375), (40.28, 19.40),
    (40.25, 19.43), (40.24, 19.44), (40.24, 19.62), (40.70, 19.62),
]
land_px = [xy(*p) for p in land]
# Shoreline glow, then land
shore = Image.new("L", (W, H), 0)
ImageDraw.Draw(shore).polygon(land_px, fill=255)
glow = shore.filter(ImageFilter.GaussianBlur(14))
img.paste((182, 204, 204), mask=glow)
d = ImageDraw.Draw(img)
land_color = (228, 214, 182)
d.polygon(land_px, fill=land_color)
# Relief hatching on the Karaburun ridge and inland hills
for _ in range(500):
    lat = random.uniform(40.30, 40.42)
    lon = random.uniform(19.30, 19.42)
    t = (40.42 - lat) / 0.12
    centre = 19.30 + t * 0.10
    if abs(lon - centre) < 0.018:
        x, y = xy(lat, lon)
        d.line([x, y, x + 5, y - 7], fill=(196, 176, 140), width=1)
for _ in range(700):
    lat = random.uniform(40.26, 40.68)
    lon = random.uniform(19.52, 19.62)
    x, y = xy(lat, lon)
    d.line([x, y, x + 5, y - 7], fill=(204, 186, 152), width=1)
d.line(land_px + [land_px[0]], fill=(120, 104, 78), width=2)

# Narta Lagoon
lagoon = [(40.568, 19.392), (40.566, 19.425), (40.556, 19.458), (40.538, 19.478), (40.518, 19.472),
          (40.508, 19.448), (40.507, 19.418), (40.513, 19.398), (40.53, 19.386), (40.552, 19.384)]
lag_px = [xy(*p) for p in lagoon]
d.polygon(lag_px, fill=(176, 206, 204), outline=(120, 104, 78))
lag_mask = Image.new("L", (W, H), 0)
ImageDraw.Draw(lag_mask).polygon(lag_px, fill=255)
placed = 0
while placed < 70:  # flamingos
    x, y = random.uniform(min(p[0] for p in lag_px), max(p[0] for p in lag_px)), random.uniform(min(p[1] for p in lag_px), max(p[1] for p in lag_px))
    if lag_mask.getpixel((int(x), int(y))) and lag_mask.getpixel((int(x) + 8, int(y))) and lag_mask.getpixel((int(x) - 8, int(y))):
        d.ellipse([x - 2.5, y - 2.5, x + 2.5, y + 2.5], fill=(232, 112, 146))
        placed += 1
# Zvërnec islet (monastery)
zx, zy = xy(40.517, 19.41)
d.ellipse([zx - 6, zy - 4, zx + 6, zy + 4], fill=land_color, outline=(120, 104, 78))

# Sazan Island
saz = []
for i in range(40):
    a = 2 * math.pi * i / 40
    lat = 40.497 + 0.022 * math.cos(a)
    lon = 19.274 + 0.011 * math.sin(a) + 0.004 * math.cos(a)
    saz.append(xy(lat, lon))
d.polygon(saz, fill=land_color, outline=(120, 104, 78))

# Vjosa river
river = [(40.64, 19.32), (40.645, 19.36), (40.64, 19.40), (40.655, 19.45), (40.66, 19.50), (40.645, 19.56), (40.62, 19.62)]
d.line([xy(*p) for p in river], fill=(126, 160, 168), width=5, joint="curve")

# Title band
d.rectangle([0, 0, W, TOP], fill=(42, 33, 24))
d.text((40, 22), "VLORA BAY  ·  ALBANIA", font=font(SERIF_B, 40), fill=(244, 232, 205))
d.text((42, 72), "Schematic map, drawn for this board. Coastline and positions approximate.", font=font(SERIF_I, 22), fill=(214, 196, 160))


def label(text, lat, lon, size=24, fill=(70, 58, 40), f=SERIF_I, anchor="mm", spacing=0):
    x, y = xy(lat, lon)
    if spacing:
        text = (" " * spacing).join(text)
    d.text((x, y), text, font=font(f, size), fill=fill, anchor=anchor)


label("ADRIATIC SEA", 40.32, 19.21, 30, (70, 98, 104), spacing=1)
label("VLORA BAY", 40.42, 19.405, 26, (70, 98, 104), spacing=1)
label("Narta Lagoon", 40.545, 19.432, 22, (50, 80, 86))
label("Vjosa River", 40.641, 19.555, 20, (70, 98, 104))
label("Vlorë", 40.462, 19.53, 26, (60, 48, 32), SERIF_B)
d.ellipse([xy(40.462, 19.488)[0] - 7, xy(40.462, 19.488)[1] - 7, xy(40.462, 19.488)[0] + 7, xy(40.462, 19.488)[1] + 7], fill=(60, 48, 32))

# Karaburun label along the ridge
kar = Image.new("RGBA", (420, 40), (0, 0, 0, 0))
ImageDraw.Draw(kar).text((210, 20), "K a r a b u r u n   P e n i n s u l a", font=font(SERIF_I, 22), fill=(110, 90, 60, 255), anchor="mm")
kar = kar.rotate(48, expand=True, resample=Image.BICUBIC)
kx, ky = xy(40.36, 19.36)
img.paste(kar, (int(kx - kar.width / 2), int(ky - kar.height / 2)), kar)
d = ImageDraw.Draw(img)

# Markers and callouts
RED = (178, 30, 40)


def pin(lat, lon):
    x, y = xy(lat, lon)
    d.ellipse([x - 13, y - 13, x + 13, y + 13], outline=RED, width=4)
    d.ellipse([x - 4, y - 4, x + 4, y + 4], fill=RED)
    return x, y


def callout(px, py, bx, by, title, lines, width=360):
    tf, lf = font(SANS_B, 22), font(SANS, 18)
    h = 16 + 30 + 24 * len(lines) + 10
    d.line([px, py, bx + (0 if bx > px else width), by + 26], fill=RED, width=3)
    d.rectangle([bx + 4, by + 4, bx + width + 4, by + h + 4], fill=(150, 130, 100))
    d.rectangle([bx, by, bx + width, by + h], fill=(250, 244, 228), outline=(60, 48, 32), width=2)
    d.text((bx + 14, by + 12), title, font=tf, fill=RED)
    for i, line in enumerate(lines):
        d.text((bx + 14, by + 46 + 24 * i), line, font=lf, fill=(40, 32, 22))


sx, sy = pin(40.497, 19.276)
callout(sx, sy, 24, 760, "SAZAN ISLAND", [
    "Resort plan: 45 ha, €1.4 billion",
    "\"Strategic investor\" status:",
    "30 Dec 2024 (Atlantic Incubation",
    "Partners, linked to Affinity)",
])
zx2, zy2 = pin(40.505, 19.392)
callout(zx2, zy2, 30, 200, "ZVËRNEC", [
    "Land bought for €230 million",
    "(Kushner's statement)",
    "30 May 2026: guards drag away a",
    "protester at the fence. Spark of",
    "the \"Flamingo Revolution\"",
], width=380)
nx, ny = xy(40.548, 19.462)
callout(nx, ny, 585, 300, "VJOSA–NARTA", [
    "Protected Landscape: flamingos,",
    "dunes, wetlands. Law 21/2024",
    "(22 Feb 2024) opened protected",
    "areas to 5-star resorts",
], width=400)

# North arrow and scale bar
ax, ay = W - 70, H - 170
d.polygon([(ax, ay - 50), (ax - 16, ay + 10), (ax, ay), (ax + 16, ay + 10)], fill=(60, 48, 32))
d.text((ax, ay - 70), "N", font=font(SERIF_B, 26), fill=(60, 48, 32), anchor="mm")
five_km = 5 / 111 * K
bx0, by0 = W - 60 - five_km, H - 60
d.rectangle([bx0, by0, bx0 + five_km / 2, by0 + 10], fill=(60, 48, 32))
d.rectangle([bx0 + five_km / 2, by0, bx0 + five_km, by0 + 10], fill=paper, outline=(60, 48, 32))
d.text((bx0 + five_km / 2, by0 - 18), "≈ 5 km", font=font(SERIF, 20), fill=(60, 48, 32), anchor="mm")

# Tirana pointer
tx, ty = W - 40, TOP + 40
d.text((tx, ty), "Tirana, ~110 km  ↗", font=font(SERIF_I, 22), fill=(60, 48, 32), anchor="rm")
d.text((tx, ty + 28), "protests from 31 May 2026", font=font(SERIF_I, 18), fill=(110, 90, 60), anchor="rm")

# Paper grain and vignette
noise = Image.effect_noise((W, H), 18).convert("L")
img = Image.composite(img, Image.new("RGB", (W, H), (120, 100, 70)), noise.point(lambda v: 255 if v > 40 else 235))
vig = Image.new("L", (W, H), 0)
ImageDraw.Draw(vig).rectangle([30, 30, W - 30, H - 30], fill=255)
vig = vig.filter(ImageFilter.GaussianBlur(60))
img = Image.composite(img, Image.new("RGB", (W, H), (150, 125, 90)), vig)
img.save(OUT, "JPEG", quality=84, optimize=True)
print(OUT, img.size)
