import re, sys
KW1 = """END FOR NEXT DATA INPUT DIM READ LET GOTO RUN IF RESTORE GOSUB RETURN REM STOP PRINT CLEAR LIST NEW ON WAIT DEF POKE CONT CSAVE CLOAD OUT LPRINT LLIST CLS WIDTH ELSE TRON TROFF SWAP ERASE ERROR RESUME DELETE AUTO RENUM DEFSTR DEFINT DEFSNG DEFDBL LINE OPEN FIELD GET PUT CLOSE LOAD MERGE FILES LSET RSET SAVE LFILES CIRCLE COLOR DRAW PAINT BEEP PLAY PSET PRESET SOUND SCREEN VPOKE SPRITE VDP BASE CALL TIME KEY MAX MOTOR BLOAD BSAVE DSKO$ SET NAME KILL IPL COPY CMD LOCATE TO THEN TAB STEP USR FN SPC NOT ERL ERR STRING$ USING INSTR VARPTR CSRLIN ATTR$ DSKI$ OFF INKEY$ POINT AND OR XOR EQV IMP MOD PAGE""".split()
KW2 = """LEFT$ RIGHT$ MID$ SGN INT ABS SQR RND SIN LOG EXP COS TAN ATN FRE INP POS LEN STR$ VAL ASC CHR$ PEEK VPEEK SPACE$ OCT$ HEX$ LPOS BIN$ CINT CSNG CDBL FIX STICK STRIG PDL PAD DSKF FPOS CVI CVS CVD EOF LOC LOF""".split()
kws = sorted(set(KW1+KW2), key=len, reverse=True)
def toksize(body):
    n=0; i=0; s=False
    while i < len(body):
        ch=body[i]
        if s:
            n+=1; i+=1
            if ch=='"': s=False
            continue
        if ch=='"': s=True; n+=1; i+=1; continue
        m=None
        for k in kws:
            if body.startswith(k,i):
                # avoid matching keyword inside identifier? MSX crunches greedily anyway
                m=k; break
        if m:
            n += 2 if m in KW2 or m=='ELSE' else 1
            i += len(m)
            if m=='REM': n += len(body)-i; break
            continue
        if ch.isdigit():
            j=i
            while j<len(body) and (body[j].isdigit() or body[j]=='.'): j+=1
            num=body[i:j]
            if '.' in num: n+=5
            else:
                v=int(num); n += 1 if v<10 else (2 if v<256 else 3)
            i=j; continue
        if ch=='&':
            n+=3; i+=2
            while i<len(body) and body[i] in '0123456789ABCDEF': i+=1
            continue
        n+=1; i+=1
    return n
def total(text, strip=False):
    text=text.replace('\r\n','\n').rstrip('\x1a')
    tot=0
    for l in text.split('\n'):
        if not l.strip(): continue
        num,_,body=l.partition(' ')
        if strip: body=stripspaces(body)
        tot += 5 + toksize(body)
    return tot
def stripspaces(body):
    if body.startswith('DATA') or 'REM' in body: return body
    KEEP=('SET','PUT','ON','ERROR','PAGE','SPRITE','DEFINT','COLOR','KEY')
    allkw=set(KW1+KW2)
    out=[]; s=False; i=0
    while i<len(body):
        ch=body[i]
        if ch=='"': s=not s; out.append(ch)
        elif ch==' ' and not s:
            prev=''.join(out)
            m=re.search(r'([A-Z]+[$]?)$',prev)
            pw=m.group(1) if m else ''
            nxt=body[i+1] if i+1<len(body) else ''
            keep=False
            if pw in KEEP: keep=True
            elif pw and pw not in allkw and pw[-1].isalpha() and nxt.isalpha(): keep=True
            if keep: out.append(ch)
        else: out.append(ch)
        i+=1
    return ''.join(out)
if __name__=='__main__':
    for f in sys.argv[1:]:
        t=open(f,encoding='latin-1').read()
        print(f, "tokenized ~", total(t), " stripped ~", total(t,True))
