"""Build the runnable game programs from the readable master source.

usage: python build.py src/IRONCLAD.BAS <outdir>

Writes <outdir>/IRONCLAD.BAS (CLASSIC/PURSUIT/BROADSIDE/STEALTH rules) and
<outdir>/SALVO.BAS (SALVO/BARRAGE rules).  The MSX has ~23 KB for a BASIC program,
so each build drops the code the other mode does not need, moves the enemy AI to the
lowest line numbers (MSX-BASIC finds jump targets by scanning from the program start),
merges lines that are not jump targets, and strips optional spaces.
"""
import re, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import toksize

# line ranges only needed by one of the two builds
# Salvo Plus (SALVOP.BAS - 8.3 name; SALVOPLUS is 9 chars, illegal on MSX) lives in SP_ONLY; every other build drops those lines.
# Lines only the ordinary 5-ship salvo game needs go in SALVO_ONLY, so Salvo Plus can
# supply its own 10-ship versions without altering SALVO.BAS at all.
SP_ONLY = [(119, 119), (122, 122), (132, 132), (134, 134), (155, 155), (4013, 4013), (4156, 4174), (9028, 9029), (9031, 9031)]
SALVO_ONLY = [(118, 118), (120, 120), (130, 130), (133, 133), (3821, 3830), (3885, 3891), (4005, 4009), (4012, 4012), (9020, 9020), (9025, 9025), (9030, 9030)]

BD_ONLY = [(974, 974), (3943, 3943), (120, 120), (130, 130), (101, 101), (133, 139), (103, 103), (118, 118), (1146, 1151), (1795, 1795), (2222, 2222), (3798, 3893), (4000, 4699), (9060, 9069)]
STD_ONLY = [(121, 121), (124, 124), (131, 131), (164, 164), (9025, 9025), (9030, 9030), (667, 667), (962, 962), (975, 975), (3944, 3944), (306, 306), (483, 483), (668, 668), (718, 724), (820, 890), (950, 950), (977, 977), (991, 991), (1216, 1230), (1132, 1142), (1270, 1288), (1755, 1775), (2225, 2225), (1810, 1889), (1892, 1935), (1937, 1999)]
# hot code (moved to the front), in order, per build
HOT_BD = [(4600, 4610), (4300, 4339), (4000, 4102), (3840, 3857)]
HOT_STD = [(1890, 1891), (1810, 1935), (1940, 1965)]
JUMPS = re.compile(r'(GOTO|GOSUB|THEN|ELSE|RESTORE|RESUME)(\s*)(\d+)')

def nostr(b):
    return re.sub(r'"[^"]*"', '', b)

def in_ranges(n, ranges):
    return any(a <= n <= b for a, b in ranges)

def reorder(nums, bodies, hotranges):
    hot = []
    for a, b in hotranges:
        hot += [n for n in nums if a <= n <= b]
    mp = {n: i + 2 for i, n in enumerate(hot)}
    for n in nums:
        if n not in mp:
            mp[n] = n + 1000
    def fix(body):
        def sub(m):
            t = int(m.group(3))
            # references to lines dropped from this build keep the +1000 offset so they
            # can never collide with a real line (they sit in branches never taken)
            return m.group(1) + m.group(2) + (str(mp[t]) if t in mp else (str(t + 1000) if t else '0'))
        parts = re.split(r'("[^"]*")', body)
        return ''.join(pp if pp.startswith('"') else JUMPS.sub(sub, pp) for pp in parts)
    newb = {mp[n]: fix(bodies[n]) for n in nums}
    newb[1] = 'GOTO 1100:REM BUILT BY TOOLS/BUILD.PY FROM SRC/IRONCLAD.BAS - EDIT THE SOURCE, NOT THIS FILE'
    return sorted(newb), newb

def build(src, drop, hotranges, merge=True, strip=True):
    src = src.replace('\r\n', '\n').rstrip('\x1a')
    lines = [l for l in src.split('\n') if l.strip()]
    nums = [int(l.split(' ', 1)[0]) for l in lines]
    bodies = {int(l.split(' ', 1)[0]): l.split(' ', 1)[1] for l in lines}
    kept = [n for n in nums if not in_ranges(n, drop) and not bodies[n].startswith('REM')]
    # every jump target must exist in the master; targets inside a dropped range are
    # tolerated (they are only reached in the other build)
    for n in kept:
        for m in JUMPS.finditer(nostr(bodies[n])):
            t = int(m.group(3))
            assert t == 0 or t in bodies, f"line {n} jumps to missing line {t}"
    nums, bodies = reorder(kept, bodies, hotranges)
    refs = set()
    for n in nums:
        for m in JUMPS.finditer(nostr(bodies[n])):
            refs.add(int(m.group(3)))
    out = []
    for n in nums:
        b = bodies[n]
        if merge and out and n not in refs and not b.startswith('DATA') and not b.startswith('REM'):
            pn, pb = out[-1]
            pbs = nostr(pb)
            bs = nostr(b)
            if not re.search(r'\bIF\b|\bREM\b|GOTO|RETURN|DATA|ON ERROR|RESUME', pbs) and len(pb) + 1 + len(b) <= 250:
                out[-1][1] = pb + ':' + b
                continue
            if (pbs.count('IF') == 1 and 'ELSE' not in pbs and 'DATA' not in pbs and 'REM' not in pbs
                    and re.search(r'(THEN\s*\d+|GOTO\s*\d+|RETURN)\s*$', pbs)
                    and 'ELSE' not in bs and len(pb) + 6 + len(b) <= 250):
                out[-1][1] = pb + ' ELSE ' + b
                continue
        out.append([n, b])
    res = []
    for n, b in out:
        if strip:
            b = toksize.stripspaces(b)
        assert len(b) + len(str(n)) + 1 <= 255, (n, len(b))
        res.append(f"{n} {b}")
    return '\r\n'.join(res) + '\r\n\x1a'

if __name__ == '__main__':
    src = open(sys.argv[1], encoding='latin-1').read()
    outdir = sys.argv[2]
    for name, drop, hot in (('IRONCLAD.BAS', BD_ONLY + SP_ONLY, HOT_STD),
                            ('SALVO.BAS', STD_ONLY + SP_ONLY, HOT_BD),
                            ('SALVOP.BAS', STD_ONLY + SALVO_ONLY, HOT_BD)):
        o = build(src, drop, hot)
        open(os.path.join(outdir, name), 'w', encoding='latin-1', newline='').write(o)
        print(name, "lines", o.count('\r\n'), "tok~", toksize.total(o))
