; SG-1000: 0000-bfff fixed ROM, c000-c3ff work RAM. No BIOS or mapper.
board:      equ 0xc000   ; 22 rows x 10, first two above the visible well
wellAddr:   equ 0x1800+32*3+12 ; first visible tile (RAM board row 2)
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
voices:     equ 0xc116   ; four records: event pointer (2), frames remaining, envelope pointer or gate timer (2)

clock:      equ 0xc130
trackId:    equ 0xc131
demo:       equ 0xc132
demoPtr:    equ 0xc133
demoCount:  equ 0xc135
demoIndex:  equ 0xc136
savedOpts:  equ 0xc137
rankPtr:    equ 0xc13b
letter:     equ 0xc13d
anchorX:    equ 0xc13e
anchorY:    equ 0xc13f
animTime:   equ 0xc140
actorId:    equ 0xc141
actorCount: equ 0xc142
allegro:    equ 0xc143
tempoBase:  equ 0xc144
fxPtr:      equ 0xc145
bonusL:     equ 0xc18c
bonusH:     equ 0xc18d
castSize:   equ 0xc149
previewOff: equ 0xc148
creatureFrame: equ 0xc14a
launchWait: equ 0xc14b
rocketY:    equ 0xc14c
leadVolume: equ 0xc14f
leadPeriod: equ 0xc14d
ranks:      equ 0xc150   ; six entries of score (BCD LE), level, six ASCII letters

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
 ld hl,rankDefaults
 ld de,ranks
 ld bc,60
 ldir
 jp intro

; Poll the latched TMS9918A frame flag (register 1 interrupts disabled).
frame:
 in a,(0xbf)
 and 0x80
 jr z,frame
 ld hl,clock
 inc (hl)
 in a,(0xdc)
 cpl
 and 63
 ld b,a
 ld a,(demo)
 or a
 call nz,demoPad

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
 ld (allegro),a
 ld (bonusL),a
 ld (bonusH),a
 ld (previewOff),a
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
 call gameScreen
 call musicInit
 xor a
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
 ; Both fire buttons together substitute for NES Select (preview toggle).
 ld a,(held)
 and 48
 cp 48
 jr nz,normalControls
 ld a,(pressed)
 and 48
 jr z,normalControls
 ld hl,previewOff
 ld a,(hl)
 xor 1
 ld (hl),a
 call drawPreview
 jr gravityControl
normalControls:
 call shift
 call rotate
gravityControl:
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
 and 14
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
 call effect
 call wipe
 call award
 call danger
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
 jp nc,shiftSound
 ld hl,posX
 ld (hl),b
 ld a,16
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
 jp rotateSound
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
 ld a,(demo)
 or a
 jp nz,demoChoose
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
 ; Scanning upwards: B=22 at the floor (RAM row 21), B=3 at
 ; the first visible row. Hidden rows compact too, but have no VRAM tile.
 push hl
 push de
 ld hl,0
 ld a,b
 sub 3
 jr c,saveWipeRow
 ld l,a
 add hl,hl
 add hl,hl
 add hl,hl
 add hl,hl
 add hl,hl
 ld de,wellAddr
 add hl,de
saveWipeRow:
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
 push bc
wipeSync:
 call frame
 call audioTick
 ld a,(clock)
 and 3
 jr nz,wipeSync
 pop bc
 ld hl,wipeRows
 ld a,(cleared)
 ld b,a
wipeRow:
 ld e,(hl)
 inc hl
 ld d,(hl)
 inc hl
 ld a,d
 or a
 jr z,wipeNextRow
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
wipeNextRow:
 djnz wipeRow
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
 push af
 ld hl,fxLevel
 call startFx
 pop af
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

gameScreen:
 ld hl,scenePlay
 call screen
 ld a,(modeB)
 or a
 ld hl,game_typeb_nametable_patch
 call nz,patchScene
 ret
 include "flow.asm"
banner:
 push hl
 ld hl,0x1800+32*11+12
 call setAddr
 pop hl
 ld bc,10
 jp transfer
lostMsg:
 dm "GAME  OVER"
wonMsg:
 dm " COMPLETE "

 include "video.asm"
 include "audio.asm"
 include "assets.inc"
romUsed:
 ds 49151-$
 db 0xff
