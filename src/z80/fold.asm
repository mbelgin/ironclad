; FOLD - constraint filter for the salvo AI.  Replaces BASIC 4301-4318 and
; 4600-4610 (KILLCELL), and serves propagate's per-cell kills as well.
;
; One idea makes all three the same routine: mark the salvo into a 12x12 byte
; map, then a candidate's overlap is just the sum of that map along its cells.
;   fold   mark every shot, then scan all five ships against HK()
;   kill1  mark one cell, then scan one ship with H=0
; A candidate survives only if its overlap equals the reported hit count.
;
; The padded index (X+1)*12+(Y+1) is the one MC already uses, so the coverage
; grid is walked with the same index and stride - no second address calculation.
;
;   USR0(NS)                  fold the salvo
;   USR1(KN*256 + U*16 + V)   kill ship KN's candidates covering (U,V)
;
; BASIC pokes VARPTR(FA(0)) into pBASE once; every other array address comes
; from it via offsets computed at build time by tools/aryoffs.py.

; One source, two binaries: FOLD.BIN (classic salvo, 5 tracked ships) and
; FOLDSP.BIN (Salvo Plus, 7 tracked ships), selected by -DSPRULES=1.  The two
; share every address; only the ship count, the array offsets and the
; boat-phase buoy skip differ.
                IFDEF SPRULES
NSHIPS          equ     7
                include "offsets_sp.inc"
                ELSE
NSHIPS          equ     5
                include "offsets.inc"
                ENDIF

; Session-memory counters live ABOVE the image at fixed addresses, outside the
; BLOADed span, so they survive the reload each RUN performs.  Only power-off
; clears them - which is exactly the meaning of a session.
SMEMG           equ     0DDF0h          ; games learned (byte, capped at 14)
SMEMR           equ     0DDF1h          ; rim cells seen (byte, <= 238)
SMEMB           equ     0DDF2h          ; learned-rim flag, poked by BASIC
                                        ; 0DDF3/F4: the power-on magic pair

; Two hard walls bound this image.  Disk BASIC's own work area is machine
; dependent: MEASURED at DE78 on the Sony HB-F1XD and DE6F on the blueMSX
; MSX2+ profile (the two machines this game actually runs on).  The image and
; the session counters stay below DDF0 - 127 bytes under the worst measured
; wall - and release/PROBE.DSK reports any new machine's wall before trusting
; it.  The 64 bytes just above the CLEAR address hold the file control block,
; so the image must START above those.  CLEAR is at CF38, the image runs
; D588 up, and every byte of it is a byte the BASIC pool does not get.
PARM            equ     0CF78h          ; CLEAR address + 64
; MO lives here as BYTES: it only ever holds the current turn stamp, which the
; wrap-safe bump below keeps inside one byte, so the 12x12 plane costs 144
; bytes instead of a 296-byte BASIC integer array.
MOBUF           equ     PARM+144        ; 12x12 stamp plane, byte per cell
; MC lives here as BYTES too: it holds live coverage counts, bounded by twice
; the fleet's total length (42 for Salvo Plus), so a byte per cell is ample
; and another 296-byte integer array leaves the pool.
MCBUF           equ     MOBUF+144       ; 12x12 coverage plane, byte per cell
; FA lives here as BYTES in reserved RAM, not as a BASIC integer array: the
; flags are only ever 0 or 1, BASIC touched them in just two places (init and
; the lone-candidate scan, now USR7 and a PEEK loop), and halving their width
; while moving them out of the pool hands roughly a kilobyte back to BASIC.
FABUF           equ     MCBUF+144       ; 1120 candidate flags (SP-sized)
pBASE           equ     PARM+0
pPH             equ     PARM+2
pCC             equ     PARM+4
pOS             equ     PARM+6
pSZ             equ     PARM+8
pHK             equ     PARM+10
pTX             equ     PARM+12
pTY             equ     PARM+14
pMAP            equ     PARM+26         ; borrows MG, which the fold never uses
pBZ             equ     PARM+28         ; buoy plane, read by the SP explore
pPM             equ     PARM+30
vRD             equ     PARM+32         ; BASIC pokes these three before USR2
vNF             equ     PARM+33
vRIM            equ     PARM+34
vST             equ     PARM+36         ; byte: the MO stamp, bumped wrap-safe
vJ0F            equ     PARM+37         ; byte: first live candidate of a draw
vRDL            equ     PARM+47         ; byte: rim redraws left (see place)
vBS             equ     PARM+38         ; word: best score so far
vBX             equ     PARM+40
vBY             equ     PARM+41
vC              equ     PARM+42
vR              equ     PARM+43
vP9             equ     PARM+44         ; word: padded index of (C,R)
vT              equ     PARM+46
vBXW            equ     PARM+48
vMODE           equ     PARM+50
vKL             equ     PARM+51         ; last-afloat wounded ship, poked by BASIC
vWT             equ     PARM+52         ; word: weight added per candidate cell
vH              equ     PARM+16
vLK             equ     PARM+17
vW              equ     PARM+18
vK              equ     PARM+19
vFAP            equ     PARM+20
vIDX            equ     PARM+22
vSTEP           equ     PARM+24
vSEED           equ     PARM+54         ; word: xorshift state, zeroed by BLOAD
vGG             equ     PARM+56
vSA             equ     PARM+57
vSI             equ     PARM+58
vSJ             equ     PARM+59
vSCJ            equ     PARM+60
vRDS            equ     PARM+62
vQNC            equ     PARM+63
vO2             equ     PARM+64
vSOP            equ     PARM+65
vCT             equ     PARM+67
vOSK            equ     PARM+68
vT2             equ     PARM+70
vT3             equ     PARM+71
vJ0             equ     PARM+72
vIBB            equ     PARM+74
vS9             equ     PARM+76
vW2             equ     PARM+78
vSOA            equ     PARM+80         ; up to 7 ship indices, sorted
vZX             equ     PARM+88         ; up to 21 sampled cells (42 bytes)
vRK             equ     PARM+130        ; in-game rim verdict, poked by BASIC
vCCK            equ     PARM+131        ; word: CC(K) during the probe argmin
; exact's scratch aliases the sampler's (vSOA/vZX): the two never run in the
; same turn, and each initialises everything it reads.
eORD            equ     vSOA            ; sortso's output IS the DFS order
eLVL            equ     PARM+85
eIT             equ     PARM+86         ; per level: iterator word + end word
eTOT            equ     PARM+106
eNODE           equ     PARM+108
eCELLS          equ     PARM+110        ; 5 levels x 5 padded cell bytes

; The parameter block, MO plane and FA buffer are reserved RAM but NOT part
; of the BLOADed image: nothing depends on load-time zeroing (rnd16 self-seeds,
; fainit resets FA, MO and vST at every game start).
; The image is BLOADed past the buffers.  Classic uses only 760 of the
; 1120 FA bytes, so FOLD.BIN starts 360 lower and gains that image room for
; free; FOLDSP needs the full buffer.
                IFDEF SPRULES
FASIZE          equ     1120
                ELSE
FASIZE          equ     760
                ENDIF
                org     FABUF+FASIZE
start:
                jp      fold
                jp      kill1
                jp      explore
                jp      pickn
                jp      marg
                jp      sample
                jp      samp1
                jp      fainit
                IFNDEF SPRULES
                jp      probesel
                ENDIF

; ---------------------------------------------------------------- pointers
; MG is the first array DIM'd, so its data sits one 8-byte header past ARYTAB.
; Reading it here rather than trusting a poked VARPTR is not an optimisation: a
; variable created for the first time mid-turn shifts the whole array table, and
; a pointer captured at the top of the turn then addresses 20 bytes below every
; array.  BASIC cannot run while this does, so what is read here cannot go stale.
setptrs:
                ld      hl,(0F6C4h)
                ld      de,8
                add     hl,de
                ld      (pBASE),hl
                IFNDEF SPRULES
                ld      hl,(pBASE)
                ld      de,oPH
                add     hl,de
                ld      (pPH),hl
                ENDIF
                ld      hl,(pBASE)
                ld      de,oCC
                add     hl,de
                ld      (pCC),hl
                ld      hl,(pBASE)
                ld      de,oOS
                add     hl,de
                ld      (pOS),hl
                ld      hl,(pBASE)
                ld      de,oSZ
                add     hl,de
                ld      (pSZ),hl
                ld      hl,(pBASE)
                ld      de,oHK
                add     hl,de
                ld      (pHK),hl
                ld      hl,(pBASE)
                ld      de,oTX
                add     hl,de
                ld      (pTX),hl
                ld      hl,(pBASE)
                ld      de,oTY
                add     hl,de
                ld      (pTY),hl
                IFDEF SPRULES
                ld      hl,(pBASE)
                ld      de,oBZ
                add     hl,de
                ld      (pBZ),hl
                ENDIF
                ld      hl,(pBASE)
                ld      de,oPM
                add     hl,de
                ld      (pPM),hl
                ld      hl,(pBASE)      ; the shot map lives in MG's storage
                ld      de,oMG
                add     hl,de
                ld      (pMAP),hl
                ret

; clearing the map is destructive to MG, so only fold and kill1 do it
clrmap:
                ld      hl,(pMAP)
                push    hl
                pop     de
                inc     de
                ld      bc,143
                ld      (hl),0
                ldir
                ret

; wipe the stamp plane; also the game-start state (via fainit)
clrmo:
                ld      hl,MOBUF
                ld      de,MOBUF+1
                ld      bc,143
                ld      (hl),0
                ldir
                ret

; ST = ST + 1, wrap-safe: stamps live in one byte, and 0 means "never
; stamped", so on wrap the plane is wiped and the count restarts at 1.
; Every stamp comparison stays exact because no stale stamp can survive
; into a new epoch.
bumpst:
                ld      a,(vST)
                inc     a
                jr      nz,bst1
                call    clrmo
                ld      a,1
bst1:
                ld      (vST),a
                ret

; ---------------------------------------------------------------- USR0: fold
fold:
                call    setptrs
                call    clrmap
                xor     a
                ld      (vMODE),a
                ld      hl,(0F7F8h)     ; DAC+2 = NS
                ld      a,l
                and     0Fh
                ret     z
                ld      b,a
                ld      c,0
fmark:
                push    bc
                ld      a,c
                ld      hl,(pTX)
                call    getel
                push    af              ; getel below clobbers D, so park TX
                ld      a,c
                ld      hl,(pTY)
                call    getel
                ld      e,a
                pop     af
                ld      d,a
                call    mapptr
                ld      (hl),1
                pop     bc
                inc     c
                djnz    fmark

                ld      a,1
                ld      (vK),a
fship:
                ld      a,(vK)
                ld      hl,(pHK)
                call    getel
                ld      (vH),a
                call    scan
                ld      hl,vK
                inc     (hl)
                ld      a,(hl)
                cp      NSHIPS+1
                jr      c,fship
                ret

; ------------------------------------------------- USR1: kill one cell's cover
kill1:
                call    setptrs
                call    clrmap
                xor     a
                ld      (vMODE),a
                ld      hl,(0F7F8h)
                ld      a,h
                ld      (vK),a
                ld      a,l
                rrca
                rrca
                rrca
                rrca
                and     0Fh
                ld      d,a
                ld      a,l
                and     0Fh
                ld      e,a
                call    mapptr
                ld      (hl),1
                xor     a
                ld      (vH),a
                jp      scan

; -------------------------------------------------- USR3: top-N shot selection
; Replaces BASIC 4050-4056: take the NF highest-scoring cells out of the kill
; mode score grid (MG, padded index 13..130), writing them to TX/TY and knocking
; each chosen cell down to -9 so the next pass cannot pick it again.
; Scores are signed: MG starts at -1 for fired cells.
pickn:
                call    setptrs
; The last-ship finisher.  When BASIC reports exactly one ship afloat and
; wounded (vKL), every unfired cell its surviving candidates can still
; occupy gets a dominating weight before the pick: covering that set is a
; guaranteed game-ending sink whenever it fits the salvo, and the twin
; measured the rule at W114/L0 (uniform) and W126/L0 (edge) over 3000
; paired boards - it never loses a game, it only wins the coin-flips.
                ld      a,(vKL)
                or      a
                jr      z,pknorm
                ld      b,a
                ld      a,1
                ld      (vMODE),a
                ld      hl,2000
                ld      (vWT),hl
                ld      a,b
                cp      255             ; 255 = endgame cover: every ship's
                jr      nz,pkone        ; surviving cells (sunk ships add
                ld      a,1             ; nothing - their cells are fired)
pkall:
                ld      (vK),a
                push    af
                call    scan
                pop     af
                inc     a
                cp      NSHIPS+1
                jr      c,pkall
                jr      pkdone
pkone:
                ld      (vK),a
                call    scan
pkdone:
                xor     a
                ld      (vMODE),a
                ld      (vKL),a
pknorm:
                xor     a
                ld      (vT),a
pnshot:
                ld      hl,-1           ; BS = -1
                ld      (vBS),hl
                ld      hl,13
                ld      (vP9),hl
pncell:
                ld      hl,(vP9)
                add     hl,hl
                ld      de,(pMAP)       ; pMAP is MG
                add     hl,de
                ld      e,(hl)
                inc     hl
                ld      d,(hl)          ; DE = MG(P9), signed
                ld      hl,(vBS)
                ld      a,h             ; bias both by 8000h so an unsigned
                xor     80h             ; compare gives the signed answer
                ld      h,a
                ld      a,d
                xor     80h
                ld      d,a
                ex      de,hl           ; HL = SC', DE = BS'
                or      a
                sbc     hl,de
                jr      z,pnnext        ; equal: keep the earlier cell
                jr      c,pnnext        ; SC < BS
                ld      hl,(vP9)        ; new best
                add     hl,hl
                ld      de,(pMAP)
                add     hl,de
                ld      e,(hl)
                inc     hl
                ld      d,(hl)
                ld      (vBS),de
                ld      hl,(vP9)
                ld      (vBXW),hl
pnnext:
                ld      hl,(vP9)
                inc     hl
                ld      (vP9),hl
                ld      de,131
                or      a
                sbc     hl,de
                jr      nz,pncell

                ld      hl,(vBXW)       ; split BX into column and row
                ld      b,0
pndiv:
                ld      de,12
                or      a
                sbc     hl,de
                jr      c,pndone
                inc     b
                jr      pndiv
pndone:
                ld      de,12
                add     hl,de           ; HL = remainder
                dec     b               ; B = X
                ld      a,l
                dec     a               ; A = Y
                ld      c,a
                push    bc
                ld      a,(vT)
                ld      hl,(pTX)
                call    elptr
                pop     bc
                ld      (hl),b          ; sign-extend: a padding cell yields -1
                inc     hl
                ld      a,b
                rla
                sbc     a,a
                ld      (hl),a
                push    bc
                ld      a,(vT)
                ld      hl,(pTY)
                call    elptr
                pop     bc
                ld      (hl),c
                inc     hl
                ld      a,c
                rla
                sbc     a,a
                ld      (hl),a
                ld      hl,(vBXW)       ; MG(BX) = -9
                add     hl,hl
                ld      de,(pMAP)
                add     hl,de
                ld      (hl),-9
                inc     hl
                ld      (hl),-1
                ld      hl,vT
                inc     (hl)
                ld      a,(hl)
                ld      hl,vNF
                cp      (hl)
                jp      c,pnshot
                ret

; ------------------------------------------------------- USR2: explore select
; Picks the NF unfired cells with the best coverage score, exactly as BASIC did:
;   SC = MC(P9)*8 + ((C*5 + R*3 + RD) AND 7), plus 192 on the rim when asked.
; Cells already chosen this turn are stamped in MO so a salvo never repeats one.
; USR argument carries ST; RD, NF and the rim flag are poked in beforehand.
explore:
                call    setptrs
                call    bumpst
                xor     a
                ld      (vT),a
extshot:
                ld      hl,-1
                ld      (vBS),hl
                xor     a
                ld      (vC),a
extcol:
                xor     a
                ld      (vR),a
                ld      a,(vC)          ; P9 = C*12 + 13
                ld      l,a
                ld      h,0
                add     hl,hl
                add     hl,hl
                ld      d,h
                ld      e,l
                add     hl,hl
                add     hl,de
                ld      de,13
                add     hl,de
                ld      (vP9),hl
extcell:
                ld      a,(vC)          ; PM(C,R) must be 0
                ld      l,a
                ld      h,0
                add     hl,hl
                ld      a,(vR)
                ld      b,a
                ld      de,20
extpm:
                or      a
                jr      z,extpm2
                add     hl,de
                dec     b
                ld      a,b
                jr      extpm
extpm2:
                ld      de,(pPM)
                add     hl,de
                ld      a,(hl)
                inc     hl
                or      (hl)
                jp      nz,extnext

                IFDEF SPRULES
                ; BZ(C,R) = 3 marks proven-empty water (sunk-ship halo or dead
                ; water).  The boat phase keeps zero-coverage cells in play, so
                ; without this test a salvo could waste shots on cells the
                ; buoys already disproved.  The classic build skips the test:
                ; its buoys only appear where coverage is already zero, and
                ; the verified reference explore never tested them.
                ld      a,(vC)
                ld      l,a
                ld      h,0
                add     hl,hl
                ld      a,(vR)
                or      a
                jr      z,extbz2
                ld      b,a
                ld      de,20
extbz1:
                add     hl,de
                djnz    extbz1
extbz2:
                ld      de,(pBZ)
                add     hl,de
                ld      a,(hl)
                cp      3
                jp      z,extnext
                ENDIF

                ld      hl,(vP9)        ; MO(P9) must not carry this turn's stamp
                ld      de,MOBUF
                add     hl,de
                ld      a,(vST)
                cp      (hl)
                jp      z,extnext

                ld      hl,(vP9)        ; SC = MC(P9)*8
                ld      de,MCBUF
                add     hl,de
                ld      l,(hl)
                ld      h,0
                add     hl,hl
                add     hl,hl
                add     hl,hl
                ld      a,(vC)          ; + ((C*5 + R*3 + RD) AND 7)
                ld      b,a
                add     a,a
                add     a,a
                add     a,b             ; C*5
                ld      b,a
                ld      a,(vR)
                ld      c,a
                add     a,a
                add     a,c             ; R*3
                add     a,b
                ld      b,a
                ld      a,(vRD)
                add     a,b
                and     7
                ld      e,a
                ld      d,0
                add     hl,de
                ld      a,(vRIM)        ; rim bonuses: the random personality
                ld      b,a             ; and the learned habit share one test
                ld      a,(SMEMB)
                or      b
                jr      z,extsc
                ld      a,(vC)
                or      a
                jr      z,extrim
                cp      9
                jr      z,extrim
                ld      a,(vR)
                or      a
                jr      z,extrim
                cp      9
                jr      nz,extsc
extrim:
                ld      a,b             ; +192 when the personality rolled rim
                or      a
                jr      z,extmem
                ld      de,192
                add     hl,de
extmem:
                ld      a,(SMEMB)       ; +64 when the habit was learned
                or      a
                jr      z,extsc
                ld      de,64
                add     hl,de
extsc:
                ld      de,(vBS)        ; keep the best.  BS starts at -1, so the
                ld      a,d             ; compare must be signed: bias both by
                xor     80h             ; 8000h and compare unsigned, as pickn does
                ld      d,a
                push    hl
                ld      a,h
                xor     80h
                ld      h,a
                or      a
                sbc     hl,de           ; SC' - BS'
                pop     hl
                jr      c,extnext       ; SC < BS
                jr      z,extnext       ; equal: keep the earlier cell
                ld      (vBS),hl
                ld      a,(vC)
                ld      (vBX),a
                ld      a,(vR)
                ld      (vBY),a
extnext:
                ld      hl,(vP9)
                inc     hl
                ld      (vP9),hl
                ld      hl,vR
                inc     (hl)
                ld      a,(hl)
                cp      10
                jp      c,extcell
                ld      hl,vC
                inc     (hl)
                ld      a,(hl)
                cp      10
                jp      c,extcol

                ld      a,(vT)          ; TX(T) = BX, TY(T) = BY
                ld      hl,(pTX)
                call    elptr
                ld      a,(vBX)
                ld      (hl),a
                inc     hl
                ld      (hl),0
                ld      a,(vT)
                ld      hl,(pTY)
                call    elptr
                ld      a,(vBY)
                ld      (hl),a
                inc     hl
                ld      (hl),0
                ld      a,(vBX)         ; stamp MO(BX*12 + BY + 13)
                ld      l,a
                ld      h,0
                add     hl,hl
                add     hl,hl
                ld      d,h
                ld      e,l
                add     hl,hl
                add     hl,de
                ld      a,(vBY)
                ld      e,a
                ld      d,0
                add     hl,de
                ld      de,13+MOBUF
                add     hl,de
                ld      a,(vST)
                ld      (hl),a
                ld      hl,vT
                inc     (hl)
                ld      a,(hl)
                ld      hl,vNF
                cp      (hl)
                jp      c,extshot
                ret

; ------------------------------------------------- USR4: fallback marginals
; Replaces BASIC 4040-4046.  When joint sampling produced nothing, every
; surviving candidate contributes weight 2880/CC(K) to the cells it covers,
; so the shot choice still follows the posterior instead of guessing.
marg:
                call    setptrs
                ld      a,1
                ld      (vMODE),a
                ld      a,1
                ld      (vK),a
mgship:
                ld      a,(vK)          ; weight = 2880 / CC(K), at least 1
                ld      hl,(pCC)
                call    elptr
                ld      c,(hl)
                inc     hl
                ld      b,(hl)
                ld      a,b             ; no candidates left: nothing to weight
                or      c
                jr      z,mgnext
                ld      hl,2880
                call    div16
                ld      a,h
                or      l
                jr      nz,mgok
                ld      hl,1
mgok:
                ld      (vWT),hl
                call    scan
mgnext:
                ld      hl,vK
                inc     (hl)
                ld      a,(hl)
                cp      NSHIPS+1
                jr      c,mgship
                xor     a
                ld      (vMODE),a
                ret

; HL = HL / BC   (BC small and positive)
div16:
                ld      de,0
div16lp:
                or      a
                sbc     hl,bc
                jr      c,div16d
                inc     de
                jr      div16lp
div16d:
                ex      de,hl
                ret

; ---------------------------------------------------------------- scan a ship
scan:
                ld      a,(vK)
                ld      hl,(pSZ)
                call    getel
                ld      (vLK),a
                ld      b,a
                ld      a,11
                sub     b
                ld      (vW),a

                ld      a,(vK)
                ld      hl,(pOS)
                call    getel16
                ld      hl,FABUF
                add     hl,de
                ld      (vFAP),hl

; --- across: Y outer 0..9, X inner 0..W-1, index starts at 13, +12 per X
                ld      hl,12
                ld      (vSTEP),hl
                ld      de,13
                ld      c,10
sacross:
                ld      a,(vW)
                ld      b,a
                push    de
sacell:
                push    bc
                push    de
                call    cand
                pop     de
                ld      hl,12
                add     hl,de
                ex      de,hl
                pop     bc
                djnz    sacell
                pop     de
                inc     de              ; same X=0 column, next Y
                dec     c
                jr      nz,sacross

; --- down: X outer 0..9, Y inner 0..W-1, index starts at 13, +1 per Y
                ld      hl,1
                ld      (vSTEP),hl
                ld      de,13
                ld      c,10
sdown:
                ld      a,(vW)
                ld      b,a
                push    de
sdcell:
                push    bc
                push    de
                call    cand
                pop     de
                inc     de
                pop     bc
                djnz    sdcell
                pop     de
                ld      hl,12
                add     hl,de           ; next X column
                ex      de,hl
                dec     c
                jr      nz,sdown
                ret

; ---------------------------------------------------------------- candidate
; DE = padded index of its first cell; vFAP -> FA(I); vSTEP = stride
cand:
                ld      hl,(vFAP)
                ld      a,(hl)
                or      a
                jp      z,cdone
                ld      a,(vMODE)
                IFNDEF SPRULES
                cp      2
                jr      z,candn1
                ENDIF
                or      a
                jr      nz,candmg

                ld      (vIDX),de
                ld      hl,(pMAP)
                add     hl,de
                ld      de,(vSTEP)
                ld      a,(vLK)
                ld      b,a
                xor     a
covsum:
                add     a,(hl)
                add     hl,de
                djnz    covsum
                ld      hl,vH
                cp      (hl)
                jr      z,cdone

                ld      hl,(vFAP)       ; kill it
                ld      (hl),0
                ld      a,(vK)
                ld      hl,(pCC)
                call    elptr
                ld      a,(hl)
                sub     1
                ld      (hl),a
                inc     hl
                ld      a,(hl)
                sbc     a,0
                ld      (hl),a
                ld      de,(vIDX)
                ld      hl,MCBUF
                add     hl,de
                ld      de,(vSTEP)
                ld      a,(vLK)
                ld      b,a
mcloop:
                dec     (hl)
                add     hl,de
                djnz    mcloop
                jp      cdone

; probe support: count live candidates covering each cell, as bytes in MO
                IFNDEF SPRULES
candn1:
                ld      hl,MOBUF
                add     hl,de
                ld      de,(vSTEP)
                ld      a,(vLK)
                ld      b,a
n1cell:
                inc     (hl)
                add     hl,de
                djnz    n1cell
                jp      cdone
                ENDIF

; marginals: add the ship's weight to each covered cell that is still scoreable
candmg:
                ld      hl,(pMAP)       ; pMAP is MG
                add     hl,de
                add     hl,de
                ld      de,(vSTEP)
                sla     e
                rl      d
                ld      a,(vLK)
                ld      b,a
mgcell:
                ld      a,(hl)
                inc     hl
                ld      a,(hl)
                dec     hl
                rla                     ; negative cells are off limits
                jr      c,mgskip
                push    de
                ld      e,(hl)
                inc     hl
                ld      d,(hl)
                dec     hl
                push    hl
                ld      hl,(vWT)
                add     hl,de
                ex      de,hl
                pop     hl
                ld      (hl),e
                inc     hl
                ld      (hl),d
                dec     hl
                pop     de
mgskip:
                add     hl,de
                djnz    mgcell
cdone:
                ld      hl,(vFAP)
                inc     hl
                ld      (vFAP),hl
                ret

; ------------------------------------------------- USR7: reset the candidates
; Game-start state in one call: every candidate alive, the stamp plane
; virgin and the stamp counter at zero (0 never matches a bumped stamp).
fainit:
                ld      hl,FABUF
                ld      de,FABUF+1
                ld      bc,FASIZE-1
                ld      (hl),1
                ldir
                ld      hl,MCBUF
                ld      de,MCBUF+1
                ld      bc,143
                ld      (hl),0
                ldir
                call    clrmo
                xor     a
                ld      (vST),a
                ld      (vKL),a
                ld      (vRK),a
                ret

                IFNDEF SPRULES
; --------------------------------------------- USR8: probe + explore salvo
; The owner's kill discipline, twin-verified at z=+8.0/+7.8/+3.9 over
; 24,000 paired boards: located wounded ships are harvested (weight 25000),
; each still-ambiguous wounded ship gets ONE probe at the cell splitting
; its candidate set closest to half (weight 12000), and everything else in
; MG holds plain explore scores (MC*8 + jitter) so pickn spends the salvo
; surplus scouting fresh water instead of piling onto one hypothesis chain.
probesel:
                call    setptrs
                call    mgseedmc
                ld      a,1
                ld      (vK),a
psship:
                ld      a,(vK)
                ld      hl,(pPH)
                call    getel
                or      a
                jp      z,psnext
                ld      b,a
                ld      a,(vK)
                ld      hl,(pSZ)
                call    getel
                cp      b
                jp      z,psnext
                ld      a,(vK)
                ld      hl,(pCC)
                call    getel16
                ld      (vCCK),de
                ld      a,d
                or      a
                jr      nz,psprobe
                ld      a,e
                cp      1
                jr      nz,psprobe
                ld      a,1
                ld      (vMODE),a
                ld      hl,25000
                ld      (vWT),hl
                call    scan
                xor     a
                ld      (vMODE),a
                jp      psnext
psprobe:
                call    clrmo
                ld      a,2
                ld      (vMODE),a
                call    scan
                xor     a
                ld      (vMODE),a
                ld      hl,-1
                ld      (vBS),hl
                ld      hl,13
                ld      (vP9),hl
pscell:
                ld      hl,(vP9)
                add     hl,hl
                ld      de,(pMAP)
                add     hl,de
                inc     hl
                ld      a,(hl)
                rla
                jr      c,pscnext
                ld      hl,(vP9)
                ld      de,MOBUF
                add     hl,de
                ld      a,(hl)
                or      a
                jr      z,pscnext
                add     a,a
                ld      l,a
                ld      h,0
                ld      de,(vCCK)
                or      a
                sbc     hl,de
                jr      nc,psabs
                ld      a,l
                cpl
                ld      l,a
                ld      a,h
                cpl
                ld      h,a
                inc     hl
psabs:
                ld      b,h
                ld      c,l
                ld      hl,(vBS)
                or      a
                sbc     hl,bc
                jr      c,pscnext
                jr      z,pscnext
                ld      h,b
                ld      l,c
                ld      (vBS),hl
                ld      hl,(vP9)
                ld      (vBXW),hl
pscnext:
                ld      hl,(vP9)
                inc     hl
                ld      (vP9),hl
                ld      de,131
                or      a
                sbc     hl,de
                jr      nz,pscell
                ld      hl,(vBS)
                ld      a,h
                and     l
                inc     a
                jr      z,psnext
                ld      hl,(vBXW)
                add     hl,hl
                ld      de,(pMAP)
                add     hl,de
                ld      e,(hl)
                inc     hl
                ld      d,(hl)
                push    hl
                ld      hl,12000
                add     hl,de
                ex      de,hl
                pop     hl
                ld      (hl),d
                dec     hl
                ld      (hl),e
psnext:
                ld      hl,vK
                inc     (hl)
                ld      a,(hl)
                cp      NSHIPS+1
                jp      c,psship
                ret

; MG := plain explore scores: -1 on fired cells, MC*8 + jitter on live ones
mgseedmc:
                ld      hl,(pMAP)
                ld      b,144
mm0:
                ld      (hl),0FFh
                inc     hl
                ld      (hl),0FFh
                inc     hl
                djnz    mm0
                call    rnd16
                ld      a,l
                and     7
                ld      (vRDS),a
                xor     a
                ld      (vC),a
mmc:
                xor     a
                ld      (vR),a
mmr:
                ld      a,(vC)
                ld      l,a
                ld      h,0
                add     hl,hl
                ld      a,(vR)
                or      a
                jr      z,mmp2
                ld      b,a
                ld      de,20
mmp1:
                add     hl,de
                djnz    mmp1
mmp2:
                ld      de,(pPM)
                add     hl,de
                ld      a,(hl)
                inc     hl
                or      (hl)
                jr      nz,mmnext
                call    padidx
                push    hl
                ld      de,MCBUF
                add     hl,de
                ld      l,(hl)
                ld      h,0
                add     hl,hl
                add     hl,hl
                add     hl,hl
                ld      a,(vC)
                ld      b,a
                add     a,a
                add     a,a
                add     a,b
                ld      c,a
                ld      a,(vR)
                ld      b,a
                add     a,a
                add     a,b
                add     a,c
                ld      b,a
                ld      a,(vRDS)
                add     a,b
                and     7
                ld      e,a
                ld      d,0
                add     hl,de
                ex      de,hl
                pop     hl
                add     hl,hl
                push    de
                ld      de,(pMAP)
                add     hl,de
                pop     de
                ld      (hl),e
                inc     hl
                ld      (hl),d
mmnext:
                ld      hl,vR
                inc     (hl)
                ld      a,(hl)
                cp      10
                jp      c,mmr
                ld      hl,vC
                inc     (hl)
                ld      a,(hl)
                cp      10
                jp      c,mmc
                ret
                ENDIF

; ---------------------------------------------------------------- helpers
elptr:
                ld      e,a
                ld      d,0
                sla     e
                rl      d
                add     hl,de
                ret

getel:
                call    elptr
                ld      a,(hl)
                ret

getel16:
                call    elptr
                ld      e,(hl)
                inc     hl
                ld      d,(hl)
                ret

; HL = MAP + (D+1)*12 + (E+1)
mapptr:
                ld      a,d
                inc     a
                ld      l,a
                ld      h,0
                add     hl,hl
                add     hl,hl
                ld      b,h
                ld      c,l
                add     hl,hl
                add     hl,bc
                ld      a,e
                inc     a
                ld      c,a
                ld      b,0
                add     hl,bc
                ld      bc,(pMAP)
                add     hl,bc
                ret

end:

                include "sampler.inc"

