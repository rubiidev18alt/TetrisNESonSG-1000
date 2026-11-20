; SG-1000: 0000-3fff fixed ROM, c000-c3ff work RAM. No BIOS or mapper.
board:      equ 0xc000   ; 22 rows x 10, first two above the visible well
cells:      equ 0xc0dc   ; four checked offsets into board (fits in a byte)
piece:      equ 0xc0e0
posX:       equ 0xc0e1
posY:       equ 0xc0e2
nextPiece:  equ 0xc0e3
seed:       equ 0xc0e4
spawnCount: equ 0xc0e6
held:       equ 0xc0e7
pressed:    equ 0xc0e8
modeB:      equ 0xc0e9
startLevel: equ 0xc0ea
heightB:    equ 0xc0eb
level:      equ 0xc0ec
lines:      equ 0xc0ed   ; 16-bit line count (remaining goal in B)
toLevel:    equ 0xc0ef
score:      equ 0xc0f0   ; 3 bytes packed BCD, least significant first
fall:       equ 0xc0f3
das:        equ 0xc0f4
soft:       equ 0xc0f5
cleared:    equ 0xc0f6
downRepeat: equ 0xc0f9
cursor:     equ 0xc0f7
music:      equ 0xc0f8
sfxTime:    equ 0xc0fa

stats:      equ 0xc100   ; seven 16-bit spawn counters, T J Z O S L I
wipeRows:   equ 0xc10e   ; up to four name-table row addresses
best:       equ 0xc120   ; two session records in packed BCD
voices:     equ 0xc116   ; three records: event pointer (2), frames remaining (1)

 org 0
 di
 jp boot
 ds 0x38-$
 reti
 ds 0x66-$
 retn
boot:
 ld sp,0xc400
 xor a
 ld hl,board
 ld (hl),a
 ld de,board+1
 ld bc,0x1ff
 ldir
 ld hl,0x8988
 ld (seed),hl
 call mute
 call videoInit
menu:
 call mute
 ld hl,menuMap
 call screen
menuLoop:
 call menuNumbers
 call frame
 ld a,(pressed)
 bit 4,a
 jp nz,newGame
 ld hl,cursor
 ld c,4
 bit 0,a
 call nz,cycleDown
 ld a,(pressed)
 bit 1,a
 call nz,cycleUp
 ld a,(cursor)
 add a,a
 add a,a
 ld hl,options
 call indexA
 ld e,(hl)
 inc hl
 ld d,(hl)
 inc hl
 ld c,(hl)
 ex de,hl
 ld a,(pressed)
 bit 2,a
 call nz,cycleDown
 ld a,(pressed)
 bit 3,a
 call nz,cycleUp
 jr menuLoop
options:
 dw modeB
 db 2,0
 dw startLevel
 db 20,0
 dw heightB
 db 6,0
 dw music
 db 4,0
cycleDown:
 ld a,(hl)
 or a
 jr nz,cycleDec
 ld (hl),c
cycleDec:
 dec (hl)
 ret
cycleUp:
 inc (hl)
 ld a,(hl)
 cp c
 ret c
 ld (hl),0
 ret

; Poll the latched TMS9918A frame flag (register 1 interrupts disabled).
frame:
 in a,(0xbf)
 and 0x80
 jr z,frame
 in a,(0xdc)
 cpl
 and 63
 ld b,a
 ld a,(held)
 cpl
 and b
 ld (pressed),a
 ld a,b
 ld (held),a
random:
 ld hl,(seed)
 ld a,h
 xor l
 rra
 rra
 rr h
 rr l
 ld (seed),hl
 ld a,h
 ret

newGame:
 xor a
 ld hl,stats
 ld (hl),a
 ld de,stats+1
 ld bc,13
 ldir
 ld hl,board
 ld de,board+1
 ld (hl),a
 ld bc,219
 ldir
 ld hl,0
 ld (lines),hl
 ld (score),hl
 ld (score+2),a
 ld (das),a
 ld (spawnCount),a
 ld (sfxTime),a
 ld a,(startLevel)
 ld (level),a
 ; NES first transition: 10..15 start at 100 lines, 16..19 at 110..140.
 cp 10
 jr c,firstThreshold
 sub 6
 cp 9
 jr nc,firstThreshold
 ld a,9
firstThreshold:
 inc a
 add a,a
 ld b,a
 add a,a
 add a,a
 add a,b
 ld (toLevel),a
 ld a,(modeB)
 or a
 call nz,garbage
 ld hl,gameMap
 call screen
 call musicInit
 ld a,255
 ld (nextPiece),a
 call choose
spawn:
 ld a,(nextPiece)
 ld (piece),a
 ld hl,spawns
 ld bc,7
 cpir
 ld a,6
 sub c
 add a,a
 ld hl,stats
 call indexA
 inc (hl)
 jr nz,counted
 inc hl
 inc (hl)
counted:
 call choose
 ld a,5
 ld (posX),a
 ld a,2
 ld (posY),a
 xor a
 ld (fall),a
 ld (soft),a
 ld (downRepeat),a
 call valid
 jp c,lost
 call hud
play:
 call drawActive
playFrame:
 call frame
 call audioTick
 ld a,(pressed)
 bit 0,a
 jp nz,pauseGame
 call shift
 call rotate
 ld a,(level)
 cp 29
 jr c,lookupGravity
 ld a,29
lookupGravity:
 ld hl,gravity
 call indexA
 ld b,(hl)
 ; NES down must be pressed afresh after entry; repeat every two frames.
 ld a,(held)
 and 15
 cp 2
 jr nz,releaseDown
 ld hl,downRepeat
 ld a,(hl)
 or a
 jr nz,repeatDown
 ld a,(pressed)
 bit 1,a
 jr z,gravityTick
 inc (hl)
 jr gravityTick
repeatDown:
 inc (hl)
 ld a,(hl)
 cp 3
 jr c,gravityTick
 ld (hl),1
 ld hl,soft
 inc (hl)
 jr dropNow
releaseDown:
 xor a
 ld (soft),a
 ld (downRepeat),a
gravityTick:
 ld hl,fall
 inc (hl)
 ld a,(hl)
 cp b
 jp c,play
dropNow:
 xor a
 ld (fall),a
 ld hl,posY
 inc (hl)
 call valid
 jr c,lock
 jp play
lock:
 ld hl,posY
 dec (hl)
 call valid
 call stamp
 ld a,(soft)
 cp 2
 jr c,noDropScore
 dec a
 ld b,a
 ld de,1
 call scoreAdd
noDropScore:
 call drawBoard
 call clearRows
 call wipe
 call award
 call drawBoard
 call hud
 ld a,(modeB)
 or a
 jr z,entryDelay
 ld a,(lines)
 or a
 jp z,won
entryDelay:
 ld a,(posY)
 srl a
 srl a
 add a,a
 ld b,a
 ld a,20
 sub b
 ld b,a
 push bc
 call effect
 pop bc
entryLoop:
 push bc
 call frame
 call audioTick
 pop bc
 djnz entryLoop
 jp spawn

shift:
 ld a,(held)
 bit 1,a
 ret nz
 and 12
 ret z
 ld a,(pressed)
 and 12
 jr z,repeatShift
 xor a
 jr setDas
repeatShift:
 ld hl,das
 inc (hl)
 ld a,(hl)
 cp 16
 ret c
 ld a,10
setDas:
 ld (das),a
 ld a,(held)
 ld hl,posX
 ld b,(hl)
 bit 3,a
 jr nz,right
 dec (hl)
 jr tryShift
right:
 inc (hl)
tryShift:
 push bc
 call valid
 pop bc
 ret nc
 ld hl,posX
 ld (hl),b
 ld a,16-1
 ld (das),a
 ret
rotate:
 ld a,(pressed)
 and 48
 ret z
 and 16      ; button 1 clockwise, button 2 counterclockwise
 jr z,turnLeft
 ld a,1
turnLeft:
 ld b,a
 ld a,(piece)
 push af
 add a,a
 add a,b
 ld hl,rotations
 call indexA
 ld a,(hl)
 ld (piece),a
 call valid
 jr c,undoTurn
 pop af
 ret
undoTurn:
 pop af
 ld (piece),a
 ret

; Carry if out of bounds/occupied. Otherwise cells[] describes all four
; minos, for both temporary drawing and permanent locking.
valid:
 ld a,(piece)
 add a,a
 add a,a
 add a,a
 ld hl,offsets
 call indexA
 ld ix,cells
 ld b,4
cellLoop:
 ld a,(posY)
 add a,(hl)
 cp 22
 jr nc,badCell
 add a,a
 ld c,a
 add a,a
 add a,a
 add a,c
 ld c,a
 inc hl
 ld a,(posX)
 add a,(hl)
 cp 10
 jr nc,badCell
 add a,c
 ld e,a
 ld d,0xc0   ; board is page-aligned
 ld (ix+0),e
 ld a,(de)
 or a
 jr nz,badCell
 inc ix
 inc hl
 djnz cellLoop
 ret
badCell:
 scf
 ret
stamp:
 ld a,(piece)
 ld hl,pieceTiles
 call indexA
 ld a,(hl)
paintCells:
 ld hl,cells
 ld b,4
 ld d,0xc0
paintLoop:
 ld e,(hl)
 ld (de),a
 inc hl
 djnz paintLoop
 ret
indexA:
 ld e,a
 ld d,0
 add hl,de
 ret

choose:
 ld hl,spawnCount
 inc (hl)
 ld a,(seed+1)
 add a,(hl)
 and 7
 cp 7
 jr z,reroll
 ld hl,spawns
 call indexA
 ld a,(nextPiece)
 cp (hl)
 jr nz,chosen
reroll:
 call random
 and 7
 ld hl,nextPiece
 add a,(hl)
modSeven:
 cp 7
 jr c,rollIndex
 sub 7
 jr modSeven
rollIndex:
 ld hl,spawns
 call indexA
chosen:
 ld a,(hl)
 ld (nextPiece),a
 ret

garbage:
 ld a,25
 ld (lines),a
 ld a,(heightB)
 ld hl,garbageRows
 call indexA
 ld b,(hl)
 ld a,b
 or a
 ret z
 ld de,board+219
garbageRow:
 push de
 ld c,10
garbageCell:
 call random
 and 7
 ld hl,garbageTiles
 push de
 call indexA
 ld a,(hl)
 pop de
 ld (de),a
 dec de
 dec c
 jr nz,garbageCell
hole:
 call random
 and 15
 cp 10
 jr nc,hole
 pop hl
 ld c,a
 ld a,l
 sub c
 ld l,a
 ld (hl),0
 djnz garbageRow
 ret
garbageRows:
 db 0,3,5,8,10,12
garbageTiles:
 db 0,8,0,16,24,24,0,0

; Stable bottom-up compaction, including the two hidden source rows.
clearRows:
 xor a
 ld (cleared),a
 ld hl,board+219
 ld de,board+219
 ld b,22
scanRow:
 push hl
 ld c,10
scanCell:
 ld a,(hl)
 or a
 jr z,keepRow
 dec hl
 dec c
 jr nz,scanCell
 ; B is the number of rows left. Translate RAM row 0..21 to
 ; the identically numbered name-table row (visible rows begin at 2).
 push hl
 ld a,22
 sub b
 ld l,a
 ld h,0
 add hl,hl
 add hl,hl
 add hl,hl
 add hl,hl
 add hl,hl
 push de
 ld de,0x1800+11
 add hl,de
 push hl
 ld a,(cleared)
 add a,a
 ld hl,wipeRows
 call indexA
 pop de
 ld (hl),e
 inc hl
 ld (hl),d
 pop de
 pop hl
 pop af       ; discard saved source end
 ld a,(cleared)
 inc a
 ld (cleared),a
 jr nextRow
keepRow:
 pop hl
 push bc
 ld bc,10
 lddr
 pop bc
nextRow:
 djnz scanRow
 ld a,(cleared)
 or a
 ret z
 ld b,a
zeroRow:
 ld c,10
zeroCell:
 xor a
 ld (de),a
 dec de
 dec c
 jr nz,zeroCell
 djnz zeroRow
 ret

; Erase completed rows from the centre outward before revealing the new board.
wipe:
 ld a,(cleared)
 or a
 ret z
 ld c,0
wipeStep:
 ld hl,wipeRows
 ld a,(cleared)
 ld b,a
wipeRow:
 ld e,(hl)
 inc hl
 ld d,(hl)
 inc hl
 push hl
 ld a,4
 sub c
 add a,e
 ld l,a
 ld h,d
 call setAddr
 xor a
 out (0xbe),a
 ld a,5
 add a,c
 add a,e
 ld l,a
 call setAddr
 xor a
 out (0xbe),a
 pop hl
 djnz wipeRow
 push bc
 ld b,4
wipeWait:
 push bc
 call frame
 call audioTick
 pop bc
 djnz wipeWait
 pop bc
 inc c
 ld a,c
 cp 5
 jr nz,wipeStep
 ret

award:
 ld a,(cleared)
 or a
 ret z
 ld c,a
 ld a,(modeB)
 or a
 jr z,countUp
 ld a,(lines)
 sub c
 jr nc,remaining
 xor a
remaining:
 ld (lines),a
 jr linePoints
countUp:
 ld hl,(lines)
 ld b,0
 add hl,bc
 ld (lines),hl
 ld a,(toLevel)
 sub c
 jr z,advance
 jr nc,setThreshold
advance:
 add a,10
 ld hl,level
 inc (hl)
setThreshold:
 ld (toLevel),a
linePoints:
 ld a,(cleared)
 add a,a
 ld hl,points
 call indexA
 ld e,(hl)
 inc hl
 ld d,(hl)
 ld a,(level)
 inc a
 ld b,a
scoreAdd:
 ld hl,score
 ld a,(hl)
 add a,e
 daa
 ld (hl),a
 inc hl
 ld a,(hl)
 adc a,d
 daa
 ld (hl),a
 inc hl
 ld a,(hl)
 adc a,0
 daa
 ld (hl),a
 jr c,maxScore
 djnz scoreAdd
 ret
maxScore:
 ld hl,0x9999
 ld (score),hl
 ld a,l
 ld (score+2),a
 ret
points:
 dw 0,0x0040,0x0100,0x0300,0x1200

pauseGame:
 call mute
 ld hl,pauseMsg
 call banner
pauseLoop:
 call frame
 ld a,(pressed)
 bit 0,a
 jr z,pauseLoop
 jp play
lost:
 call drawBoard
 ld hl,lostMsg
 jr finish
won:
 ld a,(level)
 cp 10
 jr c,winBonus
 sub 10
winBonus:
 ld hl,heightB
 add a,(hl)
 ld b,a
 ld de,0x1000
 or a
 call nz,scoreAdd
 call hud
 ld hl,wonMsg
finish:
 call banner
 call mute
 ld hl,0x1800+32*23+10
 call setAddr
 ld hl,retryMsg
 ld bc,13
 call transfer
finishLoop:
 call frame
 ld a,(pressed)
 bit 4,a
 jr z,finishLoop
 jp menu
banner:
 push hl
 ld hl,0x1800+32*11+11
 call setAddr
 pop hl
 ld bc,10
 jp transfer
pauseMsg:
 dm "  PAUSED  "
lostMsg:
 dm "GAME  OVER"
wonMsg:
 dm " COMPLETE "
retryMsg:
 dm "BUTTON 1 MENU"

 include "video.asm"
 include "audio.asm"
 include "assets.inc"
 ds 16383-$
 db 0xff
