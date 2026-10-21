#!/usr/bin/env python3
"""Рисует иконку приложения Deshielo (светлую, тёмную и «tinted») через Pillow.

Запуск:  python3 tools/make_app_icon.py
Результат: Deshielo/Assets.xcassets/AppIcon.appiconset/AppIcon*.png (1024×1024).
"""
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
SCALE = 4  # рисуем в 4 раза крупнее и уменьшаем — так края получаются гладкими
S = SIZE * SCALE
OUT = Path(__file__).resolve().parent.parent / "Deshielo/Assets.xcassets/AppIcon.appiconset"


def hex_rgb(value: str) -> tuple:
    value = value.lstrip("#")
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


def gradient(top_left: str, bottom_right: str) -> Image.Image:
    a, b = hex_rgb(top_left), hex_rgb(bottom_right)
    small = Image.new("RGB", (256, 256))
    px = small.load()
    for y in range(256):
        for x in range(256):
            t = (x + y) / 510
            px[x, y] = tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))
    return small.resize((S, S), Image.BICUBIC)


def circle(draw, cx, cy, r, fill):
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=fill)


def swoosh(draw, p0, p1, p2, width, color):
    """Мазок соуса ложкой: кривая Безье с круглым началом и тонким «хвостом»."""
    steps = 900
    for i in range(steps + 1):
        t = i / steps
        x = (1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t ** 2 * p2[0]
        y = (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t ** 2 * p2[1]
        w = width * ((1 - t) ** 0.9) * min(1.0, 0.75 + t * 4)
        circle(draw, x, y, max(w, 2) / 2, color)


def render(palette: dict) -> Image.Image:
    img = gradient(palette["bg_a"], palette["bg_b"]).convert("RGBA")
    k = SCALE
    cx, cy = 512 * k, 500 * k

    # Тень под тарелкой
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    circle(sd, cx, cy + 30 * k, 352 * k, hex_rgb(palette["shadow"]) + (palette["shadow_alpha"],))
    shadow = shadow.filter(ImageFilter.GaussianBlur(38 * k))
    img = Image.alpha_composite(img, shadow)

    d = ImageDraw.Draw(img)
    # Тарелка и бортик
    circle(d, cx, cy, 352 * k, hex_rgb(palette["plate"]))
    circle(d, cx, cy, 266 * k, hex_rgb(palette["rim"]))
    circle(d, cx, cy, 259 * k, hex_rgb(palette["plate"]))

    # Мазок соуса по диагонали тарелки
    swoosh(d, (cx - 170 * k, cy + 118 * k), (cx + 10 * k, cy + 60 * k), (cx + 196 * k, cy - 128 * k),
           92 * k, hex_rgb(palette["sauce"]))
    for (dx, dy, r) in [(214, -150, 7), (226, -172, 5)]:
        circle(d, cx + dx * k, cy + dy * k, r * k, hex_rgb(palette["sauce"]))
    # Кнель (овал)
    qx, qy = cx - 58 * k, cy + 42 * k
    layer = Image.new("RGBA", (S, S), hex_rgb(palette["quenelle"]) + (0,))
    qd = ImageDraw.Draw(layer)
    qd.ellipse([qx - 96 * k, qy - 50 * k, qx + 96 * k, qy + 50 * k], fill=hex_rgb(palette["quenelle"]) + (255,))
    layer = layer.rotate(24, center=(qx, qy), resample=Image.BILINEAR)
    img = Image.alpha_composite(img, layer)
    d = ImageDraw.Draw(img)
    # Зелень и капли
    for (dx, dy, r, key) in [(40, -40, 19, "herb"), (74, -8, 13, "herb"), (10, -78, 10, "gold"),
                             (-150, -40, 9, "herb"), (118, -70, 8, "gold")]:
        circle(d, cx + dx * k, cy + dy * k, r * k, hex_rgb(palette[key]))
    return img.resize((SIZE, SIZE), Image.LANCZOS).convert("RGB")


LIGHT = dict(bg_a="#CC6634", bg_b="#8A3216", shadow="#4A170A", shadow_alpha=150,
             plate="#F8F2E9", rim="#E9DDCC", sauce="#B4532A", quenelle="#EDC47A", herb="#6E8B3D", gold="#E2A93B")
DARK = dict(bg_a="#2A201B", bg_b="#100C0A", shadow="#000000", shadow_alpha=200,
            plate="#2E2621", rim="#3D332C", sauce="#E07A4F", quenelle="#E8B866", herb="#8DAF55", gold="#F0B84A")

if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    render(LIGHT).save(OUT / "AppIcon.png")
    render(DARK).save(OUT / "AppIcon-Dark.png")
    render(LIGHT).convert("L").convert("RGB").save(OUT / "AppIcon-Tinted.png")
    print("Иконки сохранены в", OUT)
