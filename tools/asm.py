"""Assemble a Z80 source with sjasmplus and wrap it as an MSX BLOAD binary.

usage: python tools/asm.py src/z80/foo.asm OUT.BIN [org]

sjasmplus emits a raw image; MSX BLOAD wants a 7-byte header in front:
    FE  start(2)  end(2)  exec(2)      all little-endian
The org is read from the .sym file if the source defines a label named `start`,
otherwise pass it on the command line.
"""
import os, shutil, subprocess, sys, struct

# Point SJASMPLUS at the assembler, or leave sjasmplus on PATH.
SJASM = os.environ.get("SJASMPLUS") or shutil.which("sjasmplus") or "sjasmplus"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def assemble(src, out_bin, org=None, defines=()):
    raw = out_bin + '.raw'
    sym = out_bin + '.sym'
    r = subprocess.run([SJASM, '--raw=' + raw, '--sym=' + sym]
                       + ['-D' + d for d in defines] + [src],
                       capture_output=True, text=True)
    if r.returncode != 0:
        sys.stderr.write(r.stdout + r.stderr)
        raise SystemExit(f'sjasmplus failed on {src}')
    code = open(raw, 'rb').read()
    if org is None:
        org = 0
        for line in open(sym, encoding='latin-1'):
            # sjasmplus writes:  label: EQU 0x0000DA00
            if line.split(':')[0].strip().lower() == 'start':
                org = int(line.split('EQU')[1].strip(), 0)
                break
        if not org:
            raise SystemExit('no `start` label and no org given')
    end = org + len(code) - 1
    with open(out_bin, 'wb') as f:
        f.write(bytes([0xFE]) + struct.pack('<HHH', org, end, org) + code)
    os.remove(raw)
    print(f'{out_bin}: {len(code)} bytes at {org:04X}-{end:04X}')
    return org, len(code)


if __name__ == '__main__':
    args = sys.argv[1:]
    defines = tuple(a[2:] for a in args if a.startswith('-D'))
    args = [a for a in args if not a.startswith('-D')]
    src = args[0]
    out = args[1]
    org = int(args[2], 0) if len(args) > 2 else None
    assemble(src, out, org, defines)
