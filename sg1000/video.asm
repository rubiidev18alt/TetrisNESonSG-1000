; Graphics II: three 2 KiB pattern/colour banks; name table 1800, SAT 1b00.
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
 ; Common overlay tiles have the same indices in each Graphics II third.
 ld de,0
 ld b,3
initBands:
 push bc
 ld h,d
 ld l,e
 call setAddr
 xor a
 ld bc,96*8
 call fillVram
 ld h,d
 ld l,8
 call setAddr
 ld hl,curtainTile
 ld bc,8
 call transfer
 ld hl,48*8
 add hl,de
 call setAddr
 ld hl,font
 ld bc,43*8
 call transfer
 ld h,d
 ld l,e
 set 5,h
 call setAddr
 ld bc,96*8
 ld a,0xf1
 call fillVram
 ld a,d
 add a,8
 ld d,a
 pop bc
 djnz initBands
 ld hl,0x3800
 call setAddr
 ld hl,cursorTiles
 ld bc,16
 call transfer
 ld hl,actorArt
 ld bc,actorArtEnd-actorArt
 jp transfer
vdpRegs:
 db 2,0x80,6,0xff,3,0x36,7,1
cursorTiles:
 db 255,129,129,129,129,129,129,255
 db 0,64,96,112,120,112,96,64
fillVram:
 out (0xbe),a
 dec bc
 push af
 ld a,b
 or c
 jr z,fillDone
 pop af
 jr fillVram
fillDone:
 pop af
 ret
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
 ld hl,0x1b00
 call setAddr
 ld a,0xd0
 out (0xbe),a
 pop hl
screenChunk:
 ld e,(hl)
 inc hl
 ld d,(hl)
 inc hl
 ld a,d
 cp 255
 jr z,screenOn
 ld c,(hl)
 inc hl
 ld b,(hl)
 inc hl
 ex de,hl
 call setAddr
 ex de,hl
 call transfer
 jr screenChunk
screenOn:
 ld a,0xc0
 out (0xbf),a
 ld a,0x81
 out (0xbf),a
 ret

drawActive:
 call valid
 call stamp
 call drawBoard
 xor a
 jp paintCells
drawBoard:
 ld de,board+20
 ld hl,0x1800+32*3+12
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

hud:
 ld hl,0x1800+32*2+24
 call setAddr
 call rankBase
 inc hl
 inc hl
 call printScore
 ld a,(level)
modTen:
 cp 10
 jr c,colourIndex
 sub 10
 jr modTen
colourIndex:
 ; Three block designs, sixteen bytes of pattern/colour per design.
 ld hl,blockArt
 ld de,48
 or a
 jr z,haveSkin
 ld b,a
skinOffset:
 add hl,de
 djnz skinOffset
haveSkin:
 ld de,0x0040
 ld a,3
skinBand:
 push af
 push de
 push hl
 ld a,3
skinTile:
 push af
 ex de,hl
 call setAddr
 ex de,hl
 ld bc,8
 call transfer
 set 5,d
 ex de,hl
 call setAddr
 ex de,hl
 ld bc,8
 call transfer
 res 5,d
 ld a,e
 add a,64
 ld e,a
 pop af
 dec a
 jr nz,skinTile
 pop hl
 pop de
 ld a,d
 add a,8
 ld d,a
 pop af
 dec a
 jr nz,skinBand
 ld hl,stats
 ld de,0x1800+32*9+6
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
 ld hl,0x1800+32*1+3
 call setAddr
 ld a,(modeB)
 add a,65
 out (0xbe),a
 ld hl,0x1800+32*5+24
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
 ld hl,0x1800+32*0+19
 call setAddr
 ld hl,(lines)
 call number3
 ld hl,0x1800+32*18+25
 call setAddr
 ld a,(level)
 ld l,a
 ld h,0
 call number2
 ld a,(modeB)
 or a
 jr z,drawPreview
 ld hl,0x1800+22*32+26
 call setAddr
 ld a,(heightB)
 call digit
drawPreview:
 ld a,(previewOff)
 or a
 jr z,showPreview
 ld hl,0x1800+32*11+24
 ld bc,0x0204
 xor a
 jp rectangle
showPreview:
 ld a,(nextPiece)
 add a,a
 add a,a
 add a,a
 ld hl,previews
 call indexA
 push hl
 ld hl,0x1800+32*11+24
 call setAddr
 pop hl
 ld bc,4
 call transfer
 push hl
 ld hl,0x1800+32*12+24
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
number2:
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

; Offline-converted NES nametable edits. HL points at count + (addr, tile).
patchScene:
 ld b,(hl)
 inc hl
patchTile:
 ld e,(hl)
 inc hl
 ld d,(hl)
 inc hl
 ex de,hl
 call setAddr
 ex de,hl
 ld a,(hl)
 inc hl
 out (0xbe),a
 djnz patchTile
 ret

; Match overlay digits to the sky in the ending scenes, black in the menus.
digitInk:
 ld hl,0x2000+48*8
 ld de,0x800
 ld b,3
inkBand:
 push bc
 push af
 call setAddr
 pop af
 ld bc,80
 call fillVram
 add hl,de
 pop bc
 djnz inkBand
 ret
