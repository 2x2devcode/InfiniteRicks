#!/usr/bin/env python3
"""Strip metadata from project images, Android launcher icons, and white toolbar variants."""

import os
import sys
from PIL import Image, PngImagePlugin

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
IMAGE_EXTS = {".png", ".jpg", ".jpeg", ".ico", ".icns", ".mng", ".bmp", ".gif", ".webp"}

SKIP_DIRS = {
    ".git",
    "node_modules",
    "build",
    "build-mingw-x86_64",
    "release",
    "windows-build",
    "android-build",
    "arm64-v8a",
}


def should_process(path):
    parts = set(os.path.normpath(path).split(os.sep))
    return not parts.intersection(SKIP_DIRS)


def iter_images(root):
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for name in filenames:
            ext = os.path.splitext(name)[1].lower()
            if ext in IMAGE_EXTS:
                yield os.path.join(dirpath, name)


def strip_image(path):
    ext = os.path.splitext(path)[1].lower()
    if ext == ".mng":
        return False

    img = Image.open(path)
    if getattr(img, "is_animated", False) and getattr(img, "n_frames", 1) > 1:
        frames = []
        for frame in range(img.n_frames):
            img.seek(frame)
            frames.append(clean_image(img.copy()))
        frames[0].save(
            path,
            save_all=True,
            append_images=frames[1:],
            duration=img.info.get("duration", 100),
            loop=img.info.get("loop", 0),
            optimize=True,
        )
        return True

    clean = clean_image(img)
    save_kwargs = {"optimize": True}
    if ext == ".png":
        save_kwargs["pnginfo"] = PngImagePlugin.PngInfo()
    if ext in {".jpg", ".jpeg"}:
        save_kwargs["quality"] = 95
        save_kwargs["subsampling"] = 0

    clean.save(path, **save_kwargs)
    return True


def clean_image(img):
    if img.mode in ("P", "PA"):
        img = img.convert("RGBA")
    elif img.mode == "LA":
        img = img.convert("RGBA")
    elif img.mode == "RGB":
        pass
    elif img.mode != "RGBA":
        img = img.convert("RGBA")

    out = Image.new(img.mode, img.size)
    out.paste(img)
    return out


def to_white_variant(img):
    base = clean_image(img)
    if base.mode != "RGBA":
        base = base.convert("RGBA")
    white = Image.new("RGBA", base.size, (255, 255, 255, 0))
    r, g, b, a = base.split()
    white.putalpha(a)
    return white


def save_white_copy(src_path, dst_path):
    img = Image.open(src_path)
    white = to_white_variant(img)
    white.save(dst_path, optimize=True, pnginfo=PngImagePlugin.PngInfo())


ANDROID_LAUNCHER_SIZES = {
    "drawable-ldpi": 36,
    "drawable-mdpi": 48,
    "drawable-hdpi": 72,
    "drawable-xhdpi": 96,
    "drawable-xxhdpi": 144,
    "drawable-xxxhdpi": 192,
}


def regenerate_android_launcher_icons():
    splash = os.path.join(REPO, "src", "qt", "res", "images", "splash.png")
    android_res = os.path.join(REPO, "src", "qt", "android", "res")
    if not os.path.isfile(splash) or not os.path.isdir(android_res):
        return 0

    launcher = clean_image(Image.open(splash))
    updated = 0
    for folder, size in ANDROID_LAUNCHER_SIZES.items():
        out_dir = os.path.join(android_res, folder)
        if not os.path.isdir(out_dir):
            continue
        out_path = os.path.join(out_dir, "infinitericks.png")
        icon = launcher.resize((size, size), Image.LANCZOS)
        icon.save(out_path, optimize=True, pnginfo=PngImagePlugin.PngInfo())
        updated += 1
    return updated


def install_custom_toolbar_icons():
    """Install user-provided toolbar icons when source masters exist."""
    custom_dir = os.path.join(REPO, "share", "qt", "img", "custom")
    icon_dir = os.path.join(REPO, "src", "qt", "res", "icons")
    installed = []

    for name in ("history.png", "address-book1.png"):
        src = os.path.join(custom_dir, name)
        dst = os.path.join(icon_dir, name)
        if not os.path.isfile(src):
            continue
        img = Image.open(src).convert("RGBA")
        w, h = img.size
        side = min(w, h)
        left = (w - side) // 2
        top = (h - side) // 2
        img = img.crop((left, top, left + side, top + side))
        img = img.resize((48, 48), Image.LANCZOS)
        img.save(dst, optimize=True, pnginfo=PngImagePlugin.PngInfo())
        installed.append(dst)

    return installed


def main():
    os.chdir(REPO)

    installed = install_custom_toolbar_icons()
    for path in installed:
        print(f"Installed custom icon: {path}")

    android_icons = regenerate_android_launcher_icons()
    if android_icons:
        print(f"Updated {android_icons} Android launcher icon(s)")

    processed = 0
    for path in sorted(iter_images(REPO)):
        if not should_process(path):
            continue
        try:
            if strip_image(path):
                processed += 1
        except Exception as exc:
            print(f"WARN: could not process {path}: {exc}", file=sys.stderr)

    print(f"Stripped metadata from {processed} image(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
