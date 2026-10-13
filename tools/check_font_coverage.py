"""Inspect actual LVGL binary cmap tables; do not mistake a text list for coverage."""
import argparse
import struct
from pathlib import Path


def codepoints(path):
    data = Path(path).read_bytes()
    offset = 0
    while offset + 8 <= len(data):
        size = struct.unpack_from('<I', data, offset)[0]
        if size < 8 or offset + size > len(data):
            raise ValueError(f'Invalid LVGL table in {path} at {offset}')
        if data[offset + 4:offset + 8] == b'cmap':
            count = struct.unpack_from('<I', data, offset + 8)[0]
            result = set()
            for i in range(count):
                start = offset + 12 + 16 * i
                rel, first, length, glyph, total, kind = struct.unpack_from('<IIHHHB', data, start)
                base = offset + rel
                if kind == 2:
                    result.update(range(first, first + length))
                elif kind == 0:
                    result.update(first + j for j in range(length) if j == 0 or data[base + j])
                elif kind in (1, 3):
                    result.update(first + struct.unpack_from('<H', data, base + 2*j)[0] for j in range(total))
                else:
                    raise ValueError(f'Unknown cmap format {kind}')
            return result
        offset += size
    raise ValueError(f'No cmap in {path}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('fonts', nargs='+')
    parser.add_argument('--text', default='湛江儋州亳州漯河濮阳衢州郴州蚌埠菏泽鄠邑埇桥')
    args = parser.parse_args()
    failed = False
    for font in args.fonts:
        found = codepoints(font)
        missing = ''.join(dict.fromkeys(c for c in args.text if ord(c) not in found))
        print(f'{font}: {len(found)} codepoints; missing={missing or "none"}')
        failed |= bool(missing)
    raise SystemExit(1 if failed else 0)
