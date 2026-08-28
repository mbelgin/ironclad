; ------------------------------------------------------- USR5: joint sampler
; Replaces BASIC 4003-4046.  Draws up to six joint placements of the whole
; surviving fleet, each one a legal non-touching arrangement, and scores MG by
; how often a cell is covered.  When no arrangement can be found it falls back
; to the per-ship marginals so the shot still follows the posterior.
sample:
                call    setptrs
                call    sortso
                call    mgseed
                xor     a
                ld      (vGG),a
                ld      a,6
                ld      (vSA),a
smploop:
                ld      a,(vGG)
                cp      3
                jr      nc,smpend
                call    onesamp
                ld      hl,vSA
                dec     (hl)
                jr      nz,smploop
smpend:
                ld      a,(vGG)
                cp      3
                ret     nc
                jp      marg            ; fewer than three samples: lay the
                                        ; marginal floor underneath so a live
                                        ; candidate cell can never lose to
                                        ; open-water jitter on a one-sample
                                        ; lottery (the pure_bug.png defect,
                                        ; inherited from v1.0)

; One sample only, leaving vZX/vQNC/vGG for the legality harness to inspect.
samp1:
                call    setptrs
                call    sortso
                jp      onesamp

; --- SO[0..NSHIPS-1] = ship indices ordered by ascending candidate count
sortso:
                ld      hl,vSOA
                ld      a,1
                ld      b,NSHIPS
ss0:
                ld      (hl),a
                inc     hl
                inc     a
                djnz    ss0
                xor     a
                ld      (vSI),a
ssi:
                ld      a,(vSI)
                inc     a
                ld      (vSJ),a
ssj:
                ld      a,(vSJ)
                cp      NSHIPS
                jr      nc,ssinext
                ld      a,(vSJ)
                call    ccof
                ld      (vSCJ),hl
                ld      a,(vSI)
                call    ccof
                ex      de,hl
                ld      hl,(vSCJ)
                or      a
                sbc     hl,de
                jr      nc,ssjnext
                ld      a,(vSI)         ; swap the two slots
                ld      e,a
                ld      d,0
                ld      hl,vSOA
                add     hl,de
                push    hl
                ld      a,(vSJ)
                ld      e,a
                ld      d,0
                ld      hl,vSOA
                add     hl,de
                pop     de
                ld      a,(de)
                ld      c,(hl)
                ld      (hl),a
                ld      a,c
                ld      (de),a
ssjnext:
                ld      hl,vSJ
                inc     (hl)
                jr      ssj
ssinext:
                ld      hl,vSI
                inc     (hl)
                ld      a,(hl)
                cp      NSHIPS-1
                jr      c,ssi
                ret

; A = slot index -> HL = CC(SO[A])
ccof:
                ld      e,a
                ld      d,0
                ld      hl,vSOA
                add     hl,de
                ld      a,(hl)
                ld      hl,(pCC)
                call    getel16
                ex      de,hl
                ret

; --- MG = -1 everywhere, then a small jitter on every cell not yet fired at
mgseed:
                ld      hl,(pMAP)
                ld      b,144
mgs0:
                ld      (hl),0FFh
                inc     hl
                ld      (hl),0FFh
                inc     hl
                djnz    mgs0
                call    rnd16
                ld      a,l
                and     7
                ld      (vRDS),a
                xor     a
                ld      (vC),a
mgsc:
                xor     a
                ld      (vR),a
mgsr:
                ld      a,(vC)
                ld      l,a
                ld      h,0
                add     hl,hl
                ld      a,(vR)
                or      a
                jr      z,mgsp2
                ld      b,a
                ld      de,20
mgsp1:
                add     hl,de
                djnz    mgsp1
mgsp2:
                ld      de,(pPM)
                add     hl,de
                ld      a,(hl)
                inc     hl
                or      (hl)
                jr      nz,mgsnext
                ld      a,(vC)          ; jitter = (C*5 + R*3 + RD) and 7
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
                ld      c,a
                call    padidx
                add     hl,hl
                ld      de,(pMAP)
                add     hl,de
                ld      (hl),c
                inc     hl
                ld      (hl),0
mgsnext:
                ld      hl,vR
                inc     (hl)
                ld      a,(hl)
                cp      10
                jp      c,mgsr
                ld      hl,vC
                inc     (hl)
                ld      a,(hl)
                cp      10
                jp      c,mgsc
                ret

; HL = padded index of (vC,vR) = C*12 + R + 13
padidx:
                ld      a,(vC)
                ld      l,a
                ld      h,0
                add     hl,hl
                add     hl,hl
                ld      d,h
                ld      e,l
                add     hl,hl
                add     hl,de
                ld      a,(vR)
                ld      e,a
                ld      d,0
                add     hl,de
                ld      de,13
                add     hl,de
                ret

; --- one joint sample: place every ship, then credit the cells it covered
onesamp:
                xor     a
                ld      (vQNC),a
                call    bumpst
                ld      a,NSHIPS
                ld      (vO2),a
                ld      hl,vSOA
                ld      (vSOP),hl
osship:
                ld      hl,(vSOP)
                ld      a,(hl)
                ld      (vK),a
                call    place
                ret     c
                ld      hl,(vSOP)
                inc     hl
                ld      (vSOP),hl
                ld      hl,vO2
                dec     (hl)
                jr      nz,osship
                ld      hl,vGG
                inc     (hl)
                ld      a,(vQNC)        ; every sampled cell gains 16
                or      a
                ret     z
                ld      b,a
                ld      hl,vZX
osadd:
                push    bc
                ld      e,(hl)
                inc     hl
                ld      d,(hl)
                inc     hl
                push    hl
                ex      de,hl
                add     hl,hl
                ld      de,(pMAP)
                add     hl,de
                inc     hl
                ld      a,(hl)
                dec     hl
                rla                     ; dead water stays out of it
                jr      c,osskip
                ld      a,(hl)
                add     a,16
                ld      (hl),a
                inc     hl
                ld      a,(hl)
                adc     a,0
                ld      (hl),a
osskip:
                pop     hl
                pop     bc
                djnz    osadd
                ret

; --- place ship vK; carry set if eight attempts all failed
place:
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
                ld      (vOSK),de

                ld      a,8
                ld      (vT2),a
platt:
                call    pldraw          ; vJ0 <- uniform over LIVE candidates
                jr      c,plnext        ; none left for this ship
                call    decode          ; vJ0 -> vIBB, vS9
; When THIS GAME's located ships prove a rim-heavy layout (vRK, computed by
; BASIC from PD/PH each kill turn - within-game evidence, not the cross-game
; habit), the kill posterior should believe it:
; a drawn candidate that does not touch the rim gets up to two biased
; redraws, each preferring a live rim candidate and keeping the original
; when none turns up.  Measured (tools twin, 2000 paired boards): -1.95
; salvos vs a rim-heavy placer (z=20.9), -0.23 when misapplied (z=-3.8);
; the SMEMB gate makes the second case rare.
                ld      a,(vRK)
                or      a
                jr      z,plcoll
                call    rimchk
                jr      z,plcoll        ; already on the rim: accept
                ld      a,(vJ0)
                ld      (vJ0F),a        ; remember the first live candidate
                ld      a,2
                ld      (vRDL),a
plrdo:
                call    pldraw          ; a redraw always finds a live one now
                jr      c,plrgive
                call    decode
                call    rimchk
                jr      z,plcoll        ; a rim candidate: take it
                ld      hl,vRDL
                dec     (hl)
                jr      nz,plrdo
plrgive:
                ld      a,(vJ0F)        ; keep the first candidate
                ld      (vJ0),a
                call    decode
plcoll:
                ld      a,(vLK)         ; does it touch anything placed already?
                ld      b,a
                ld      hl,(vIBB)
                ld      de,MOBUF
                add     hl,de
                ld      a,(vST)
plcf:
                cp      (hl)
                jr      z,plnext
                ld      de,(vS9)
                add     hl,de
                djnz    plcf
                jr      plok
plnext:
                ld      hl,vT2
                dec     (hl)
                jp      nz,platt
                scf
                ret
plok:
                ld      a,(vLK)         ; record the cells this ship covers
                ld      b,a
                ld      hl,(vIBB)
                ld      (vP9),hl
                ld      a,(vQNC)
                ld      e,a
                ld      d,0
                ld      hl,vZX
                add     hl,de
                add     hl,de
                ex      de,hl           ; DE -> ZX slot
plrec:
                ld      hl,(vP9)
                ex      de,hl
                ld      (hl),e
                inc     hl
                ld      (hl),d
                inc     hl
                ex      de,hl
                push    bc              ; BC is the cell counter
                ld      bc,(vS9)
                add     hl,bc
                pop     bc
                ld      (vP9),hl
                ld      hl,vQNC
                inc     (hl)
                djnz    plrec

                ld      hl,13           ; W2 = 13 - S9: the sideways neighbour
                ld      bc,(vS9)
                or      a
                sbc     hl,bc
                ld      (vW2),hl
                ld      hl,(vIBB)       ; stamp from IB - S9 for LK + 2 cells
                or      a
                sbc     hl,bc
                ld      de,MOBUF
                add     hl,de
                ld      a,(vLK)
                add     a,2
                ld      b,a
                ld      a,(vST)
                ld      c,a             ; the stamp, kept at hand
plstamp:
                ld      (hl),c
                push    hl
                ld      de,(vW2)
                or      a
                sbc     hl,de
                ld      (hl),c
                pop     hl
                push    hl
                ld      de,(vW2)
                add     hl,de
                ld      (hl),c
                pop     hl
                ld      de,(vS9)
                add     hl,de
                djnz    plstamp
                or      a
                ret

; Uniform draw over ship vK's LIVE candidates: r in [0, CC) then a count
; scan of the FA flags to the r-th live one.  Never fails while a candidate
; survives (carry set only when CC=0).  This replaced 24-probe rejection
; over the full slot space, whose ~18% late-game success rate starved the
; joint sampler; twin-measured worth z=+6.2 vs edge fleets.  CC is trusted
; to equal the live-flag count - the fold maintains it and the checksum
; suites verify it.
pldraw:
                ld      a,(vK)
                ld      hl,(pCC)
                call    getel16         ; DE = CC(K)
                ld      a,d
                or      e
                jr      nz,pld1
                scf
                ret
pld1:
                ld      c,e             ; CC <= 180 fits a byte
pldr:
                call    rnd16
                ld      a,l
                cp      c
                jr      nc,pldr         ; r uniform in [0, CC)
                inc     a
                ld      b,a             ; stop at the (r+1)-th live flag
                ld      hl,(vOSK)
                ld      de,FABUF
                add     hl,de
pldscan:
                ld      a,(hl)
                or      a
                jr      z,pldnx
                dec     b
                jr      z,pldhit
pldnx:
                inc     hl
                jr      pldscan
pldhit:
                ld      de,FABUF        ; index = ptr - FABUF - OS(K)
                or      a
                sbc     hl,de
                ld      de,(vOSK)
                or      a
                sbc     hl,de
                ld      a,l
                ld      (vJ0),a
                or      a
                ret

; vJ0 (candidate offset within the ship) -> vIBB padded index, vS9 stride
decode:
                ld      a,(vW)
                ld      b,a
                add     a,a
                add     a,a
                add     a,a
                add     a,b
                add     a,b             ; 10*W
                ld      c,a
                ld      a,(vJ0)
                cp      c
                jr      nc,decdown
                ld      a,(vW)          ; across: Y = J0/W, X = J0-Y*W
                ld      c,a
                ld      a,(vJ0)
                ld      l,a
                ld      h,0
                call    divsm
                ld      a,l
                ld      (vR),a          ; Y
                ld      a,e
                ld      (vC),a          ; X
                ld      hl,12
                ld      (vS9),hl
                jr      decfin
decdown:
                sub     c               ; down: X = J/W, Y = J-X*W
                ld      l,a
                ld      h,0
                ld      a,(vW)
                ld      c,a
                call    divsm
                ld      a,l
                ld      (vC),a          ; X
                ld      a,e
                ld      (vR),a          ; Y
                ld      hl,1
                ld      (vS9),hl
decfin:
                call    padidx
                ld      (vIBB),hl
                ret

; HL (< 256) / C -> HL quotient, E remainder
divsm:
                ld      b,0
dv1:
                ld      a,l
                sub     c
                jr      c,dv2
                ld      l,a
                inc     b
                jr      dv1
dv2:
                ld      e,l
                ld      l,b
                ld      h,0
                ret

; Z set if the decoded candidate (vC,vR,vS9,vLK) touches the board rim.
; Across (S9=12): cells (C..C+LK-1, R) - rim iff R=0, R=9, C=0 or C+LK-1=9.
; Down: the same test with C and R swapped.
rimchk:
                ld      a,(vS9)
                cp      12
                ld      a,(vC)
                ld      b,a
                ld      a,(vR)
                jr      z,rck1
                ld      c,a             ; down: swap main/cross
                ld      a,b
                ld      b,c
rck1:                                   ; A = cross axis, B = main axis
                or      a
                ret     z
                cp      9
                ret     z
                ld      a,b
                or      a
                ret     z
                ld      c,a
                ld      a,(vLK)
                add     a,c
                cp      10              ; main + LK - 1 = 9
                ret

; xorshift16 (7,9,8): full 16-bit mix per call, period 65535
rnd16:
                ld      hl,(vSEED)
                ld      a,h
                or      l
                jr      nz,rnz
                ld      hl,(0FC9Eh)
                ld      a,h
                or      l
                jr      nz,rnz
                ld      hl,0ACE1h
rnz:
                ld      d,l             ; x = x xor (x shl 7)
                ld      e,0
                srl     d
                rr      e
                ld      a,h
                xor     d
                ld      h,a
                ld      a,l
                xor     e
                ld      l,a
                ld      a,h             ; x = x xor (x shr 9)
                srl     a
                xor     l
                ld      l,a
                ld      a,l             ; x = x xor (x shl 8)
                xor     h
                ld      h,a
                ld      (vSEED),hl
                ret
