"""Split 0/1 sample validity flags from the exact 64-bit numeric image."""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--check', action='store_true')
    args = ap.parse_args()
    assets = ROOT / 'assets'
    profile = json.loads((assets / 'profile.json').read_text())
    allocation = profile['allocations']['BAD']
    first, length = allocation['address'], allocation['words']
    assert (first, length) == (1799, 1500), 'Regenerate the RTL memory contract for a different profile'
    image = [int(s, 16) for s in (assets / 'data.hex').read_text().split()]
    assert len(image) == 6144
    flags = image[first:first + length]
    assert all(v in (0, 1) for v in flags)
    numeric = image[:first] + image[first + length:]
    assert len(numeric) == 4644
    outputs = {
        'compact_numeric_low.hex': ''.join(f'{v:016x}\n' for v in numeric[:4096]),
        'compact_numeric_high.hex': ''.join(f'{v:016x}\n' for v in numeric[4096:] + [0] * (1024 - len(numeric[4096:]))),
        'compact_bad.hex': ''.join(f'{v:x}\n' for v in flags),
    }
    for name, contents in outputs.items():
        path = assets / name
        if args.check:
            assert path.exists() and path.read_text() == contents, f'Stale generated image: {name}'
        else:
            path.write_text(contents)
    print('COMPACT STATE PASS: 6144 logical words -> 4644 numeric words + 1500 one-bit flags')


if __name__ == '__main__':
    main()
