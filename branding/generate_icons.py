"""Generate NetScope logo assets (eye/lens + packet flow).

Requires Pillow. Run from the repository root:
    python branding/generate_icons.py
"""

from __future__ import annotations

import math
import shutil
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent
ICONS = ROOT / "icons"
WINDOWS_RESOURCES = (
    ROOT.parent / "flutter-desktop-app" / "windows" / "runner" / "resources"
)

SIZE = 1024
ORANGE_DARK = (255, 74, 0, 255)
ORANGE = (255, 122, 38, 255)
ORANGE_LIGHT = (255, 176, 112, 255)
DARK = (11, 7, 5, 255)


def lerp(a: int, b: int, t: float) -> int:
    return round(a + (b - a) * t)


def gradient(size: int, top: tuple[int, int, int], bottom: tuple[int, int, int]) -> Image.Image:
    image = Image.new("RGBA", (size, size))
    draw = ImageDraw.Draw(image)
    for y in range(size):
        t = y / max(size - 1, 1)
        draw.line(
            [(0, y), (size, y)],
            fill=(lerp(top[0], bottom[0], t), lerp(top[1], bottom[1], t), lerp(top[2], bottom[2], t), 255),
        )
    return image


def cubic(p0, p1, p2, p3, steps: int = 96):
    points = []
    for i in range(steps + 1):
        t = i / steps
        u = 1 - t
        x = u**3 * p0[0] + 3 * u**2 * t * p1[0] + 3 * u * t**2 * p2[0] + t**3 * p3[0]
        y = u**3 * p0[1] + 3 * u**2 * t * p1[1] + 3 * u * t**2 * p2[1] + t**3 * p3[1]
        points.append((x, y))
    return points


def eye_points():
    points = []
    points += cubic((168, 512), (272, 350), (384, 288), (512, 288))
    points += cubic((512, 288), (640, 288), (752, 350), (856, 512))
    points += cubic((856, 512), (752, 674), (640, 736), (512, 736))
    points += cubic((512, 736), (384, 736), (272, 674), (168, 512))
    return points


def dashed(draw: ImageDraw.ImageDraw, start, end, fill, width, dash=26, gap=20):
    length = math.dist(start, end)
    if length == 0:
        return
    dx = (end[0] - start[0]) / length
    dy = (end[1] - start[1]) / length
    position = 0.0
    while position < length:
        segment_end = min(position + dash, length)
        draw.line(
            [
                (start[0] + dx * position, start[1] + dy * position),
                (start[0] + dx * segment_end, start[1] + dy * segment_end),
            ],
            fill=fill,
            width=width,
        )
        position += dash + gap


def blurred(size: int, painter, radius: int) -> Image.Image:
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    painter(ImageDraw.Draw(layer))
    return layer.filter(ImageFilter.GaussianBlur(radius))


def load_font(name: str, size: int) -> ImageFont.FreeTypeFont:
    path = Path("C:/Windows/Fonts") / name
    if path.exists():
        return ImageFont.truetype(str(path), size)
    return ImageFont.load_default()


def build_mark() -> Image.Image:
    image = gradient(SIZE, (43, 26, 16), (12, 8, 5))

    # Warm glow behind the lens.
    glow = Image.new("L", (SIZE, SIZE), 0)
    glow_draw = ImageDraw.Draw(glow)
    for radius in range(520, 0, -10):
        alpha = round(52 * (1 - radius / 520) ** 2)
        glow_draw.ellipse(
            [512 - radius, 512 - radius, 512 + radius, 512 + radius],
            fill=alpha,
        )
    image.paste(Image.new("RGBA", (SIZE, SIZE), (255, 92, 0, 255)), (0, 0), glow)

    points = eye_points()

    # Packet trails behind the eye.
    def trails(draw: ImageDraw.ImageDraw):
        dashed(draw, (38, 512), (150, 512), (255, 160, 90, 175), 10)
        dashed(draw, (874, 512), (986, 512), (255, 160, 90, 175), 10)

    image.alpha_composite(blurred(SIZE, trails, 18))
    trails(ImageDraw.Draw(image))

    # Eye glow + outline.
    def eye_glow(draw: ImageDraw.ImageDraw):
        draw.line(points, fill=(255, 92, 0, 165), width=112, joint="curve")

    image.alpha_composite(blurred(SIZE, eye_glow, 36))
    draw = ImageDraw.Draw(image)
    draw.line(points, fill=ORANGE_DARK, width=72, joint="curve")
    draw.line(points, fill=ORANGE, width=44, joint="curve")
    for endpoint in (points[0], points[-1]):
        draw.ellipse(
            [endpoint[0] - 36, endpoint[1] - 36, endpoint[0] + 36, endpoint[1] + 36],
            fill=ORANGE_DARK,
        )

    # Lens / pupil.
    def pupil_glow(draw: ImageDraw.ImageDraw):
        draw.ellipse([352, 352, 672, 672], fill=(255, 92, 0, 190))

    image.alpha_composite(blurred(SIZE, pupil_glow, 34))
    draw = ImageDraw.Draw(image)
    draw.ellipse([366, 366, 658, 658], fill=ORANGE_DARK)
    draw.ellipse([390, 390, 634, 634], fill=ORANGE)
    draw.ellipse([408, 408, 616, 616], fill=DARK)
    draw.ellipse([432, 432, 592, 592], outline=(255, 176, 112, 210), width=8)
    draw.ellipse([480, 480, 544, 544], fill=(255, 140, 60, 150))

    # Packet nodes at both sides of the lens.
    def packet_glow(draw: ImageDraw.ImageDraw):
        for x, radius in (
            (70, 18),
            (132, 26),
            (188, 14),
            (836, 14),
            (892, 26),
            (954, 18),
        ):
            draw.ellipse(
                [x - radius * 2, 512 - radius * 2, x + radius * 2, 512 + radius * 2],
                fill=(255, 160, 90, 150),
            )

    image.alpha_composite(blurred(SIZE, packet_glow, 22))
    draw = ImageDraw.Draw(image)
    for x, radius in (
        (70, 15),
        (132, 22),
        (188, 11),
        (836, 11),
        (892, 22),
        (954, 15),
    ):
        draw.ellipse(
            [x - radius, 512 - radius, x + radius, 512 + radius],
            fill=ORANGE_LIGHT,
        )
        draw.ellipse(
            [x - radius // 2, 512 - radius // 2, x + radius // 2, 512 + radius // 2],
            fill=(255, 240, 220, 235),
        )

    # Rounded mask + subtle warm rim.
    mask = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(mask).rounded_rectangle([32, 32, 992, 992], radius=216, fill=255)
    image.putalpha(mask)
    ImageDraw.Draw(image).rounded_rectangle(
        [40, 40, 984, 984],
        radius=208,
        outline=(255, 150, 80, 80),
        width=7,
    )
    return image


def write_pngs(mark: Image.Image) -> None:
    ICONS.mkdir(parents=True, exist_ok=True)
    sizes = [16, 20, 22, 24, 30, 32, 36, 40, 44, 48, 60, 64, 71, 72, 80, 96, 128, 150, 256, 310, 512, 1024]
    for size in sizes:
        mark.resize((size, size), Image.LANCZOS).save(ICONS / f"icon-{size}.png")
    mark.resize((512, 512), Image.LANCZOS).save(ICONS / "icon.png")
    mark.save(
        ICONS / "app_icon.ico",
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
    )
    WINDOWS_RESOURCES.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(ICONS / "app_icon.ico", WINDOWS_RESOURCES / "app_icon.ico")


def wide_tile(mark: Image.Image) -> Image.Image:
    tile = gradient(1024, (43, 26, 16), (12, 8, 5)).resize((310, 150), Image.LANCZOS)
    icon = mark.resize((118, 118), Image.LANCZOS)
    tile.alpha_composite(icon, (16, 16))
    draw = ImageDraw.Draw(tile)
    draw.text((150, 38), "NetScope", font=load_font("segoeuib.ttf", 31), fill=(255, 245, 238, 255))
    draw.text(
        (151, 76),
        "Network monitor",
        font=load_font("segoeui.ttf", 14),
        fill=(255, 176, 112, 255),
    )
    return tile


def store_assets(mark: Image.Image) -> None:
    amo = ROOT / "store" / "amo"
    microsoft = ROOT / "store" / "microsoft"
    snap = ROOT / "store" / "snap"
    for directory in (amo, microsoft, snap):
        directory.mkdir(parents=True, exist_ok=True)

    mark.resize((32, 32), Image.LANCZOS).save(amo / "icon-32.png")
    mark.resize((64, 64), Image.LANCZOS).save(amo / "icon-64.png")

    mark.resize((300, 300), Image.LANCZOS).save(microsoft / "app-tile-300.png")

    box = gradient(1080, (43, 26, 16), (12, 8, 5))
    icon = mark.resize((500, 500), Image.LANCZOS)
    box.alpha_composite(icon, (290, 190))
    draw = ImageDraw.Draw(box)
    title = "NetScope"
    font = load_font("segoeuib.ttf", 92)
    width = draw.textlength(title, font=font)
    draw.text(((1080 - width) / 2, 730), title, font=font, fill=(255, 245, 238, 255))
    tagline = "Network visibility without the noise"
    font = load_font("segoeui.ttf", 36)
    width = draw.textlength(tagline, font=font)
    draw.text(((1080 - width) / 2, 850), tagline, font=font, fill=(255, 176, 112, 255))
    box.save(microsoft / "box-art-1080.png")

    hero = gradient(1920, (43, 26, 16), (12, 8, 5))
    icon = mark.resize((560, 560), Image.LANCZOS)
    hero.alpha_composite(icon, (680, 260))
    hero.save(microsoft / "super-hero-1920.png")

    mark.resize((256, 256), Image.LANCZOS).save(snap / "banner-icon.png")
    snap_wide = wide_tile(mark).resize((1920, 640), Image.LANCZOS)
    snap_wide.save(snap / "banner.png")


LOGO_SVG = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" width="256" height="256" role="img" aria-label="NetScope">
<title>NetScope</title>
<desc>An eye and camera lens with packet-flow nodes.</desc>
<defs>
  <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#2B1A10"/>
    <stop offset="1" stop-color="#0C0805"/>
  </linearGradient>
  <linearGradient id="eye" x1="0" y1="0" x2="1" y2="0">
    <stop offset="0" stop-color="#FF4A00"/>
    <stop offset="0.55" stop-color="#FF7A26"/>
    <stop offset="1" stop-color="#FFB070"/>
  </linearGradient>
  <radialGradient id="glow">
    <stop offset="0" stop-color="#FF5C00" stop-opacity="0.30"/>
    <stop offset="1" stop-color="#FF5C00" stop-opacity="0"/>
  </radialGradient>
</defs>
<rect x="8" y="8" width="240" height="240" rx="54" fill="url(#bg)"/>
<circle cx="128" cy="128" r="96" fill="url(#glow)"/>
<g fill="none" stroke="#FFA05A" stroke-opacity="0.55" stroke-width="2.5" stroke-dasharray="6 5">
  <path d="M9 128 H38"/>
  <path d="M218 128 H247"/>
</g>
<path d="M42 128 C68 87 96 72 128 72 C160 72 188 87 214 128 C188 169 160 184 128 184 C96 184 68 169 42 128Z" fill="none" stroke="url(#eye)" stroke-width="18" stroke-linejoin="round"/>
<circle cx="128" cy="128" r="37" fill="#FF4A00"/>
<circle cx="128" cy="128" r="31" fill="#FF7A26"/>
<circle cx="128" cy="128" r="26" fill="#0B0705"/>
<circle cx="128" cy="128" r="21" fill="none" stroke="#FFB070" stroke-opacity="0.82" stroke-width="2"/>
<circle cx="128" cy="128" r="8" fill="#FF8C3C" fill-opacity="0.6"/>
<g fill="#FFB070">
  <circle cx="17" cy="128" r="4"/>
  <circle cx="33" cy="128" r="5.5"/>
  <circle cx="47" cy="128" r="2.75"/>
  <circle cx="209" cy="128" r="2.75"/>
  <circle cx="223" cy="128" r="5.5"/>
  <circle cx="239" cy="128" r="4"/>
</g>
</svg>
"""

BANNER_SVG = """<svg xmlns="http://www.w3.org/2000/svg" width="1280" height="480" viewBox="0 0 1280 480" role="img" aria-label="NetScope">
<title>NetScope</title>
<desc>System-wide network monitoring with an eye-and-lens packet-flow mark.</desc>
<defs>
  <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
    <stop offset="0" stop-color="#2B1A10"/>
    <stop offset="1" stop-color="#0C0805"/>
  </linearGradient>
  <linearGradient id="eye" x1="0" y1="0" x2="1" y2="0">
    <stop offset="0" stop-color="#FF4A00"/>
    <stop offset="1" stop-color="#FFB070"/>
  </linearGradient>
</defs>
<rect width="1280" height="480" fill="url(#bg)"/>
<rect x="1" y="1" width="1278" height="478" fill="none" stroke="#FF7A26" stroke-opacity="0.25" stroke-width="2"/>
<g transform="translate(110 92) scale(1.16)">
  <circle cx="128" cy="128" r="96" fill="#FF5C00" fill-opacity="0.12"/>
  <g fill="none" stroke="#FFA05A" stroke-opacity="0.55" stroke-width="2.5" stroke-dasharray="6 5">
    <path d="M9 128 H38"/>
    <path d="M218 128 H247"/>
  </g>
  <path d="M42 128 C68 87 96 72 128 72 C160 72 188 87 214 128 C188 169 160 184 128 184 C96 184 68 169 42 128Z" fill="none" stroke="url(#eye)" stroke-width="18" stroke-linejoin="round"/>
  <circle cx="128" cy="128" r="37" fill="#FF4A00"/>
  <circle cx="128" cy="128" r="31" fill="#FF7A26"/>
  <circle cx="128" cy="128" r="26" fill="#0B0705"/>
  <circle cx="128" cy="128" r="8" fill="#FF8C3C" fill-opacity="0.6"/>
  <g fill="#FFB070">
    <circle cx="17" cy="128" r="4"/>
    <circle cx="33" cy="128" r="5.5"/>
    <circle cx="47" cy="128" r="2.75"/>
    <circle cx="209" cy="128" r="2.75"/>
    <circle cx="223" cy="128" r="5.5"/>
    <circle cx="239" cy="128" r="4"/>
  </g>
</g>
<text x="470" y="196" font-family="Segoe UI, Ubuntu, Cantarell, sans-serif" font-weight="700" font-size="76" fill="#FFF5EE">NetScope</text>
<rect x="472" y="224" width="180" height="8" rx="4" fill="#FF7A26"/>
<text x="472" y="292" font-family="Segoe UI, Ubuntu, Cantarell, sans-serif" font-size="30" fill="#FFB070">See every connection. Keep it local.</text>
<g font-family="Segoe UI, Ubuntu, Cantarell, sans-serif" font-size="23" fill="#EBD9CC">
  <rect x="472" y="334" width="218" height="46" rx="23" fill="#1A100A" stroke="#FF7A26" stroke-opacity="0.45"/>
  <text x="494" y="365">Windows ETW capture</text>
  <rect x="706" y="334" width="160" height="46" rx="23" fill="#1A100A" stroke="#FF7A26" stroke-opacity="0.45"/>
  <text x="728" y="365">Local SQLite</text>
  <rect x="882" y="334" width="190" height="46" rx="23" fill="#1A100A" stroke="#FF7A26" stroke-opacity="0.45"/>
  <text x="904" y="365">Hosts file editor</text>
</g>
</svg>
"""


def write_svgs() -> None:
    (ROOT / "logo.svg").write_text(LOGO_SVG, encoding="utf-8")
    (ROOT / "github-banner.svg").write_text(BANNER_SVG, encoding="utf-8")


def main() -> None:
    mark = build_mark()
    write_pngs(mark)
    store_assets(mark)
    write_svgs()
    wide_tile(mark).save(ICONS / "icon-310x150.png")
    mark.resize((310, 310), Image.LANCZOS).save(ICONS / "icon-310.png")
    print(f"Wrote NetScope logo assets to {ICONS}")


if __name__ == "__main__":
    main()
