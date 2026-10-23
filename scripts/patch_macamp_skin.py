#!/usr/bin/env python3
"""
Patch Winamp 2.91 base skin titlebars to say 'MACAMP' instead of 'WINAMP'.
Modifies:
  - TITLEBAR.BMP (Main active, Main inactive, Shade active, Shade inactive)
  - EQMAIN.BMP   (Equalizer active, Equalizer inactive)
  - PLEDIT.BMP   (Playlist active, Playlist inactive)

Then repacks skin/base-2.91.wsz, MacAmp/base-2.91.wsz, and MacAmp/Resources/base-2.91.wsz.
"""

import os
import struct
import zipfile

def decode_bmp(path):
    with open(path, "rb") as f:
        data = f.read()
    hdr, w, h, planes, bpp, comp = struct.unpack_from("<IiiHHI", data, 14)
    palette = []
    for i in range(256):
        b, g, r, a = struct.unpack_from("<4B", data, 54 + i*4)
        palette.append((r, g, b))
    offset = struct.unpack_from("<I", data, 10)[0]
    
    if comp == 0:
        row_size = ((w * bpp + 31) // 32) * 4
        pixels = []
        for y in range(h):
            row_offset = offset + (h - 1 - y) * row_size
            pixels.append(list(data[row_offset:row_offset + w]))
        return w, h, palette, pixels
    elif comp == 1:
        pixels = [[0]*w for _ in range(h)]
        ptr = offset
        x, y = 0, h - 1
        while ptr < len(data) and y >= 0:
            b1, b2 = data[ptr], data[ptr+1]
            ptr += 2
            if b1 > 0:
                for _ in range(b1):
                    if 0 <= x < w and 0 <= y < h:
                        pixels[y][x] = b2
                    x += 1
            else:
                if b2 == 0:
                    x, y = 0, y - 1
                elif b2 == 1:
                    break
                elif b2 == 2:
                    dx, dy = data[ptr], data[ptr+1]
                    ptr += 2
                    x += dx
                    y -= dy
                else:
                    for _ in range(b2):
                        if 0 <= x < w and 0 <= y < h:
                            pixels[y][x] = data[ptr]
                        ptr += 1
                        x += 1
                    if b2 % 2 != 0:
                        ptr += 1
        return w, h, palette, pixels
    else:
        raise ValueError(f"Unsupported compression {comp} in {path}")

def encode_bmp(w, h, palette, pixels):
    row_size = ((w * 8 + 31) // 32) * 4
    img_size = row_size * h
    offset = 14 + 40 + len(palette) * 4
    file_size = offset + img_size
    
    header = struct.pack("<2sIII", b"BM", file_size, 0, offset)
    dib = struct.pack("<IiiHHIIiiII", 40, w, h, 1, 8, 0, img_size, 2835, 2835, len(palette), 0)
    
    pal_data = bytearray()
    for r, g, b in palette:
        pal_data.extend([b, g, r, 0])
        
    pixel_data = bytearray()
    pad = b"\x00" * (row_size - w)
    for y in range(h - 1, -1, -1):
        pixel_data.extend(bytes(pixels[y]))
        pixel_data.extend(pad)
        
    return header + dib + pal_data + pixel_data

import shutil

def patch_winamp_to_macamp(pixels, palette, x_start, y_start):
    """
    Patches the 43-pixel region at (x_start, y_start) from WINAMP to MACAMP with perfect spacing.
    Original WINAMP layout:
      W (8) + sp(1) + I (2) + sp(1) + N (6) + A (6) + sp(1) + M (7) + sp(1) + P (6)
      Indices relative to x_start:
        W: 0..7, sp: 8, I: 9..10, sp: 11, N: 12..17, A: 18..23, sp: 24, M: 25..31, sp: 32, P: 33..38

    New MACAMP layout (balanced 1-pixel gap between every character):
      M (7) + sp(1) + A (6) + sp(1) + C (5) + sp(1) + A (6) + sp(1) + M (7) + sp(1) + P (6)
      Indices relative to x_start:
        M1: 0..6
        sp: 7
        A1: 8..13
        sp: 14
        C:  15..19
        sp: 20
        A2: 21..26
        sp: 27
        M2: 28..34
        sp: 35
        P:  36..41
        sp: 42
    """
    for r in range(6):
        y = y_start + r

        # Extract untouched original letter slices from this row
        m_pixels = [pixels[y][x_start + 25 + i] for i in range(7)]
        a_pixels = [pixels[y][x_start + 18 + i] for i in range(6)]
        p_pixels = [pixels[y][x_start + 33 + i] for i in range(6)]
        sp = pixels[y][x_start + 24]

        # Determine highlight, shadow, and bevel colors from text pixels on this row
        all_text_pix = sorted(set(m_pixels + a_pixels + p_pixels), key=lambda idx: sum(palette[idx]), reverse=True)
        hi = all_text_pix[0]
        sh = all_text_pix[1] if len(all_text_pix) > 1 else hi
        bv = all_text_pix[2] if len(all_text_pix) > 2 else sh

        # Construct authentic Winamp-style 'C' (5x6) with smooth rounded outer and inner corners
        if r == 0:
            c_pixels = [sp, bv, hi, hi, sh]
        elif r == 1:
            c_pixels = [bv, hi, bv, sp, hi]
        elif r == 2 or r == 3:
            c_pixels = [hi, hi, sp, sp, sp]
        elif r == 4:
            c_pixels = [bv, hi, bv, sp, hi]
        elif r == 5:
            c_pixels = [sp, bv, hi, hi, sh]

        # 1. Write M1 at cols 0..6
        for i in range(7):
            pixels[y][x_start + 0 + i] = m_pixels[i]

        # 2. Space at col 7
        pixels[y][x_start + 7] = sp

        # 3. Write A1 at cols 8..13
        for i in range(6):
            pixels[y][x_start + 8 + i] = a_pixels[i]

        # 4. Space at col 14
        pixels[y][x_start + 14] = sp

        # 5. Write C at cols 15..19
        for i in range(5):
            pixels[y][x_start + 15 + i] = c_pixels[i]

        # 6. Space at col 20
        pixels[y][x_start + 20] = sp

        # 7. Write A2 at cols 21..26
        for i in range(6):
            pixels[y][x_start + 21 + i] = a_pixels[i]

        # 8. Space at col 27
        pixels[y][x_start + 27] = sp

        # 9. Write M2 at cols 28..34
        for i in range(7):
            pixels[y][x_start + 28 + i] = m_pixels[i]

        # 10. Space at col 35
        pixels[y][x_start + 35] = sp

        # 11. Write P at cols 36..41
        for i in range(6):
            pixels[y][x_start + 36 + i] = p_pixels[i]

        # 12. Trailing space at col 42
        pixels[y][x_start + 42] = sp


def compose_macamp(pixels, palette, src_x, y_start, segs, dst_x, gap):
    """
    Writes MACAMP over a WINAMP whose letters sit at src_x + segs[letter] = (offset, width), using that
    bitmap's own M, A and P glyphs (VIDEO.BMP and MB.BMP use other letter widths than TITLEBAR.BMP).
    The word starts at dst_x with `gap` background columns between letters; the old word is cleared first.
    """
    order = ["M", "A", "C", "A", "M", "P"]
    width = sum(5 if l == "C" else segs[l][1] for l in order) + gap * (len(order) - 1)
    for r in range(6):
        y = y_start + r
        glyph = {l: [pixels[y][src_x + segs[l][0] + i] for i in range(segs[l][1])] for l in ("M", "A", "P")}
        sp = pixels[y][src_x - 1]
        text = sorted(set(glyph["M"] + glyph["A"] + glyph["P"]) - {sp}, key=lambda idx: sum(palette[idx]), reverse=True)
        hi = text[0]
        sh = text[1] if len(text) > 1 else hi
        bv = text[2] if len(text) > 2 else sh
        glyph["C"] = [[sp, bv, hi, hi, sh], [bv, hi, bv, sp, hi], [hi, hi, sp, sp, sp], [hi, hi, sp, sp, sp],
                      [bv, hi, bv, sp, hi], [sp, bv, hi, hi, sh]][r]
        for x in range(min(src_x, dst_x), max(src_x + 39, dst_x + width)):
            pixels[y][x] = sp
        x = dst_x
        for l in order:
            for v in glyph[l]:
                pixels[y][x] = v
                x += 1
            x += gap

def main():
    orig_src = "webamp-master/packages/webamp/assets/skins/base-2.91"
    base_dir = "skin/base-2.91"
    
    # Restore pristine bitmaps from reference if available to guarantee idempotency
    if os.path.isdir(orig_src):
        for fname in ["TITLEBAR.BMP", "EQMAIN.BMP", "PLEDIT.BMP", "VIDEO.BMP", "MB.BMP"]:
            src = os.path.join(orig_src, fname)
            dst = os.path.join(base_dir, fname)
            if os.path.isfile(src):
                shutil.copyfile(src, dst)
    
    # 1. Patch TITLEBAR.BMP
    tb_path = os.path.join(base_dir, "TITLEBAR.BMP")
    print(f"Patching {tb_path}...")
    w, h, pal, px = decode_bmp(tb_path)
    patch_winamp_to_macamp(px, pal, 145, 5)   # Main Active
    patch_winamp_to_macamp(px, pal, 145, 20)  # Main Inactive
    patch_winamp_to_macamp(px, pal, 47, 34)   # Shade Active
    patch_winamp_to_macamp(px, pal, 47, 47)   # Shade Inactive
    with open(tb_path, "wb") as f:
        f.write(encode_bmp(w, h, pal, px))
        
    # 2. Patch EQMAIN.BMP
    eq_path = os.path.join(base_dir, "EQMAIN.BMP")
    print(f"Patching {eq_path}...")
    w, h, pal, px = decode_bmp(eq_path)
    patch_winamp_to_macamp(px, pal, 95, 139)  # EQ Active
    patch_winamp_to_macamp(px, pal, 95, 154)  # EQ Inactive
    with open(eq_path, "wb") as f:
        f.write(encode_bmp(w, h, pal, px))
        
    # 3. Patch PLEDIT.BMP
    pl_path = os.path.join(base_dir, "PLEDIT.BMP")
    print(f"Patching {pl_path}...")
    w, h, pal, px = decode_bmp(pl_path)
    patch_winamp_to_macamp(px, pal, 33, 5)    # PL Active
    patch_winamp_to_macamp(px, pal, 33, 26)   # PL Inactive
    with open(pl_path, "wb") as f:
        f.write(encode_bmp(w, h, pal, px))
        
    # 4. VIDEO.BMP ("WINAMP VIDEO") and MB.BMP ("WINAMP BROWSER"): active title at y 5, inactive at y 26
    for fname, src_x, segs, dst_x, gap in [
        ("VIDEO.BMP", 41, {"M": (25, 7), "A": (18, 6), "P": (33, 6)}, 39, 1),
        ("MB.BMP", 32, {"M": (24, 8), "A": (18, 6), "P": (33, 6)}, 32, 0),
    ]:
        path = os.path.join(base_dir, fname)
        print(f"Patching {path}...")
        w, h, pal, px = decode_bmp(path)
        for y in (5, 26):
            compose_macamp(px, pal, src_x, y, segs, dst_x, gap)
        with open(path, "wb") as f:
            f.write(encode_bmp(w, h, pal, px))

    # 5. Repack base-2.91.wsz archives
    wsz_destinations = [
        "skin/base-2.91.wsz",
        "MacAmp/base-2.91.wsz",
        "MacAmp/Resources/base-2.91.wsz"
    ]
    
    files_to_pack = sorted(os.listdir(base_dir))
    for dest in wsz_destinations:
        print(f"Creating {dest} with {len(files_to_pack)} skin files...")
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        with zipfile.ZipFile(dest, "w", zipfile.ZIP_DEFLATED) as zf:
            for fname in files_to_pack:
                src_file = os.path.join(base_dir, fname)
                if os.path.isfile(src_file):
                    zf.write(src_file, arcname=fname)
                    
    print("Done! MacAmp base skin generated successfully.")

if __name__ == "__main__":
    main()
