# Building IRONCLAD

`release/IRONCLAD.DSK` is a complete build. You only need this to make a new one.

## What you need

- **Python 3**
- **[sjasmplus](https://github.com/z00m128/sjasmplus)** on your `PATH`, or point
  `SJASMPLUS` at the executable
- **[openMSX](https://openmsx.org/)** with MSX2 system ROMs, to tokenise the BASIC

## The source

`src/IRONCLAD.BAS` is the readable master and the only BASIC file you edit. The
whole game does not fit in one MSX BASIC program, so the build emits four -
`IRONCLAD.BAS`, `SALVO.BAS`, `SALVOP.BAS` and `BARRAGE.BAS` - one per rule
family, each carrying only the enemy code its own rulesets need.
[Which program runs which ruleset](#which-program-runs-which-ruleset) lists what
each one covers and which engine it loads.

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
# the four BASIC programs
python tools/build.py src/IRONCLAD.BAS build/

# the Z80 engine, three variants
python tools/asm.py src/z80/fold.asm build/FOLD.BIN
python tools/asm.py -DSPRULES=1 src/z80/fold.asm build/FOLDSP.BIN
python tools/asm.py -DBARRULES=1 src/z80/fold.asm build/FOLDBAR.BIN

# the menu, with the version stamped in from VERSION, plus the artwork
python tools/stamp.py build/
cp *.SC5 build/

# tokenise in openMSX (it exits on its own); the .BAS names to tokenise
# come from mkdsk.FILES, so they cannot drift from the disk's contents
FILES="$(python -c "import sys;sys.path.insert(0,'tools');import mkdsk;print(' '.join(f for f in mkdsk.FILES if f.endswith('.BAS')))")" \
  openmsx -machine Sony_HB-F1XD -diska build/ -script tools/emu/tokenize.tcl

# the disk image - its contents and their order live in tools/mkdsk.py
python tools/mkdsk.py release/IRONCLAD.DSK build/
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

## Which program runs which ruleset

`SETUP.BAS` reads a `BD` field per ruleset and dispatches on it. Each program
loads its own engine; the three engines are one source assembled with different
constants, at the same addresses, so only the filename differs.

| program | engine | rulesets |
|---|---|---|
| `IRONCLAD.BAS` | none | CLASSIC, PURSUIT, STEALTH, ANKA |
| `SALVO.BAS` | `FOLD.BIN` | SALVO |
| `SALVOP.BAS` | `FOLDSP.BIN` | SALVO PLUS |
| `BARRAGE.BAS` | `FOLDBAR.BIN` | BARRAGE |

BARRAGE is its own program because its game is different: salvo size is the
surviving ship count, so sinking a ship also takes a shot off the opponent every
turn after. `tools/build.py` keeps the four apart with per-build line lists, so a
change meant for one cannot reach the others. Check that by building before and
after and comparing: the programs you did not mean to touch must come out
byte-identical.

## If you add, remove or resize an array

```sh
python tools/aryoffs.py > src/z80/offsets.inc
python tools/aryoffs.py sp > src/z80/offsets_sp.inc
```

Then reassemble all three engines. The machine code finds every BASIC array by a
fixed offset. A stale offsets file makes it read the wrong memory with no error.

`FOLD.BIN` and `FOLDBAR.BIN` are both built against `offsets.inc`, so BARRAGE's
`DIM` sequence has to stay identical to SALVO's: BARRAGE may add variables, but
it may never add, remove or resize an array. `FOLDSP.BIN` has its own,
`offsets_sp.inc`.

## Memory

Free memory during play is the binding constraint, and it differs by ruleset:

| | Floor |
|---|---|
| SALVO, SALVO PLUS, BARRAGE | **~360 bytes** |
| CLASSIC, PURSUIT, STEALTH, ANKA | ~4170 bytes |

Check the cost of a change against SALVO PLUS: it carries the largest fleet, so
its arrays are the biggest and its headroom the smallest of the family.
