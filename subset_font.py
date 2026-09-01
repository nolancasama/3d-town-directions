"""
Subset NotoSansJP to only the characters used in the game dialogue + UI.
Outputs assets/fonts/NotoSansJP.ttf (overwrites the full font).
"""
from fontTools import subset

# All Japanese characters actually used in dialogue, buttons, and discovery panel.
CHARS = (
    # Dialogue lines (Kansai Japanese intro)
    "やあぼく松原くんやでアメリカ来るの初めてやねん"
    "わめっちゃ広いな"
    "どこに何があんかぜんわからへ助けてれ"
    "頼む"
    "そっか残念ほさいなら"
    "おおきに誰道いたらええ"
    # Buttons
    "助ける断"
    # Discovery counter
    "か所発見"
    # Punctuation used in Japanese text
    "！、？。〜"
    # Digits and slash for the discovery counter (e.g. 3 / 7 か所発見)
    "0123456789/"
    # Full printable ASCII — dialogue labels show English too (NPC replies, etc.)
    " !\"#$%&'()*+,-./:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"
)

def scan_script_chars():
    """Every non-ASCII character appearing anywhere in scripts/*.gd.

    Hand-maintaining the list above is not safe on its own: a glyph missing from
    the subset still renders on Windows, because the OS falls back to a system
    Japanese font, but comes out blank in the web build where no such fallback
    exists. So new UI text looks fine in the editor and is broken for players.
    Scanning the scripts closes that gap automatically.
    """
    import glob
    import io

    found = set()
    for path in sorted(glob.glob("scripts/*.gd")):
        with io.open(path, encoding="utf-8") as handle:
            for ch in handle.read():
                if ord(ch) > 127:
                    found.add(ch)
    return found


scanned = scan_script_chars()
print("Scanned scripts/*.gd: {} unique non-ASCII characters".format(len(scanned)))

unicodes = ",".join("U+{:04X}".format(ord(c)) for c in set(CHARS) | scanned)

args = [
    "C:/Windows/Fonts/NotoSansJP-VF.ttf",
    "--unicodes=" + unicodes,
    "--layout-features=*",
    "--output-file=assets/fonts/NotoSansJP.ttf",
    "--flavor=",   # keep as TTF (not woff2) so Godot can load it
]

print(f"Subsetting {len(set(CHARS))} unique codepoints...")
subset.main(args)

import os
size = os.path.getsize("assets/fonts/NotoSansJP.ttf")
print(f"Done. Output size: {size:,} bytes ({size // 1024} KB)")
