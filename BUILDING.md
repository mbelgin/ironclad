# Building IRONCLAD

`release/IRONCLAD.DSK` is a complete build. You only need this to make a new one.

## What you need

- **Python 3**
- **[sjasmplus](https://github.com/z00m128/sjasmplus)** on your `PATH`, or point
  `SJASMPLUS` at the executable
- **[openMSX](https://openmsx.org/)** with MSX2 system ROMs, to tokenise the BASIC

## The source

`src/IRONCLAD.BAS` is the readable master and the only BASIC file you edit. The
build emits one program per rule family, each without the other's enemy code:

| Program | Rulesets |
|---|---|
| `IRONCLAD.BAS` | CLASSIC, PURSUIT, STEALTH, ANKA |
| `SALVO.BAS` | SALVO, BARRAGE |
| `SALVOP.BAS` | SALVO PLUS |

`SETUP.BAS` is the menu and is edited directly. The salvo opponent's search is
Z80 machine code in `src/z80/fold.asm`.

The version shown on the loading screen comes from the `VERSION` file at the
repo root, and nowhere else. `SETUP.BAS` carries a `@V@` placeholder that
`tools/stamp.py` substitutes on the way into `build/`; the boot message in
`tools/mkdsk.py` reads the same file. Copying `SETUP.BAS` by hand instead of
running the stamp leaves the placeholder showing on screen.

Line numbers in the built programs are not the source's: the enemy's routines
are renumbered from 2, everything else is its source line plus 1000. An error
reported at line 2286 is source line 1286.

## Build

```sh
# the three BASIC programs
python tools/build.py src/IRONCLAD.BAS build/

# the Z80 engine, two variants
python tools/asm.py src/z80/fold.asm build/FOLD.BIN
python tools/asm.py -DSPRULES=1 src/z80/fold.asm build/FOLDSP.BIN

# the menu, with the version stamped in from VERSION, plus the artwork
python tools/stamp.py build/
cp *.SC5 build/

# tokenise in openMSX (it exits on its own)
FILES="SETUP.BAS IRONCLAD.BAS SALVO.BAS SALVOP.BAS" \
  openmsx -machine Sony_HB-F1XD -diska build/ -script tools/emu/tokenize.tcl

# the disk image
python -c "import sys;sys.path.insert(0,'tools');import mkdsk;mkdsk.build(
  'release/IRONCLAD.DSK', basdir='build',
  files=['SETUP.BAS','IRONCLAD.BAS','SALVO.BAS','SALVOP.BAS','IRONCLAD.SC5',
         'TILES.SC5','DEFEAT.SC5','VICTORY.SC5','FOLD.BIN','FOLDSP.BIN'])"
```

Mount and play that image directly. The game never writes to the disk it runs
from, so playing does not modify it.

## The cover art

The `.SC5` files ship ready to use and the build chain above does not rebuild
them.

`IRONCLAD.SC5` carries the loading panel's QR code as a 58x58 block of pixels at
(36,152). `SETUP.BAS` copies that block onto the panel with a single `COPY`;
plotting it in BASIC instead cost 24 seconds of the boot. Two things follow if
you ever regenerate the cover art yourself:

- the block has to be written back in, or the panel shows a plain white square
  with no error anywhere;
- it has to stay inside the menu box `SETUP.BAS` 3520 fills, or a QR code
  appears on the title screen.

## If you add, remove or resize an array

```sh
python tools/aryoffs.py > src/z80/offsets.inc
python tools/aryoffs.py sp > src/z80/offsets_sp.inc
```

Then reassemble. The machine code finds every BASIC array by a fixed offset. A
stale `offsets.inc` makes it read the wrong memory with no error.

## Memory

Free memory during play is the binding constraint, and it differs by ruleset:

| | Floor |
|---|---|
| SALVO, SALVO PLUS, BARRAGE | **~360 bytes** |
| CLASSIC, PURSUIT, STEALTH, ANKA | ~4170 bytes |

Check the cost of a change against SALVO or BARRAGE.
