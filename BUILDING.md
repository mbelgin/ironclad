# Building IRONCLAD

`release/IRONCLAD.DSK` is a complete build, so you only need this if you want to
change the game and produce a new disk.

## What you need

- **Python 3**
- **[sjasmplus](https://github.com/z00m128/sjasmplus)** to assemble the Z80 code.
  Put it on your `PATH`, or point `SJASMPLUS` at the executable.
- **[openMSX](https://openmsx.org/)** with MSX2 system ROMs. The build uses it to
  tokenise the BASIC programs, which is why the game loads in seconds instead of
  minutes.

## The source

`src/IRONCLAD.BAS` is the readable master and the only BASIC file you edit. An
MSX has about 23 KB for a BASIC program and the whole game does not fit, so the
build emits one program per rule family, each without the other's enemy code:

| Program | Rulesets |
|---|---|
| `IRONCLAD.BAS` | CLASSIC, PURSUIT, STEALTH, ANKA |
| `SALVO.BAS` | SALVO, BARRAGE |
| `SALVOP.BAS` | SALVO PLUS |

`SETUP.BAS` is the menu and is edited directly. The salvo opponent's search is
Z80 machine code in `src/z80/fold.asm`.

Line numbers in the built programs are **not** the source's: the enemy's
routines are renumbered from 2, because MSX BASIC finds a `GOTO` target by
scanning from the start of the program and hot code belongs at the front.
Everything else is its source line number plus 1000. So a runtime error reported
at line 2286 is source line 1286.

## Build

```sh
# 1. the three BASIC programs, into a scratch directory
python tools/build.py src/IRONCLAD.BAS build/

# 2. the Z80 engine, two variants
python tools/asm.py src/z80/fold.asm build/FOLD.BIN
python tools/asm.py -DSPRULES=1 src/z80/fold.asm build/FOLDSP.BIN

# 3. the artwork and the menu the disk needs
cp SETUP.BAS *.SC5 build/

# 4. tokenise the BASIC in openMSX (it exits on its own)
FILES="SETUP.BAS IRONCLAD.BAS SALVO.BAS SALVOP.BAS" \
  openmsx -machine Sony_HB-F1XD -diska build/ -script tools/emu/tokenize.tcl

# 5. the disk image
python -c "import sys;sys.path.insert(0,'tools');import mkdsk;mkdsk.build(
  'release/IRONCLAD.DSK', basdir='build',
  files=['SETUP.BAS','IRONCLAD.BAS','SALVO.BAS','SALVOP.BAS','IRONCLAD.SC5',
         'TILES.SC5','DEFEAT.SC5','VICTORY.SC5','FOLD.BIN','FOLDSP.BIN'])"
```

Building `release/IRONCLAD.DSK` also writes `sb/IRONCLAD_TEST.DSK`, a mirror of
it. Mount **that** one to play: the game saves `CFG.DAT` into whatever disk it
runs from, so playing the tracked image shows up as a change every time.

## If you add, remove or resize an array

Regenerate the offsets and reassemble:

```sh
python tools/aryoffs.py > src/z80/offsets.inc
python tools/aryoffs.py sp > src/z80/offsets_sp.inc
```

The machine code finds every BASIC array by a fixed offset from the first one.
A stale `offsets.inc` makes it read the wrong memory **with no error at all**,
so this is not optional.

## Watch the memory

The binding constraint is free memory during play, not program size, and it is
not the same in every ruleset. Measured on a real run, floor in bytes:

| | |
|---|---|
| SALVO, SALVO PLUS, BARRAGE | **~360** |
| CLASSIC, PURSUIT, STEALTH, ANKA | ~4170 |

The salvo family shares the constraint engine and its arrays, and runs on a few
hundred bytes with the interpreter's stack in the same space. A change that
looks free can exhaust it, so check a cost against SALVO or BARRAGE rather than
whichever ruleset is convenient.

## A note on editing the BASIC from scripts

If you generate edits to `src/IRONCLAD.BAS` programmatically, write backslashes
as `bytes([92])`. In a Python string `\12` is an octal escape and silently
inserts a control byte, which the MSX tokeniser then drops: the line looks right
in a listing and misbehaves in the game. Grep the file for bytes below 0x20
other than CR and LF before building.
