"""Build a bootable 720 KB MSX disk image (FAT12) with the game files.

usage: python tools/mkdsk.py release/IRONCLAD.DSK [dir-with-tokenised-BAS]

The game does not write to the disk it runs from, so the image this builds is
the one to mount and play; it is not modified by playing.
The image contains AUTOEXEC.BAS, SETUP.BAS, IRONCLAD.BAS, SALVO.BAS, IRONCLAD.SC5 and
TILES.SC5 from the repository root.  If a directory is given, the .BAS files are taken
from there instead (tools/emu/tokenize.tcl produces tokenised copies that load in seconds).
"""
import sys, os, struct, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FILES = ['SETUP.BAS', 'IRONCLAD.BAS', 'SALVO.BAS', 'IRONCLAD.SC5', 'TILES.SC5']
BPS, SPC, RES, NFAT, ROOTN, TOTAL, MEDIA, SPF, SPT, HEADS = 512, 2, 1, 2, 112, 1440, 0xF9, 3, 9, 2

def boot_sector():
    b = bytearray(512)
    b[0:3] = b'\xEB\xFE\x90'
    b[3:11] = b'IRONCLAD'
    struct.pack_into('<HBHBHHBHHHH', b, 11, BPS, SPC, RES, NFAT, ROOTN, TOTAL, MEDIA, SPF, SPT, HEADS, 0)
    # boot code: paint FORCLR/BAKCLR/BDRCLR black so the BASIC banner prints invisibly,
    # then RET -> no DOS on this disk, drop into Disk BASIC (which runs AUTOEXEC.BAS)
    b[0x1E:0x2A] = bytes([0x3E, 0x01,             # LD A,1
                          0x32, 0xE9, 0xF3,       # LD (FORCLR),A
                          0x32, 0xEA, 0xF3,       # LD (BAKCLR),A
                          0x32, 0xEB, 0xF3,       # LD (BDRCLR),A
                          0xC9])                  # RET
    return bytes(b)

def build(out, basdir=None, files=None, autoexec=None):
    img = bytearray(TOTAL * BPS)
    img[0:512] = boot_sector()
    fat = bytearray(SPF * BPS)
    fat[0:3] = bytes([MEDIA, 0xFF, 0xFF])
    root = bytearray(ROOTN * 32)
    data_start = (RES + NFAT * SPF) * BPS + ROOTN * 32
    next_cluster = 2
    def set_fat(c, v):
        o = c * 3 // 2
        if c % 2 == 0:
            fat[o] = v & 0xFF; fat[o + 1] = (fat[o + 1] & 0xF0) | ((v >> 8) & 0x0F)
        else:
            fat[o] = (fat[o] & 0x0F) | ((v << 4) & 0xF0); fat[o + 1] = (v >> 4) & 0xFF
    if autoexec is not None:
        boot = autoexec
    else:
        # the same version the loading panel shows, from the one VERSION file
        with open(os.path.join(ROOT, 'VERSION'), encoding='ascii') as vf:
            title = 'IRONCLAD V' + vf.read().strip() + ' IS LOADING ...'
        boot = ('10 COLOR 15,1,1:SCREEN 0:WIDTH 40:KEY OFF:LOCATE %d,11:PRINT"%s"'
                ':LOCATE 4,13:PRINT"PLEASE WAIT, THIS TAKES A WHILE":RUN"SETUP.BAS"\r\n\x1a'
                % ((40 - len(title)) // 2, title)).encode('ascii')
    entries = [('AUTOEXEC.BAS', boot)]
    for f in (FILES if files is None else files):
        src = os.path.join(basdir, f) if basdir and os.path.exists(os.path.join(basdir, f)) else os.path.join(ROOT, f)
        entries.append((f, open(src, 'rb').read()))
    t = time.localtime()
    dostime = (t.tm_hour << 11) | (t.tm_min << 5) | (t.tm_sec // 2)
    dosdate = ((t.tm_year - 1980) << 9) | (t.tm_mon << 5) | t.tm_mday
    for i, (name, content) in enumerate(entries):
        base, ext = name.split('.')
        e = bytearray(32)
        e[0:8] = base.ljust(8).encode(); e[8:11] = ext.ljust(3).encode()
        e[11] = 0x20
        struct.pack_into('<HH', e, 22, dostime, dosdate)
        first = next_cluster
        n = (len(content) + BPS * SPC - 1) // (BPS * SPC)
        for k in range(n):
            c = next_cluster + k
            set_fat(c, 0xFFF if k == n - 1 else c + 1)
            off = data_start + (c - 2) * BPS * SPC
            img[off:off + BPS * SPC] = content[k * BPS * SPC:(k + 1) * BPS * SPC].ljust(BPS * SPC, b'\0')
        next_cluster += n
        struct.pack_into('<HI', e, 26, first, len(content))
        root[i * 32:(i + 1) * 32] = e
    for k in range(NFAT):
        o = (RES + k * SPF) * BPS
        img[o:o + len(fat)] = fat
    o = (RES + NFAT * SPF) * BPS
    img[o:o + len(root)] = root
    # The game never writes to the disk it runs from: the menu hands it the
    # chosen settings in RAM (SETUP.BAS 162-164 -> src/IRONCLAD.BAS 158).  The
    # image you build is the image you play, and playing does not modify it.
    try:
        open(out, 'wb').write(img)
        print(out, len(img), 'bytes,', len(entries), 'files')
    except OSError as e:
        # usually the image is mounted in an emulator right now
        raise SystemExit(f'{out} NOT written ({e}). Close whatever has it open.')

if __name__ == '__main__':
    build(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None)
