"""生成混元武僧技能点面板的 UI 素材（BAM V1 / BAMC）。

产出：
  c4Monk/bam/c4mkf1b.bam .. c4mkf7b.bam   拳法七条线图标（32x32）
  c4Monk/bam/c4mkm1b.bam .. c4mkm4b.bam   心法四条图标（32x32）
  c4Monk/bam/c4mkbdb.bam                  高等混元身法（金星）
  c4Monk/bam/c4mkspbg.bam                 面板底板（820x344，全不透明）

用法：python tools/make_ui_icons.py [--preview out.png]
只依赖 Pillow。生成后用 ni 无法校验 MENU，得进游戏看。
"""
import math
import os
import struct
import sys
import zlib

from PIL import Image, ImageChops, ImageDraw, ImageFilter

W = H = 32
SS = 8  # 超采样倍数

PANEL_W, PANEL_H = 820, 344

BASE = (20, 21, 26)      # 盘面底色
INK = (10, 10, 13)       # 图形描边


def mix(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def shade(c, t):
    """t<1 变暗，t>1 朝白提亮。"""
    if t <= 1:
        return tuple(int(round(v * t)) for v in c)
    return mix(c, (255, 255, 255), t - 1)


def disc(img, rim, inner=BASE):
    d = ImageDraw.Draw(img)
    d.ellipse([1.2 * SS, 1.2 * SS, 30.8 * SS, 30.8 * SS], fill=shade(rim, 0.55) + (255,))
    d.ellipse([2.2 * SS, 2.2 * SS, 29.8 * SS, 29.8 * SS], fill=rim + (255,))
    d.ellipse([3.2 * SS, 3.2 * SS, 28.8 * SS, 28.8 * SS], fill=mix(inner, rim, 0.16) + (255,))
    d.ellipse([4.0 * SS, 4.0 * SS, 28.0 * SS, 28.0 * SS], fill=inner + (255,))


def mask(fn):
    m = Image.new("L", (W * SS, H * SS), 0)
    fn(ImageDraw.Draw(m), SS)
    return m


def stamp(img, m, color, dilate=SS):
    """先按 dilate 画一圈深色描边，再填主色。"""
    ring = m.filter(ImageFilter.MaxFilter(dilate * 2 + 1)) if dilate else m
    img.paste(INK + (255,), (0, 0), ring)
    img.paste(color + (255,), (0, 0), m)


def _pts(points, s):
    return [(x * s, y * s) for x, y in points]


def _almond(cx, cy, hw, hh, n=20):
    up = [(cx - hw + 2 * hw * t / n, cy - hh * math.sin(math.pi * t / n)) for t in range(n + 1)]
    lo = [(cx + hw - 2 * hw * t / n, cy + hh * math.sin(math.pi * t / n)) for t in range(n + 1)]
    return up + lo


# ---------------- 拳法 ----------------

def snowflake(d, s):
    cx = cy = 16 * s
    for k in range(3):
        a = math.radians(90 + k * 60)
        dx, dy = math.cos(a), -math.sin(a)
        d.line([cx - dx * 10 * s, cy - dy * 10 * s, cx + dx * 10 * s, cy + dy * 10 * s],
               fill=255, width=int(2.0 * s))
        for side in (-1, 1):
            bx, by = cx + dx * 6.2 * s, cy + dy * 6.2 * s
            for t in (-40, 40):
                aa = a + math.radians(90 + t) * side
                d.line([bx, by, bx + math.cos(aa) * 3.6 * s, by - math.sin(aa) * 3.6 * s],
                       fill=255, width=int(1.8 * s))


def flame(d, s):
    d.polygon(_pts([(16.6, 2.8), (20.4, 9.2), (23.0, 14.6), (22.4, 20.4), (18.8, 26.6),
                    (13.2, 26.8), (9.4, 22.2), (9.0, 16.0), (12.4, 9.6), (13.8, 14.6),
                    (15.4, 9.0)], s), fill=255)


def bolt(d, s):
    d.polygon(_pts([(19.6, 2.8), (9.6, 17.4), (15.2, 17.4), (12.4, 29.2),
                    (23.2, 13.8), (17.2, 13.8), (20.6, 2.8)], s), fill=255)


def skull(d, s):
    d.ellipse([7.0 * s, 4.0 * s, 25.0 * s, 21.5 * s], fill=255)
    d.rounded_rectangle([11.0 * s, 17.5 * s, 21.0 * s, 26.0 * s],
                        radius=2.0 * s, fill=255)


def sword(d, s):
    d.polygon(_pts([(16, 1.8), (18.4, 5.4), (18.4, 18.6), (13.6, 18.6), (13.6, 5.4)], s), fill=255)
    d.rectangle([9.0 * s, 18.6 * s, 23.0 * s, 21.4 * s], fill=255)
    d.rectangle([14.8 * s, 21.4 * s, 17.2 * s, 27.2 * s], fill=255)
    d.ellipse([14.0 * s, 26.0 * s, 18.0 * s, 29.8 * s], fill=255)


def heart(d, s):
    d.polygon(_pts([(16, 27.0), (6.6, 17.6), (5.8, 11.8), (9.2, 8.0), (13.0, 8.4),
                    (16, 11.4), (19.0, 8.4), (22.8, 8.0), (26.2, 11.8), (25.4, 17.6)], s),
              fill=255)


def arrow(d, s):
    # 横穿的箭：箭杆从左侧穿入，箭头露在心形右侧
    d.rectangle([1.6 * s, 14.2 * s, 25.4 * s, 16.8 * s], fill=255)
    d.polygon(_pts([(24.4, 11.4), (30.4, 15.5), (24.4, 19.6)], s), fill=255)
    d.polygon(_pts([(2.2, 12.4), (5.4, 15.5), (2.2, 18.6)], s), fill=255)


def gale(d, s):
    pts = []
    step = 0.18
    t = 0.0
    while t < 2.35 * math.pi:
        r = 11.0 - 8.2 * (t / (2.35 * math.pi))
        pts.append((16 + math.cos(t) * r, 16 + math.sin(t) * r))
        t += step
    d.line([(x * s, y * s) for x, y in pts], fill=255, width=int(2.1 * s), joint="curve")
    d.ellipse([14.6 * s, 14.6 * s, 17.4 * s, 17.4 * s], fill=255)


# ---------------- 身法 / 心法 ----------------

def star(d, s):
    pts = []
    for k in range(10):
        r = 10.6 if k % 2 == 0 else 4.7
        a = math.radians(-90 + k * 36)
        pts.append((16 + math.cos(a) * r, 16.4 + math.sin(a) * r))
    d.polygon(_pts(pts, s), fill=255)


def hood(d, s):
    """凌波微步：发的是「混元兜帽」（c4mkhelm.itm，图标 IHELM29）—— 尖顶兜帽，画褶皱不挖脸洞。"""
    d.polygon(_pts([(16, 2.2), (20.6, 5.4), (23.4, 11.2), (24.6, 17.8), (27.8, 24.4),
                    (22.2, 23.0), (16, 28.0), (9.8, 23.0), (4.2, 24.4), (7.4, 17.8),
                    (8.6, 11.2), (11.4, 5.4)], s), fill=255)
    # 布褶：从顶上分下来两道，收在下摆
    d.line([16.2 * s, 6.2 * s, 13.4 * s, 24.6 * s], fill=0, width=int(1.2 * s))
    d.line([16.2 * s, 6.2 * s, 18.8 * s, 24.6 * s], fill=0, width=int(1.2 * s))


def wind(d, s):
    # 两道弧形风纹：轻快、飘（不抢兜帽的形）
    d.arc([1.2 * s, 13.0 * s, 12.4 * s, 24.4 * s], start=205, end=285, fill=255,
          width=int(1.5 * s))
    d.arc([2.6 * s, 18.0 * s, 10.4 * s, 27.0 * s], start=210, end=280, fill=255,
          width=int(1.3 * s))


def cloud(d, s):
    """仙风云体术：云团。"""
    d.ellipse([5.6 * s, 15.0 * s, 15.2 * s, 24.6 * s], fill=255)
    d.ellipse([11.2 * s, 10.6 * s, 21.2 * s, 23.0 * s], fill=255)
    d.ellipse([17.2 * s, 14.6 * s, 26.6 * s, 24.2 * s], fill=255)
    d.rectangle([9.0 * s, 19.2 * s, 23.2 * s, 24.4 * s], fill=255)


def lotus_center(d, s):
    d.polygon(_pts([(16, 5.6), (20.2, 13.4), (16, 20.4), (11.8, 13.4)], s), fill=255)


def lotus_left(d, s):
    d.polygon(_pts([(15.0, 12.6), (9.6, 7.4), (4.8, 13.6), (10.8, 19.4)], s), fill=255)


def lotus_right(d, s):
    d.polygon(_pts([(17.0, 12.6), (22.4, 7.4), (27.2, 13.6), (21.2, 19.4)], s), fill=255)


def lotus_base(d, s):
    d.polygon(_pts([(7.0, 19.0), (25.0, 19.0), (21.4, 25.8), (10.6, 25.8)], s), fill=255)


def eye_ring(d, s):
    d.polygon(_pts(_almond(16, 16, 12.2, 8.6), s), fill=255)
    d.polygon(_pts(_almond(16, 16, 8.6, 6.0), s), fill=0)


def eye_pupil(d, s):
    d.ellipse([12.4 * s, 12.4 * s, 19.6 * s, 19.6 * s], fill=255)


ICONS = [
    # resref, 主色, 盘边色, 形状（可多段，逐段描边）, 内层高光
    ("c4mkf1b", (150, 232, 255), (58, 132, 178), [snowflake], None),   # 冰魄
    ("c4mkf2b", (255, 158, 58), (168, 62, 20), [flame], "flame"),      # 烈火
    ("c4mkf3b", (255, 226, 92), (162, 132, 18), [bolt], "bolt"),       # 雷音
    ("c4mkf4b", (154, 224, 110), (66, 124, 46), [skull], "skull"),     # 蚀骨
    ("c4mkf5b", (216, 226, 240), (86, 104, 132), [sword], "sword"),    # 斩铁
    ("c4mkf6b", (255, 92, 112), (146, 28, 48), [heart, arrow], "arrow"),  # 穿心
    ("c4mkf7b", (188, 255, 228), (52, 142, 112), [gale], None),        # 疾风
    ("c4mkbdb", (255, 214, 120), (150, 106, 30), [star], None),        # 高等混元身法
    ("c4mkm1b", (196, 186, 255), (78, 66, 140),
     [hood, wind], None),                                              # 凌波微步：混元兜帽 + 风纹
    ("c4mkm2b", (150, 214, 255), (52, 108, 156), [cloud], None),       # 仙风云体术：豁免 / 魔抗
    ("c4mkm3b", (128, 232, 172), (44, 128, 86),
     [lotus_left, lotus_right, lotus_center, lotus_base], None),        # 五气朝元：回血 / 生命上限
    ("c4mkm4b", (228, 146, 246), (118, 56, 132), [eye_ring, eye_pupil], None),  # 凝神归元：免疫心智
]


def inner_detail(img, kind, color):
    """内层亮部：让符号不是一整块。"""
    d = ImageDraw.Draw(img)
    s = SS
    hi = mix(color, (255, 255, 255), 0.55)
    if kind == "flame":
        d.polygon([(16 * s, 12.4 * s), (19.4 * s, 18.4 * s), (16 * s, 25.2 * s),
                   (12.8 * s, 18.8 * s)], fill=hi + (255,))
    elif kind == "bolt":
        d.polygon([(17.4 * s, 6.2 * s), (13.2 * s, 15.4 * s), (16.2 * s, 15.4 * s),
                   (14.6 * s, 22.4 * s), (18.6 * s, 12.6 * s), (15.8 * s, 12.6 * s)],
                  fill=hi + (255,))
    elif kind == "skull":
        for cx in (12.2, 19.8):
            d.ellipse([(cx - 2.4) * s, 10.2 * s, (cx + 2.4) * s, 15.0 * s],
                      fill=BASE + (255,))
        d.polygon([(16 * s, 16.6 * s), (18.0 * s, 19.6 * s), (14.0 * s, 19.6 * s)],
                  fill=BASE + (255,))
        for x in (12.8, 16.0, 19.2):
            d.line([x * s, 20.4 * s, x * s, 25.2 * s], fill=BASE + (255,), width=int(1.1 * s))
    elif kind == "sword":
        d.rectangle([15.2 * s, 3.4 * s, 16.8 * s, 18.2 * s], fill=hi + (255,))


TILT = {"c4mkm1b": -10}   # 头盔斜一点，看着在"走"，不是摆在那儿


def make_icon(color, rim, parts, detail):
    img = Image.new("RGBA", (W * SS, H * SS), (0, 0, 0, 0))
    disc(img, rim)
    if detail == "arrow":
        # 心 + 箭作为一个轮廓描边，箭身再单独提亮，看起来是"射穿"
        union = Image.new("L", (W * SS, H * SS), 0)
        for fn in parts:
            union = ImageChops.lighter(union, mask(fn))
        stamp(img, union, color)
        img.paste(mix(color, (255, 255, 255), 0.86) + (255,), (0, 0), mask(arrow))
    else:
        for fn in parts:
            stamp(img, mask(fn), color)
        if detail:
            inner_detail(img, detail, color)
    return img.resize((W, H), Image.LANCZOS)


def make_panel(w_px, h_px):
    img = Image.new("RGBA", (w_px, h_px), (0, 0, 0, 255))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, w_px - 1, h_px - 1], fill=(22, 20, 18, 255))
    d.rectangle([0, 0, w_px - 1, h_px - 1], outline=(96, 78, 54, 255), width=2)
    d.rectangle([4, 4, w_px - 5, 46], fill=(32, 28, 23, 255))
    d.line([6, 46, w_px - 7, 46], fill=(96, 78, 54, 255), width=1)
    return img


def quantize(img):
    """RGBA -> 调色板索引 + 256 色 RGBQUAD 调色板（索引 0 = 透明）。"""
    rgba = img.convert("RGBA")
    alpha = rgba.getchannel("A").point(lambda v: 255 if v >= 110 else 0)
    rgb = rgba.convert("RGB")
    q = rgb.quantize(colors=255, method=Image.MEDIANCUT, dither=Image.NONE)
    qpal = q.getpalette()  # 768 bytes（PIL 偶尔只返回用到的部分）
    if len(qpal) < 768:
        qpal = qpal + [0] * (768 - len(qpal))
    idx = list(q.getdata())
    amask = list(alpha.getdata())
    out = [0 if amask[i] == 0 else idx[i] + 1 for i in range(len(idx))]
    pal = [(0, 0, 0)]
    for i in range(255):
        pal.append((qpal[i * 3], qpal[i * 3 + 1], qpal[i * 3 + 2]))
    return out, pal


def write_bam(path, img):
    w, h = img.size
    px, pal = quantize(img)
    frame_off = 0x18
    cycle_off = frame_off + 12
    pal_off = cycle_off + 4
    lut_off = pal_off + 1024
    data_off = lut_off + 2

    buf = bytearray()
    buf += b"BAM " + b"V1  "
    buf += struct.pack("<HBB", 1, 1, 0)          # frames, cycles, transparent index
    buf += struct.pack("<III", frame_off, pal_off, lut_off)
    buf += struct.pack("<HHhhI", w, h, w // 2, h // 2, 0x80000000 | data_off)
    buf += struct.pack("<HH", 1, 0)              # 1 cycle, starts at LUT[0]
    for r, g, b in pal:
        buf += bytes((b, g, r, 0 if (r, g, b) == (0, 0, 0) else 255))
    buf += b"\x00\x00"                            # LUT[0] = frame 0
    buf += bytes(px)

    body = zlib.compress(bytes(buf), 9)
    blob = b"BAMC" + b"V1  " + struct.pack("<I", len(buf)) + body
    with open(path, "wb") as f:
        f.write(blob)
    return len(blob), len(buf)


def main():
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out_dir = os.path.join(here, "c4Monk", "bam")
    preview = None
    if "--preview" in sys.argv:
        preview = sys.argv[sys.argv.index("--preview") + 1]

    sheet = Image.new("RGBA", (40 * len(ICONS) + 8, 40), (46, 44, 42, 255))
    for i, (resref, color, rim, parts, detail) in enumerate(ICONS):
        img = make_icon(color, rim, parts, detail)
        if resref in TILT:
            img = img.rotate(TILT[resref], resample=Image.BICUBIC)
        sheet.alpha_composite(img, (i * 40 + 4, 4))
        n, raw = write_bam(os.path.join(out_dir, resref + ".bam"), img)
        print("%-8s %6d -> %6d bytes" % (resref, raw, n))

    panel = make_panel(PANEL_W, PANEL_H)
    n, raw = write_bam(os.path.join(out_dir, "c4mkspbg.bam"), panel)
    print("%-8s %6d -> %6d bytes" % ("c4mkspbg", raw, n))

    if preview:
        big = sheet.resize((sheet.width * 6, sheet.height * 6), Image.NEAREST)
        bg = panel.resize((PANEL_W // 2, PANEL_H // 2), Image.LANCZOS)
        canvas = Image.new("RGBA", (big.width + 430, max(big.height, PANEL_H // 2 + 16)), (30, 30, 30, 255))
        canvas.alpha_composite(big, (0, 0))
        canvas.alpha_composite(bg, (big.width + 10, 8))
        canvas.save(preview)
        print("preview", preview)


if __name__ == "__main__":
    main()