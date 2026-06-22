#!/usr/bin/env python3
"""Generate modern flat icons for InfiniteRicks Qt GUI and Android."""

import math
import os
import sys
from PIL import Image, ImageDraw, PngImagePlugin

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ICON_DIR = os.path.join(REPO, "src", "qt", "res", "icons")
ANDROID_RES = os.path.join(REPO, "src", "qt", "android", "res")
ANDROID_LAUNCHER_SOURCE = os.path.join(REPO, "src", "qt", "res", "images", "splash.png")

BRAND = (94, 174, 76, 255)
BRAND_DARK = (77, 154, 62, 255)
WHITE = (255, 255, 255, 255)
MUTED = (118, 128, 144, 255)
RED = (239, 68, 68, 255)
AMBER = (245, 158, 11, 255)


def stroke(size):
    return max(2, round(size * 0.08))


def pad(size):
    return round(size * 0.18)


def line(draw, size, pts, color, width=None):
    w = width or stroke(size)
    scaled = [(pad(size) + x * (size - 2 * pad(size)),
               pad(size) + y * (size - 2 * pad(size))) for x, y in pts]
    draw.line(scaled, fill=color, width=w, joint="curve")


def poly(draw, size, pts, color, width=None):
    w = width or stroke(size)
    scaled = [(pad(size) + x * (size - 2 * pad(size)),
               pad(size) + y * (size - 2 * pad(size))) for x, y in pts]
    if len(scaled) > 2:
        draw.polygon(scaled, outline=color, fill=None)
    draw.line(scaled + [scaled[0]], fill=color, width=w, joint="curve")


def circle(draw, size, cx, cy, r, color, width=None):
    w = width or stroke(size)
    scale = size - 2 * pad(size)
    x0 = pad(size) + (cx - r) * scale
    y0 = pad(size) + (cy - r) * scale
    x1 = pad(size) + (cx + r) * scale
    y1 = pad(size) + (cy + r) * scale
    draw.ellipse([x0, y0, x1, y1], outline=color, width=w)


def arc(draw, size, cx, cy, r, start, end, color, width=None):
    w = width or stroke(size)
    scale = size - 2 * pad(size)
    x0 = pad(size) + (cx - r) * scale
    y0 = pad(size) + (cy - r) * scale
    x1 = pad(size) + (cx + r) * scale
    y1 = pad(size) + (cy + r) * scale
    draw.arc([x0, y0, x1, y1], start=start, end=end, fill=color, width=w)


def render(draw_fn, size, color=WHITE):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    draw_fn(draw, size, color)
    return img


def draw_send(draw, size, color):
    line(draw, size, [(0.15, 0.82), (0.5, 0.5), (0.85, 0.18)], color)
    line(draw, size, [(0.5, 0.5), (0.85, 0.18)], color)
    line(draw, size, [(0.62, 0.18), (0.85, 0.18), (0.85, 0.41)], color)


def draw_receive(draw, size, color):
    line(draw, size, [(0.5, 0.15), (0.5, 0.72)], color)
    line(draw, size, [(0.32, 0.38), (0.5, 0.58), (0.68, 0.38)], color)
    line(draw, size, [(0.2, 0.78), (0.8, 0.78)], color)


def draw_history(draw, size, color):
    circle(draw, size, 0.5, 0.5, 0.34, color)
    line(draw, size, [(0.5, 0.5), (0.5, 0.28)], color)
    line(draw, size, [(0.5, 0.5), (0.66, 0.5)], color)


def draw_overview(draw, size, color):
    poly(draw, size, [(0.5, 0.12), (0.82, 0.38), (0.82, 0.82), (0.18, 0.82), (0.18, 0.38)], color)
    poly(draw, size, [(0.42, 0.82), (0.42, 0.55), (0.58, 0.55), (0.58, 0.82)], color)


def draw_options(draw, size, color):
    circle(draw, size, 0.5, 0.5, 0.14, color)
    for i in range(8):
        a = i * math.pi / 4
        x1 = 0.5 + 0.22 * math.cos(a)
        y1 = 0.5 - 0.22 * math.sin(a)
        x2 = 0.5 + 0.38 * math.cos(a)
        y2 = 0.5 - 0.38 * math.sin(a)
        line(draw, size, [(x1, y1), (x2, y2)], color)


def draw_debug(draw, size, color):
    poly(draw, size, [(0.12, 0.18), (0.5, 0.12), (0.88, 0.18), (0.78, 0.82), (0.22, 0.82)], color)
    line(draw, size, [(0.28, 0.42), (0.44, 0.58), (0.72, 0.32)], color, width=stroke(size) + 1)


def draw_add(draw, size, color):
    line(draw, size, [(0.5, 0.2), (0.5, 0.8)], color)
    line(draw, size, [(0.2, 0.5), (0.8, 0.5)], color)


def draw_remove(draw, size, color):
    line(draw, size, [(0.2, 0.5), (0.8, 0.5)], color)


def draw_edit(draw, size, color):
    line(draw, size, [(0.72, 0.15), (0.85, 0.28), (0.38, 0.75), (0.18, 0.82), (0.25, 0.62)], color)
    line(draw, size, [(0.38, 0.75), (0.25, 0.62)], color)


def draw_quit(draw, size, color):
    line(draw, size, [(0.28, 0.28), (0.72, 0.72)], color)
    line(draw, size, [(0.72, 0.28), (0.28, 0.72)], color)


def draw_export(draw, size, color):
    line(draw, size, [(0.5, 0.15), (0.5, 0.62)], color)
    line(draw, size, [(0.34, 0.38), (0.5, 0.55), (0.66, 0.38)], color)
    poly(draw, size, [(0.18, 0.62), (0.82, 0.62), (0.82, 0.82), (0.18, 0.82)], color)


def draw_address_book(draw, size, color):
    poly(draw, size, [(0.22, 0.15), (0.78, 0.15), (0.78, 0.85), (0.22, 0.85)], color)
    line(draw, size, [(0.35, 0.35), (0.65, 0.35)], color)
    line(draw, size, [(0.35, 0.5), (0.58, 0.5)], color)


def draw_copy(draw, size, color):
    poly(draw, size, [(0.38, 0.22), (0.72, 0.22), (0.72, 0.62), (0.38, 0.62)], color)
    poly(draw, size, [(0.28, 0.32), (0.62, 0.32), (0.62, 0.72), (0.28, 0.72)], color)


def draw_paste(draw, size, color):
    poly(draw, size, [(0.32, 0.18), (0.68, 0.18), (0.68, 0.28), (0.78, 0.28), (0.78, 0.82), (0.22, 0.82), (0.22, 0.28), (0.32, 0.28)], color)


def draw_filesave(draw, size, color):
    poly(draw, size, [(0.18, 0.15), (0.82, 0.15), (0.82, 0.85), (0.18, 0.85)], color)
    poly(draw, size, [(0.32, 0.15), (0.5, 0.32), (0.68, 0.15)], color)
    line(draw, size, [(0.32, 0.55), (0.68, 0.55)], color)
    line(draw, size, [(0.32, 0.68), (0.58, 0.68)], color)


def draw_key(draw, size, color):
    circle(draw, size, 0.32, 0.32, 0.14, color)
    line(draw, size, [(0.42, 0.42), (0.82, 0.82)], color)
    line(draw, size, [(0.66, 0.66), (0.74, 0.58)], color)
    line(draw, size, [(0.74, 0.74), (0.82, 0.66)], color)


def draw_lock_closed(draw, size, color):
    poly(draw, size, [(0.22, 0.42), (0.78, 0.42), (0.78, 0.85), (0.22, 0.85)], color)
    arc(draw, size, 0.5, 0.42, 0.2, 180, 360, color)


def draw_lock_open(draw, size, color):
    poly(draw, size, [(0.22, 0.48), (0.78, 0.48), (0.78, 0.85), (0.22, 0.85)], color)
    arc(draw, size, 0.58, 0.42, 0.2, 200, 340, color)


def draw_qrcode(draw, size, color):
    poly(draw, size, [(0.15, 0.15), (0.42, 0.15), (0.42, 0.42), (0.15, 0.42)], color)
    poly(draw, size, [(0.58, 0.15), (0.85, 0.15), (0.85, 0.42), (0.58, 0.42)], color)
    poly(draw, size, [(0.15, 0.58), (0.42, 0.58), (0.42, 0.85), (0.15, 0.85)], color)
    line(draw, size, [(0.58, 0.58), (0.85, 0.58)], color)
    line(draw, size, [(0.58, 0.72), (0.72, 0.72)], color)
    line(draw, size, [(0.72, 0.58), (0.72, 0.85)], color)
    line(draw, size, [(0.58, 0.85), (0.85, 0.85)], color)


def draw_synced(draw, size, color):
    circle(draw, size, 0.5, 0.5, 0.34, color)
    line(draw, size, [(0.32, 0.52), (0.46, 0.66), (0.7, 0.34)], color, width=stroke(size) + 1)


def draw_connect(draw, size, color, bars):
    for i in range(4):
        h = 0.22 + i * 0.18
        x = 0.18 + i * 0.2
        c = color if i < bars else MUTED
        w = stroke(size)
        x0 = pad(size) + x * (size - 2 * pad(size))
        y1 = pad(size) + 0.82 * (size - 2 * pad(size))
        y0 = pad(size) + (0.82 - h) * (size - 2 * pad(size))
        x1 = x0 + 0.12 * (size - 2 * pad(size))
        draw.rectangle([x0, y0, x1, y1], fill=c)


def draw_clock(draw, size, color, fraction):
    circle(draw, size, 0.5, 0.5, 0.34, MUTED)
    arc(draw, size, 0.5, 0.5, 0.34, 90, 90 - 360 * fraction, color, width=stroke(size) + 1)


def draw_tx_confirmed(draw, size, color):
    circle(draw, size, 0.5, 0.5, 0.34, color)
    line(draw, size, [(0.34, 0.52), (0.46, 0.64), (0.68, 0.36)], color, width=stroke(size) + 1)


def draw_tx_pending(draw, size, color):
    circle(draw, size, 0.5, 0.5, 0.34, color)
    line(draw, size, [(0.38, 0.5), (0.62, 0.5)], color)


def draw_tx_conflict(draw, size, color):
    circle(draw, size, 0.5, 0.5, 0.34, color)
    line(draw, size, [(0.36, 0.36), (0.64, 0.64)], color)
    line(draw, size, [(0.64, 0.36), (0.36, 0.64)], color)


def draw_tx_mined(draw, size, color):
    poly(draw, size, [(0.5, 0.12), (0.78, 0.38), (0.68, 0.82), (0.32, 0.82), (0.22, 0.38)], color)


def draw_tx_input(draw, size, color):
    line(draw, size, [(0.2, 0.5), (0.55, 0.5)], color)
    line(draw, size, [(0.42, 0.35), (0.55, 0.5), (0.42, 0.65)], color)
    circle(draw, size, 0.72, 0.5, 0.12, color)


def draw_tx_output(draw, size, color):
    circle(draw, size, 0.28, 0.5, 0.12, color)
    line(draw, size, [(0.45, 0.5), (0.8, 0.5)], color)
    line(draw, size, [(0.67, 0.35), (0.8, 0.5), (0.67, 0.65)], color)


def draw_tx_inout(draw, size, color):
    draw_tx_input(draw, size, color)
    draw_tx_output(draw, size, color)


def draw_staking(draw, size, color, on):
    if on:
        line(draw, size, [(0.5, 0.78), (0.5, 0.38)], color)
        poly(draw, size, [(0.5, 0.15), (0.72, 0.42), (0.28, 0.42)], color)
    else:
        line(draw, size, [(0.5, 0.78), (0.5, 0.42)], color)
        poly(draw, size, [(0.5, 0.2), (0.72, 0.46), (0.28, 0.46)], color)
        line(draw, size, [(0.28, 0.72), (0.72, 0.72)], color)


def draw_app_icon(size):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    margin = round(size * 0.08)
    radius = round(size * 0.22)
    box = [margin, margin, size - margin, size - margin]
    for y in range(size):
        t = y / max(size - 1, 1)
        r = int(BRAND_DARK[0] * (1 - t) + BRAND[0] * t)
        g = int(BRAND_DARK[1] * (1 - t) + BRAND[1] * t)
        b = int(BRAND_DARK[2] * (1 - t) + BRAND[2] * t)
        draw.line([(box[0] + radius, y), (box[2] - radius, y)], fill=(r, g, b, 255))
    draw.rounded_rectangle(box, radius=radius, fill=None, outline=None)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(box, radius=radius, fill=255)
    grad = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    gdraw = ImageDraw.Draw(grad)
    for y in range(size):
        t = y / max(size - 1, 1)
        r = int(BRAND_DARK[0] * (1 - t) + BRAND[0] * t)
        g = int(BRAND_DARK[1] * (1 - t) + BRAND[1] * t)
        b = int(BRAND_DARK[2] * (1 - t) + BRAND[2] * t)
        gdraw.line([(0, y), (size, y)], fill=(r, g, b, 255))
    img = Image.composite(grad, img, mask)

    draw = ImageDraw.Draw(img)
    s = size
    w = max(3, round(size * 0.07))
    cx, cy = s * 0.5, s * 0.52
    rw, rh = s * 0.34, s * 0.24
    draw.rounded_rectangle(
        [cx - rw, cy - rh, cx + rw, cy + rh],
        radius=round(size * 0.06),
        outline=WHITE,
        width=w,
    )
    draw.arc(
        [cx - rw * 0.55, cy - rh * 2.1, cx + rw * 0.55, cy],
        start=200,
        end=340,
        fill=WHITE,
        width=w,
    )
    draw.ellipse(
        [cx - s * 0.07, cy + rh * 0.15, cx + s * 0.07, cy + rh * 0.55],
        fill=WHITE,
    )
    return img


def save_icon(path, image):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    image.save(path, "PNG", optimize=True, pnginfo=PngImagePlugin.PngInfo())


def main():
    ui_icons = {
        "send.png": draw_send,
        "receive.png": draw_receive,
        "overview.png": draw_overview,
        "configure.png": draw_options,
        "debugwindow.png": draw_debug,
        "add.png": draw_add,
        "remove.png": draw_remove,
        "edit.png": draw_edit,
        "quit.png": draw_quit,
        "export.png": draw_export,
        "address-book.png": draw_address_book,
        "editcopy.png": draw_copy,
        "editpaste.png": draw_paste,
        "filesave.png": draw_filesave,
        "key.png": draw_key,
        "lock_closed.png": draw_lock_closed,
        "lock_open.png": draw_lock_open,
        "qrcode.png": draw_qrcode,
        "synced.png": draw_synced,
        "transaction0.png": lambda d, s, c: draw_tx_pending(d, s, MUTED),
        "transaction2.png": draw_tx_confirmed,
        "transaction_conflicted.png": lambda d, s, c: draw_tx_conflict(d, s, RED),
        "tx_mined.png": draw_tx_mined,
        "tx_input.png": draw_tx_input,
        "tx_output.png": draw_tx_output,
        "tx_inout.png": draw_tx_inout,
        "staking_on.png": lambda d, s, c: draw_staking(d, s, BRAND, True),
        "staking_off.png": lambda d, s, c: draw_staking(d, s, MUTED, False),
    }

    for i in range(5):
        frac = (5 - i) / 5.0
        ui_icons[f"clock{i + 1}.png"] = lambda d, s, c, f=frac: draw_clock(d, s, AMBER, f)

    for i in range(5):
        ui_icons[f"connect{i}_16.png"] = lambda d, s, c, b=i: draw_connect(d, s, BRAND, b)

    for name, fn in ui_icons.items():
        save_icon(os.path.join(ICON_DIR, name), render(fn, 48))

    app_sizes = {
        "infinitericks-16.png": 16,
        "infinitericks-32.png": 32,
        "infinitericks-48.png": 48,
        "infinitericks-80.png": 80,
        "infinitericks-128.png": 128,
        "infinitericks.png": 256,
        "infinitericks_testnet.png": 256,
        "bitcoin_testnet.png": 256,
    }
    app_images = []
    for name, sz in app_sizes.items():
        img = draw_app_icon(sz)
        save_icon(os.path.join(ICON_DIR, name), img)
        if sz in (16, 32, 48, 256):
            app_images.append(img.resize((sz, sz), Image.LANCZOS))

    ico_path = os.path.join(ICON_DIR, "infinitericks.ico")
    base = draw_app_icon(256)
    base.save(
        ico_path,
        format="ICO",
        sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
    )

    android_sizes = {
        "drawable-ldpi": 36,
        "drawable-mdpi": 48,
        "drawable-hdpi": 72,
        "drawable-xhdpi": 96,
        "drawable-xxhdpi": 144,
        "drawable-xxxhdpi": 192,
    }
    launcher = Image.open(ANDROID_LAUNCHER_SOURCE).convert("RGBA")
    for folder, sz in android_sizes.items():
        save_icon(
            os.path.join(ANDROID_RES, folder, "infinitericks.png"),
            launcher.resize((sz, sz), Image.LANCZOS),
        )

    print(f"Generated icons in {ICON_DIR} and {ANDROID_RES}")

    script_dir = os.path.dirname(os.path.abspath(__file__))
    if script_dir not in sys.path:
        sys.path.insert(0, script_dir)
    from process_project_images import install_custom_toolbar_icons

    for path in install_custom_toolbar_icons():
        print(f"Installed custom icon: {path}")


if __name__ == "__main__":
    main()
