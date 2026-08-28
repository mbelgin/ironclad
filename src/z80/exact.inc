; ------------------------------------------------------- exact joint counts
; When the product of the ships' candidate counts is small, Monte-Carlo
; sampling is replaced by exact enumeration: a depth-first search over every
; consistent no-touch joint placement of all five ships.  MG receives, for
; every unfired cell, 8x the number of completions covering it plus the usual
; 0..7 jitter; fired cells get -1.  pickn then turns MG into shots exactly as
; it does for the sampler, so a caller's only job is to try exact first.
;
; Returns carry SET when it declined (candidate space too big, node budget
; blown, or no completion) - the caller falls back to its old path.  MG is
; only defined on carry clear; every fallback rebuilds it from scratch.
;
; The halo map borrows MO's storage: each cell's low byte holds the halo
; count, and the high byte is forced to 80h first, so no leftover value can
; ever equal a sampler stamp (vST stays far below 8000h).
;
; Twin: class Exact in tools/smart.py, measured at the caps below (z=5.4 on
; edge fleets, z=1.8 on uniform, n=1500 paired boards).

EPRODCAP        equ     3500
ENODECAP        equ     12000

exact:
                call    setptrs
                ld      hl,1            ; prod of CC(1..5) <= EPRODCAP ?
                ld      a,1
exprod:
                push    af
                push    hl
                ld      hl,(pCC)
                call    elptr
                ld      c,(hl)
                inc     hl
                ld      b,(hl)
                pop     hl
                ld      a,b
                or      a
                jr      nz,exfailp
                call    mul16c
                jr      c,exfailp
                ld      de,EPRODCAP+1
                push    hl
                or      a
                sbc     hl,de
                pop     hl
                jr      nc,exfailp
                pop     af
                inc     a
                cp      6
                jr      c,exprod
                jr      exsort
exfailp:
                pop     af
                scf
                ret

exsort:
                call    sortso          ; vSOA is eORD: same order, same slots

                ld      hl,(pMO)        ; halo map: count in low, 80h in high
                ld      b,144
exclr:
                ld      (hl),0
                inc     hl
                ld      (hl),80h
                inc     hl
                djnz    exclr
                ld      hl,(pMAP)       ; MG as the 16-bit count accumulator
                ld      b,144
exclr2:
                ld      (hl),0
                inc     hl
                ld      (hl),0
                inc     hl
                djnz    exclr2
                ld      hl,0
                ld      (eTOT),hl
                ld      (eNODE),hl

                xor     a               ; ------------- iterative DFS
                ld      (eLVL),a
exdesc:
                call    exship          ; vK/vLK/vW for eORD[eLVL]
                ld      a,(vK)
                ld      hl,(pOS)
                call    getel16         ; DE = OS(K)
                push    de
                ld      a,(vK)
                call    ctof            ; HL = CT(K)
                pop     de
                add     hl,de
                push    hl              ; OS+CT
                call    exitp           ; HL -> it slot for this level
                pop     bc
                dec     de              ; it = OS-1 (pre-increment scan)
                ld      (hl),e
                inc     hl
                ld      (hl),d
                inc     hl
                ld      (hl),c          ; end bound stored beside it
                inc     hl
                ld      (hl),b
exnext:
                call    exship
                call    exitp
                ld      e,(hl)
                inc     hl
                ld      d,(hl)
                inc     de              ; ++it
                ld      (hl),d
                dec     hl
                ld      (hl),e
                inc     hl
                inc     hl
                ld      a,(hl)          ; BC = end bound
                inc     hl
                ld      h,(hl)
                ld      l,a
                or      a
                sbc     hl,de
                jp      z,exup          ; exhausted this level
                ld      hl,FABUF        ; FA(it) alive?
                add     hl,de
                ld      a,(hl)
                or      a
                jp      z,exnext
                ld      hl,(eNODE)      ; node budget
                inc     hl
                ld      (eNODE),hl
                push    de
                ld      de,ENODECAP
                or      a
                sbc     hl,de
                pop     de
                jr      nc,exabort
                ld      a,(vK)          ; J0 = it - OS(K), fits in 8 bits
                push    de
                ld      hl,(pOS)
                call    getel16
                pop     hl
                or      a
                sbc     hl,de
                ld      a,l
                ld      (vJ0),a
                call    decode          ; -> vIBB, vS9
                ld      a,(vLK)         ; conflict against the halo map?
                ld      b,a
                ld      hl,(vIBB)
                add     hl,hl
                ld      de,(pMO)
                add     hl,de
                ld      de,(vS9)
                sla     e
                rl      d
excf:
                ld      a,(hl)
                or      a
                jp      nz,exnext
                add     hl,de
                djnz    excf
                call    explace
                ld      hl,eLVL
                inc     (hl)
                ld      a,(hl)
                cp      5
                jp      c,exdesc
                ld      hl,(eTOT)       ; -------- leaf: a complete fleet
                inc     hl
                ld      (eTOT),hl
                ld      hl,eCELLS
                ld      b,25
exleaf:
                ld      e,(hl)
                ld      a,e
                inc     a
                jr      z,exlnext       ; 0FFh pad slot
                ld      d,0
                push    hl
                ld      hl,(pMAP)
                add     hl,de
                add     hl,de
                inc     (hl)
                jr      nz,exlpop
                inc     hl
                inc     (hl)
exlpop:
                pop     hl
exlnext:
                inc     hl
                djnz    exleaf
                ld      hl,eLVL
                dec     (hl)
                call    exunplace
                jp      exnext
exup:
                ld      a,(eLVL)
                or      a
                jr      z,exfin
                ld      hl,eLVL
                dec     (hl)
                call    exunplace
                jp      exnext
exabort:
                scf
                ret
exfin:
                ld      hl,(eTOT)
                ld      a,h
                or      l
                jr      nz,exmg
                scf
                ret

exmg:                                   ; MG = count*8 + jitter; fired = -1
                xor     a
                ld      (vC),a
exmgc:
                xor     a
                ld      (vR),a
exmgr:
                ld      a,(vC)          ; PM(C,R) fired?
                ld      l,a
                ld      h,0
                add     hl,hl
                ld      a,(vR)
                or      a
                jr      z,exmp2
                ld      b,a
                ld      de,20
exmp1:
                add     hl,de
                djnz    exmp1
exmp2:
                ld      de,(pPM)
                add     hl,de
                ld      a,(hl)
                inc     hl
                or      (hl)
                push    af
                call    padidx          ; HL = padded index of (C,R)
                add     hl,hl
                ld      de,(pMAP)
                add     hl,de
                pop     af
                jr      z,exmg1
                ld      (hl),0FFh       ; fired: -1
                inc     hl
                ld      (hl),0FFh
                jr      exmg2
exmg1:
                ld      e,(hl)
                inc     hl
                ld      d,(hl)
                dec     hl
                push    hl
                ex      de,hl
                add     hl,hl
                add     hl,hl
                add     hl,hl           ; count*8: count <= 3500, no overflow
                push    hl
                call    rnd16
                ld      a,l
                and     7
                pop     hl
                ld      e,a
                ld      d,0
                add     hl,de
                ex      de,hl
                pop     hl
                ld      (hl),e
                inc     hl
                ld      (hl),d
exmg2:
                ld      hl,vR
                inc     (hl)
                ld      a,(hl)
                cp      10
                jp      c,exmgr
                ld      hl,vC
                inc     (hl)
                ld      a,(hl)
                cp      10
                jp      c,exmgc
                or      a               ; success
                ret

; vK/vLK/vW from the ship at the current DFS level
exship:
                ld      a,(eLVL)
                ld      e,a
                ld      d,0
                ld      hl,eORD
                add     hl,de
                ld      a,(hl)
                ld      (vK),a
                ld      hl,(pSZ)
                call    getel
                ld      (vLK),a
                ld      b,a
                ld      a,11
                sub     b
                ld      (vW),a
                ret

; HL -> the current level's (it, end) quad in eIT
exitp:
                ld      a,(eLVL)
                add     a,a
                add     a,a             ; 4 bytes per level
                ld      e,a
                ld      d,0
                ld      hl,eIT
                add     hl,de
                ret

; record the candidate's cells at this level and raise their halos in MO
explace:
                ld      a,(eLVL)
                add     a,a
                add     a,a
                ld      e,a
                ld      a,(eLVL)
                add     a,e             ; *5
                ld      e,a
                ld      d,0
                ld      hl,eCELLS
                add     hl,de
                ex      de,hl           ; DE -> this level's five slots
                ld      a,(vLK)
                ld      b,a
                ld      hl,(vIBB)
explc:
                ld      a,l             ; padded idx 13..130 fits a byte
                ld      (de),a
                inc     de
                push    hl
                push    de
                push    bc
                add     hl,hl           ; MO is a word array
                ld      de,(pMO)
                add     hl,de
                ld      de,-26          ; up-left corner of the 3x3 block
                add     hl,de
                ld      b,3
exph1:
                inc     (hl)
                inc     hl
                inc     hl
                inc     (hl)
                inc     hl
                inc     hl
                inc     (hl)
                ld      de,20           ; to the next padded row
                add     hl,de
                djnz    exph1
                pop     bc
                pop     de
                pop     hl
                push    de
                ld      de,(vS9)
                add     hl,de
                pop     de
                djnz    explc
                ld      a,(vLK)         ; 0FFh-pad the unused slots
                ld      c,a
                ld      a,5
                sub     c
                ret     z
                ld      b,a
                ld      a,0FFh
expad:
                ld      (de),a
                inc     de
                djnz    expad
                ret

; inverse of explace for the current level
exunplace:
                ld      a,(eLVL)
                add     a,a
                add     a,a
                ld      e,a
                ld      a,(eLVL)
                add     a,e
                ld      e,a
                ld      d,0
                ld      hl,eCELLS
                add     hl,de
                ld      b,5
exun1:
                ld      e,(hl)
                ld      a,e
                inc     a
                jr      z,exun3
                push    hl
                push    bc
                ld      d,0
                ex      de,hl
                add     hl,hl
                ld      de,(pMO)
                add     hl,de
                ld      de,-26
                add     hl,de
                ld      b,3
exun2:
                dec     (hl)
                inc     hl
                inc     hl
                dec     (hl)
                inc     hl
                inc     hl
                dec     (hl)
                ld      de,20
                add     hl,de
                djnz    exun2
                pop     bc
                pop     hl
exun3:
                inc     hl
                djnz    exun1
                ret

; A = ship -> HL = CT(ship) = 20*(11-SZ); preserves DE
ctof:
                push    de
                ld      hl,(pSZ)
                call    getel
                ld      b,a
                ld      a,11
                sub     b
                ld      l,a
                ld      h,0
                add     hl,hl
                add     hl,hl           ; *4
                ld      e,l
                ld      d,h
                add     hl,hl
                add     hl,hl           ; *16
                add     hl,de           ; *20
                pop     de
                ret

; HL = HL * C, carry set on 16-bit overflow
mul16c:
                ld      de,0
                ld      b,8
mul16l:
                srl     c
                jr      nc,mul16s
                ex      de,hl
                add     hl,de
                ex      de,hl
                jr      c,mul16o
mul16s:
                add     hl,hl
                jr      nc,mul16n
                ld      a,c             ; shifted-out bit only matters if C
                or      a               ; still has bits to consume
                jr      nz,mul16o
mul16n:
                djnz    mul16l
                ex      de,hl
                or      a
                ret
mul16o:
                scf
                ret
