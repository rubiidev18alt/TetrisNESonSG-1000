; Graphics I: patterns at 0000, name table 1800, SAT 1b00, colours 2000.
videoInit:
 in a,(0xbf)
 ld hl,vdpRegs
 ld b,8
 ld c,0x80
regLoop:
 ld a,(hl)
 out (0xbf),a
 ld a,c
 out (0xbf),a
 inc hl
 inc c
 djnz regLoop
 ld hl,0
 call setAddr
 ld hl,patterns
 ld bc,256*8
 call transfer
 ld hl,0x2000
 call setAddr
 ld hl,colours
 ld bc,32
 call transfer
 ld hl,0x1b00
 call setAddr
 ld a,0xd0
 out (0xbe),a
 ret
vdpRegs:
 db 0,0x80,6,0x80,0,0x36,0,1
colours:
 db 0x51,0x71,0x91,0xb1,0xf1,0xf1,0xf1,0xf1
 db 0xf1,0xf1,0xf1,0xf1,0xf1,0xf1,0xf1,0xf1
 db 0x91,0x91,0x91,0x91,0x91,0x91,0x91,0x91
 db 0x91,0x91,0x91,0x91,0x91,0x91,0x91,0x91
setAddr:
 ld a,l
 out (0xbf),a
 ld a,h
 or 0x40
 out (0xbf),a
 ret
; Space writes by at least 29 T-states, also safe during active display.
transfer:
 ld a,(hl)
 out (0xbe),a
 inc hl
 dec bc
 ld a,b
 or c
 jr nz,transfer
 ret
screen:
 push hl
 ld a,0x80
 out (0xbf),a
 ld a,0x81
 out (0xbf),a
 ld hl,0x1800
 call setAddr
 pop hl
 ld bc,768
 call transfer
 ld a,0xc0
 out (0xbf),a
 ld a,0x81
 out (0xbf),a
 ret
menuNumbers:
 ld hl,0x1800+32*11+4
 ld b,4
 ld a,(cursor)
 ld c,a
menuCursor:
 call setAddr
 xor a
 cp c
 jr nz,noMarker
 ld a,2
noMarker:
 out (0xbe),a
 ld de,64
 add hl,de
 dec c
 djnz menuCursor
 ld hl,0x1800+32*11+23
 call setAddr
 ld a,(modeB)
 add a,65
 out (0xbe),a
 ld hl,0x1800+32*13+23
 call setAddr
 ld a,(startLevel)
 ld l,a
 ld h,0
 ld de,10
 call quotient
 call digit
 ld a,l
 call digit
 ld hl,0x1800+32*15+23
 call setAddr
 ld a,(heightB)
 call digit
 ld hl,0x1800+32*17+23
 call setAddr
 ld a,(music)
 add a,a
 add a,a
 ld hl,musicNames
 call indexA
 ld bc,4
 jp transfer
musicNames:
 dm "1   2   3   OFF "

drawActive:
 call valid
 call stamp
 call drawBoard
 xor a
 jp paintCells
drawBoard:
 ld de,board+20
 ld hl,0x1800+32*2+11
 ld c,20
drawRow:
 call setAddr
 ld b,10
drawTile:
 ld a,(de)
 out (0xbe),a
 inc de
 djnz drawTile
 push de
 ld de,32
 add hl,de
 pop de
 dec c
 jr nz,drawRow
 ret

; Keep separate A/B best scores until the console is reset.
drawBest:
 ld hl,best+2
 ld a,(modeB)
 or a
 jr z,compareBest
 ld hl,best+5
compareBest:
 push hl
 ld de,score+2
 ld b,3
compareDigitPair:
 ld a,(de)
 cp (hl)
 jr c,printBest
 jr nz,newBest
 dec de
 dec hl
 djnz compareDigitPair
 jr printBest
newBest:
 ld a,(de)
 ld (hl),a
 dec hl
 dec de
 djnz newBest
printBest:
 ld hl,0x1800+32*21+2
 call setAddr
 pop hl
 jp printScore
hud:
 call drawBest
 ld hl,0x2001
 call setAddr
 ld a,(level)
modTen:
 cp 10
 jr c,colourIndex
 sub 10
 jr modTen
colourIndex:
 ld b,a
 add a,a
 add a,b
 ld hl,levelColours
 call indexA
 ld bc,3
 call transfer
 ld hl,stats
 ld de,0x1800+32*6+4
 ld b,7
statsLoop:
 push bc
 push de
 ex de,hl
 call setAddr
 ex de,hl
 ld e,(hl)
 inc hl
 ld d,(hl)
 inc hl
 push hl
 ex de,hl
 call number3
 pop hl
 pop de
 ld a,e
 add a,64
 ld e,a
 jr nc,statsNext
 inc d
statsNext:
 pop bc
 djnz statsLoop
 ld hl,0x1800+32*4+28
 call setAddr
 ld a,(modeB)
 add a,65
 out (0xbe),a
 ld hl,0x1800+32*7+23
 call setAddr
 ld hl,score+2
 call printScore
 jr hudLines
printScore:
 ld b,3
scorePair:
 ld a,(hl)
 rrca
 rrca
 rrca
 rrca
 and 15
 call digit
 ld a,(hl)
 and 15
 call digit
 dec hl
 djnz scorePair
 ret
hudLines:
 ld hl,0x1800+32*11+23
 call setAddr
 ld hl,(lines)
 call number3
 ld hl,0x1800+32*14+23
 call setAddr
 ld a,(level)
 ld l,a
 ld h,0
 call number3
 ld a,(nextPiece)
 add a,a
 add a,a
 add a,a
 ld hl,previews
 call indexA
 push hl
 ld hl,0x1800+32*18+23
 call setAddr
 pop hl
 ld bc,4
 call transfer
 push hl
 ld hl,0x1800+32*19+23
 call setAddr
 pop hl
 ld bc,4
 jp transfer
number3:
 ld de,1000
 call quotient
 ld de,100
 call quotient
 call digit
 ld de,10
 call quotient
 call digit
 ld a,l
digit:
 add a,48
 out (0xbe),a
 ret
quotient:
 xor a
subtract:
 or a
 sbc hl,de
 jr c,remainder
 inc a
 jr subtract
remainder:
 add hl,de
 ret

levelColours:
 db 0xf1,0x51,0x71, 0xf1,0xc1,0x31, 0xf1,0xd1,0x91
 db 0xf1,0x51,0x31, 0xf1,0x91,0x71, 0xf1,0x71,0x31
 db 0xf1,0x61,0xe1, 0xf1,0xd1,0x51, 0xf1,0x61,0xb1
 db 0xf1,0x91,0xb1
