#!/usr/bin/env python3
"""Generates the BetterGlide app icon (Liquid Glass style) into the asset catalog.

Usage: python3 scripts/make-icon.py   (requires Pillow)
Design: macOS icon grid (824 pt squircle on a 1024 canvas), neutral gray glass body (like macOS 26 clear/gray icons),
three frosted "window" panes in a row with the middle one in front, and a soft top sheen.
"""
import json
import os
from PIL import Image, ImageDraw, ImageFilter, ImageChops

S = 2048  # supersampled canvas (2× of 1024)
OUT = os.path.join(os.path.dirname(__file__), "..", "BetterGlide", "Resources", "Assets.xcassets", "AppIcon.appiconset")


def rounded_mask(size, box, radius):
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(box, radius=radius, fill=255)
    return mask


def vertical_gradient(size, top, bottom):
    w, h = size
    grad = Image.new("RGBA", (1, h))
    for y in range(h):
        t = y / (h - 1)
        grad.putpixel((0, y), tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(4)))
    return grad.resize((w, h))


def frosted_pane(canvas, box, radius, tint_alpha, rim_alpha):
    """Frosted glass: blur what is underneath, tint it white, add a bright rim and window dots."""
    size = canvas.size
    x0, y0, x1, y1 = box
    blurred = canvas.filter(ImageFilter.GaussianBlur(46))
    tint = vertical_gradient(size, (255, 255, 255, tint_alpha + 35), (255, 255, 255, max(tint_alpha - 25, 0)))
    glass = Image.alpha_composite(blurred, tint)
    out = canvas.copy()
    out.paste(glass, (0, 0), rounded_mask(size, box, radius))
    d = ImageDraw.Draw(out)
    d.rounded_rectangle(box, radius=radius, outline=(255, 255, 255, rim_alpha), width=9)
    r = (y1 - y0) * 0.035
    cy = y0 + (y1 - y0) * 0.09
    for i in range(3):
        cx = x0 + (x1 - x0) * 0.11 + i * r * 3.2
        d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(120, 122, 132, 220))
    return out


def shadow(size, box, radius, alpha, blur, offset):
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    x0, y0, x1, y1 = box
    ImageDraw.Draw(layer).rounded_rectangle((x0, y0 + offset, x1, y1 + offset), radius=radius, fill=(20, 20, 30, alpha))
    return layer.filter(ImageFilter.GaussianBlur(blur))


def make_master():
    size = (S, S)
    canvas = Image.new("RGBA", size, (0, 0, 0, 0))
    m = 200                      # 100 px margin at 1024
    body_box = (m, m, S - m, S - m)
    body_radius = 370            # ≈185 px at 1024, macOS squircle-ish

    canvas = Image.alpha_composite(canvas, shadow(size, body_box, body_radius, 120, 40, 24))

    body = vertical_gradient(size, (238, 239, 243, 255), (150, 153, 162, 255))
    glow = Image.new("RGBA", size, (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse((m - 200, m - 300, S * 0.75, S * 0.62), fill=(255, 255, 255, 170))
    body = Image.alpha_composite(body, glow.filter(ImageFilter.GaussianBlur(180)))
    glow2 = Image.new("RGBA", size, (0, 0, 0, 0))
    ImageDraw.Draw(glow2).ellipse((S * 0.5, S * 0.55, S + 200, S + 300), fill=(105, 110, 125, 110))
    body = Image.alpha_composite(body, glow2.filter(ImageFilter.GaussianBlur(200)))
    mask = rounded_mask(size, body_box, body_radius)
    canvas.paste(body, (0, 0), mask)

    # Three window panes: side panes behind, centre pane in front.
    cy0, cy1 = S * 0.33, S * 0.72
    side_w, mid_w = S * 0.25, S * 0.36
    left = (S * 0.17, cy0 + 70, S * 0.17 + side_w, cy1 - 30)
    right = (S * 0.83 - side_w, cy0 + 70, S * 0.83, cy1 - 30)
    mid = ((S - mid_w) / 2, cy0, (S + mid_w) / 2, cy1)
    for box in (left, right):
        canvas = Image.alpha_composite(canvas, shadow(size, box, 60, 70, 24, 14))
        canvas = frosted_pane(canvas, box, 60, 100, 220)
    canvas = Image.alpha_composite(canvas, shadow(size, mid, 70, 130, 34, 22))
    canvas = frosted_pane(canvas, mid, 70, 165, 255)

    # Glide arrows under the panes.
    d = ImageDraw.Draw(canvas)
    ay = S * 0.80
    for direction in (-1, 1):
        cx = S / 2 + direction * S * 0.09
        tip = cx + direction * S * 0.05
        d.line([(cx, ay - 55), (tip, ay), (cx, ay + 55)], fill=(72, 74, 84, 235), width=34, joint="curve")

    # Top sheen (the "liquid" highlight) clipped to the body.
    w, h = size
    fade = Image.new("L", (1, h))
    for y in range(h):
        t = (y - m) / (S * 0.5 - m)
        fade.putpixel((0, y), int(70 * max(0.0, 1 - t) ** 2) if y >= m else 0)
    sheen_mask = ImageChops.multiply(mask, fade.resize(size))
    canvas = Image.alpha_composite(canvas, Image.composite(Image.new("RGBA", size, (255, 255, 255, 255)),
                                                           Image.new("RGBA", size, (0, 0, 0, 0)), sheen_mask))
    # Thin bright rim around the body.
    rim = Image.new("RGBA", size, (0, 0, 0, 0))
    ImageDraw.Draw(rim).rounded_rectangle(body_box, radius=body_radius, outline=(255, 255, 255, 160), width=8)
    canvas = Image.alpha_composite(canvas, rim)
    return canvas.resize((1024, 1024), Image.LANCZOS)


def main():
    os.makedirs(OUT, exist_ok=True)
    master = make_master()
    images = []
    for points in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            px = points * scale
            name = f"icon_{points}x{points}{'@2x' if scale == 2 else ''}.png"
            master.resize((px, px), Image.LANCZOS).save(os.path.join(OUT, name))
            images.append({"idiom": "mac", "size": f"{points}x{points}", "scale": f"{scale}x", "filename": name})
    with open(os.path.join(OUT, "Contents.json"), "w") as f:
        json.dump({"images": images, "info": {"author": "xcode", "version": 1}}, f, indent=2)
    with open(os.path.join(OUT, "..", "Contents.json"), "w") as f:
        json.dump({"info": {"author": "xcode", "version": 1}}, f, indent=2)


if __name__ == "__main__":
    main()
