; Toolchain probe: prove sjasmplus -> BLOAD -> USR works before touching the game.
; Writes a signature and the doubled USR argument into the reserved area.
                org     0DA00h
start:
                ld      a,5Ah
                ld      (0DA80h),a          ; signature byte BASIC can PEEK
                ld      hl,(0F7F8h)         ; DAC+2: the integer USR argument
                add     hl,hl               ; double it
                ld      (0F7F8h),hl         ; hand it back as the USR result
                ld      a,2
                ld      (0F663h),a          ; VALTYP = integer
                ret
end:
