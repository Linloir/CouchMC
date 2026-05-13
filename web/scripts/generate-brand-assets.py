from pathlib import Path

from PIL import Image, ImageDraw

COS30 = 0.8660254037844387
SIN30 = 0.5
GRID = 16

GRASS_BASE = (0x6F, 0xB0, 0x35, 255)
GRASS_DARK = (0x55, 0x8F, 0x25, 255)
GRASS_DARKER = (0x4A, 0x7F, 0x1F, 255)
GRASS_LIGHT = (0x7F, 0xC3, 0x42, 255)
DIRT_BASE = (0x88, 0x5C, 0x36, 255)
DIRT_DARK = (0x6E, 0x46, 0x25, 255)
DIRT_DARKER = (0x55, 0x36, 0x1B, 255)
DIRT_LIGHT = (0xA0, 0x73, 0x49, 255)


def variant(i: int, j: int, salt: int) -> int:
    h = (i * 73856093) ^ (j * 19349663) ^ (salt * 83492791)
    return ((h ^ (h >> 13)) & 0x7FFFFFFF) % 100


def grass_top_color(i: int, j: int) -> tuple[int, int, int, int]:
    v = variant(i, j, 1)
    if v < 10:
        return GRASS_DARKER
    if v < 25:
        return GRASS_DARK
    if v < 40:
        return GRASS_LIGHT
    return GRASS_BASE


def dirt_side_color(i: int, j: int, is_right: bool) -> tuple[int, int, int, int]:
    v = variant(i, j, 2 if is_right else 3)
    if j < 3:
        color = GRASS_DARKER if v < 30 else GRASS_DARK if v < 55 else GRASS_BASE
    elif j == 3:
        color = GRASS_DARKER if v < 50 else DIRT_DARK
    else:
        color = (
            DIRT_DARKER
            if v < 15
            else DIRT_LIGHT
            if v < 30
            else DIRT_DARK
            if v < 50
            else DIRT_BASE
        )

    if is_right:
        return (int(color[0] * 0.78), int(color[1] * 0.78), int(color[2] * 0.78), 255)
    return color


def bilinear(tl, tr, br, bl, u: float, v: float) -> tuple[float, float]:
    top_x = tl[0] + (tr[0] - tl[0]) * u
    top_y = tl[1] + (tr[1] - tl[1]) * u
    bot_x = bl[0] + (br[0] - bl[0]) * u
    bot_y = bl[1] + (br[1] - bl[1]) * u
    return (top_x + (bot_x - top_x) * v, top_y + (bot_y - top_y) * v)


def draw_face(draw: ImageDraw.ImageDraw, tl, tr, br, bl, color_fn, mul: int) -> None:
    for j in range(GRID):
        for i in range(GRID):
            u0 = i / GRID
            u1 = (i + 1) / GRID
            v0 = j / GRID
            v1 = (j + 1) / GRID
            points = [
                bilinear(tl, tr, br, bl, u0, v0),
                bilinear(tl, tr, br, bl, u1, v0),
                bilinear(tl, tr, br, bl, u1, v1),
                bilinear(tl, tr, br, bl, u0, v1),
            ]
            scaled = [(x * mul, y * mul) for x, y in points]
            color = color_fn(i, j)
            draw.polygon(scaled, fill=color, outline=color)


def render_grass_block(size: int, content_scale: float = 0.92) -> Image.Image:
    mul = 4
    image = Image.new("RGBA", (size * mul, size * mul), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    cx = size / 2
    cy = size / 2 - size * 0.025
    scale = size * 0.42 * content_scale

    def p(x: float, y: float, z: float) -> tuple[float, float]:
        return (cx + (x - y) * COS30 * scale, cy + ((x + y) * SIN30 - z) * scale)

    v_top_back = p(0, 0, 1)
    v_top_right = p(1, 0, 1)
    v_top_front = p(1, 1, 1)
    v_top_left = p(0, 1, 1)
    v_bot_right = p(1, 0, 0)
    v_bot_front = p(1, 1, 0)
    v_bot_left = p(0, 1, 0)

    draw_face(draw, v_top_back, v_top_right, v_top_front, v_top_left, grass_top_color, mul)
    draw_face(
        draw,
        v_top_left,
        v_top_front,
        v_bot_front,
        v_bot_left,
        lambda i, j: dirt_side_color(i, j, False),
        mul,
    )
    draw_face(
        draw,
        v_top_right,
        v_top_front,
        v_bot_front,
        v_bot_right,
        lambda i, j: dirt_side_color(i, j, True),
        mul,
    )
    return image.resize((size, size), Image.Resampling.LANCZOS)


def main() -> None:
    out_dir = Path(__file__).resolve().parents[1] / "public" / "brand"
    out_dir.mkdir(parents=True, exist_ok=True)
    for size in (64, 128, 256, 512):
        render_grass_block(size).save(out_dir / f"grass-block-{size}.png")
    render_grass_block(256).save(out_dir / "grass-block.png")


if __name__ == "__main__":
    main()
