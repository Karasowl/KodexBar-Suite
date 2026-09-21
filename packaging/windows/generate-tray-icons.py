#!/usr/bin/env python3
"""Generate the Windows tray status PNGs from the shared tray icon design.

Pure standard library: renders the kodexbar-tray SVG look (rounded purple
badge, white check, status dot) at 4x supersampling and writes 32x32 RGBA
PNGs next to packages/ai-cli-control/icons/kodexbar-tray-*.svg so the
Windows tray and the PyInstaller build never need an SVG rasterizer.
"""

from __future__ import annotations

import math
from pathlib import Path
import struct
import sys
import zlib


SIZE = 32
SCALE = 4
PLANE = SIZE * SCALE

# App icon sizes inside kodexbar.ico. Windows picks the closest entry per
# view, so a single 32px image shows as a blank placeholder in the Start
# menu and other large-icon surfaces.
ICO_SIZES = (16, 32, 48, 256)

STATUS_COLORS = {
    "ok": (0x35, 0xD0, 0x7F),
    "warning": (0xF5, 0xA6, 0x23),
    "critical": (0xFF, 0x5C, 0x5C),
}
GRADIENT_START = (0x8F, 0x7B, 0xFF)
GRADIENT_END = (0x5A, 0x45, 0xF0)
WHITE = (0xFF, 0xFF, 0xFF)


def clamp(value: float, low: float = 0.0, high: float = 1.0) -> float:
    return max(low, min(high, value))


def sd_round_rect(px: float, py: float, cx: float, cy: float, hw: float, hh: float, r: float) -> float:
    qx = abs(px - cx) - (hw - r)
    qy = abs(py - cy) - (hh - r)
    outside = math.hypot(max(qx, 0.0), max(qy, 0.0))
    return outside + min(max(qx, qy), 0.0) - r


def sd_capsule(px: float, py: float, ax: float, ay: float, bx: float, by: float, r: float) -> float:
    abx, aby = bx - ax, by - ay
    apx, apy = px - ax, py - ay
    length_sq = abx * abx + aby * aby
    t = 0.0 if length_sq == 0 else clamp((apx * abx + apy * aby) / length_sq)
    return math.hypot(apx - t * abx, apy - t * aby) - r


def sd_circle(px: float, py: float, cx: float, cy: float, r: float) -> float:
    return math.hypot(px - cx, py - cy) - r


def blend(base: tuple[float, float, float, float], color: tuple[int, int, int], distance: float, scale: float = SCALE) -> tuple[float, float, float, float]:
    alpha = clamp(0.5 - distance / scale)
    if alpha <= 0:
        return base
    out_a = alpha + base[3] * (1 - alpha)
    if out_a <= 0:
        return (0.0, 0.0, 0.0, 0.0)
    channels = []
    for index in range(3):
        front = color[index] * alpha
        behind = base[index] * base[3] * (1 - alpha)
        channels.append((front + behind) / out_a)
    return (channels[0], channels[1], channels[2], out_a)


def capsule_points(cx: float, cy: float, degrees: float, half_length: float) -> tuple[float, float, float, float]:
    rad = math.radians(degrees)
    dx, dy = math.cos(rad) * half_length, math.sin(rad) * half_length
    return cx - dx, cy - dy, cx + dx, cy + dy


def render(status: str, size: int = SIZE, scale: int = SCALE) -> list[list[tuple[int, int, int, int]]]:
    dot = STATUS_COLORS[status]
    plane = size * scale
    pixels: list[list[tuple[int, int, int, int]]] = []
    unit = plane / 128
    check1 = capsule_points(60 * unit, 56 * unit, -38, 18 * unit)
    check2 = capsule_points(78 * unit, 74 * unit, 38, 18 * unit)
    for y in range(size):
        row = []
        for x in range(size):
            # Subsamples per pixel for anti-aliasing.
            sample: tuple[float, float, float, float] = (0.0, 0.0, 0.0, 0.0)
            for sy in range(scale):
                for sx in range(scale):
                    px = x * scale + sx + 0.5
                    py = y * scale + sy + 0.5
                    # Gradient badge in the SVG's diagonal direction.
                    t = clamp((px + py) / (2 * plane))
                    badge = tuple(
                        GRADIENT_START[c] + (GRADIENT_END[c] - GRADIENT_START[c]) * t for c in range(3)
                    )
                    sub: tuple[float, float, float, float] = (0.0, 0.0, 0.0, 0.0)
                    sub = blend(sub, badge, sd_round_rect(px, py, plane / 2, plane / 2, plane / 2, plane / 2, 30 * unit), scale)
                    # The three small bars keep the SVG layout: colored first bar.
                    sub = blend(sub, dot, sd_round_rect(px, py, 45 * unit, 38 * unit, 9 * unit, 10 * unit, 6 * unit), scale)
                    sub = blend(sub, WHITE, sd_round_rect(px, py, 45 * unit, 64 * unit, 9 * unit, 10 * unit, 6 * unit), scale)
                    sub = blend(sub, WHITE, sd_round_rect(px, py, 45 * unit, 90 * unit, 9 * unit, 10 * unit, 6 * unit), scale)
                    sub = blend(sub, WHITE, sd_capsule(px, py, *check1, 8 * unit), scale)
                    sub = blend(sub, WHITE, sd_capsule(px, py, *check2, 8 * unit), scale)
                    sub = blend(sub, WHITE, sd_circle(px, py, 102 * unit, 102 * unit, 18 * unit), scale)
                    sub = blend(sub, dot, sd_circle(px, py, 102 * unit, 102 * unit, 12 * unit), scale)
                    sample = tuple(sample[i] + sub[i] for i in range(4))  # type: ignore[assignment]
            count = scale * scale
            row.append(tuple(round(channel / count) for channel in sample))
        pixels.append(row)
    return pixels


def encode_png(pixels: list[list[tuple[int, int, int, int]]], size: int) -> bytes:
    raw = bytearray()
    for row in pixels:
        raw.append(0)
        for r, g, b, a in row:
            raw.extend((r, g, b, a))
    compressed = zlib.compress(bytes(raw), 9)
    chunk = lambda kind, data: struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    header = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", compressed)
        + chunk(b"IEND", b"")
    )


def write_png(path: Path, pixels: list[list[tuple[int, int, int, int]]], size: int = SIZE) -> None:
    path.write_bytes(encode_png(pixels, size))


def write_ico(path: Path, images: list[tuple[int, bytes]]) -> None:
    """Pack several PNG-compressed entries (Vista+) so every Windows surface finds its size."""
    directory = struct.pack("<HHH", 0, 1, len(images))
    offset = 6 + 16 * len(images)
    blob = bytearray()
    for size, png_bytes in images:
        side = 0 if size >= 256 else size
        directory += struct.pack("<BBBBHHII", side, side, 0, 0, 1, 32, len(png_bytes), offset)
        offset += len(png_bytes)
    for _, png_bytes in images:
        blob.extend(png_bytes)
    path.write_bytes(directory + bytes(blob))


def main() -> int:
    target = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[2] / "packages" / "ai-cli-control" / "icons" / "windows"
    target.mkdir(parents=True, exist_ok=True)
    for status in STATUS_COLORS:
        pixels = render(status)
        write_png(target / f"kodexbar-tray-{status}.png", pixels)
        print(f"wrote {target / f'kodexbar-tray-{status}.png'}")
    images = []
    for size in ICO_SIZES:
        scale = 4 if size <= 48 else 2
        images.append((size, encode_png(render("ok", size, scale), size)))
    write_ico(target / "kodexbar.ico", images)
    print(f"wrote {target / 'kodexbar.ico'} with sizes {[size for size, _ in images]}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
