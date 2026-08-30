"""Copy SETUP.BAS into the build directory with the version stamped in.

The version lives in one place, the VERSION file at the repo root, and is the
number a player can match against a download: the public release, not any
internal or development numbering.

SETUP.BAS carries the placeholder @V@ inside a string literal, so an unstamped
copy still tokenises and runs; it just shows the placeholder, which makes a
missed build step obvious rather than silent.

usage: python tools/stamp.py build/
"""
import os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def version():
    with open(os.path.join(ROOT, 'VERSION'), encoding='ascii') as f:
        return 'V' + f.read().strip()


def stamp(outdir):
    src = os.path.join(ROOT, 'SETUP.BAS')
    with open(src, 'rb') as f:
        data = f.read()
    v = version().encode('ascii')
    if b'@V@' not in data:
        raise SystemExit('SETUP.BAS has no @V@ placeholder - nothing to stamp')
    out = os.path.join(outdir, 'SETUP.BAS')
    with open(out, 'wb') as f:
        f.write(data.replace(b'@V@', v))
    print(f'{out} stamped {v.decode()}')


if __name__ == '__main__':
    stamp(sys.argv[1] if len(sys.argv) > 1 else 'build')
