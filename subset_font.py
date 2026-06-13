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
    # NO Latin block — Godot falls back to its built-in font for ASCII,
    # which keeps English labels looking normal (matching the rest of the UI).
)

unicodes = ",".join("U+{:04X}".format(ord(c)) for c in set(CHARS))

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
