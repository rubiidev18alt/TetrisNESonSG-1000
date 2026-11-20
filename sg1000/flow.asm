; Original screen sequence. Button 1 substitutes for Start; button 2 is the
; secondary menu action. SAT cursors never destroy the underlying name table.
intro:
 ld hl,sceneLegal
 call screen
 ld b,120
legalWait:
 push bc
 call frame
 pop bc
 ld a,(pressed)
 and 48
 jr nz,title
 djnz legalWait
title:
 ld hl,sceneTitle
 call screen
 ld a,4
 call startTrack
 ld de,1280
titleWait:
 push de
 call frame
 call audioTick
 pop de
 ld a,(pressed)
 bit 4,a
 jr nz,typeMenu
 dec de
 ld a,d
 or e
 jr nz,titleWait
 jp demoStart
typeMenu:
 ld hl,sceneType
 call screen
 call musicInit
typeLoop:
 call satStart
 ld a,(modeB)
 rlca
 rlca
 rlca
 rlca
 rlca
 ld e,a
 add a,a
 add a,e
 add a,62
 ld e,a
 ld d,39
 ld a,1
 call marker
 ld a,(music)
 rlca
 rlca
 rlca
 rlca
 add a,119
 ld d,a
 ld e,101
 ld a,1
 call marker
 call satEnd
 call frame
 call audioTick
 ld a,(pressed)
 bit 4,a
 jp nz,levelMenu
 bit 5,a
 jr nz,title
 ld hl,modeB
 bit 2,a
 jr z,typeRight
 ld (hl),0
typeRight:
 bit 3,a
 jr z,typeMusic
 ld (hl),1
typeMusic:
 ld hl,music
 bit 0,a
 jr z,typeDown
 ld a,(hl)
 or a
 jr z,typeLoop
 dec (hl)
 jr previewMusic
typeDown:
 bit 1,a
 jr z,typeLoop
 ld a,(hl)
 cp 3
 jr z,typeLoop
 inc (hl)
previewMusic:
 call musicInit
 jr typeLoop

levelMenu:
 ld a,0xf1
 call digitInk
 xor a
 ld (allegro),a
 call musicInit
 ld hl,sceneLevel
 call screen
 call showRanks
 xor a
 ld (cursor),a
 ld a,(startLevel)
 cp 10
 jr c,levelType
 sub 10
 ld (startLevel),a
levelType:
 call typeLabel
 ld a,(modeB)
 or a
 jp nz,levelLoop
 ld hl,0x1800+4*32+19
 ld bc,0x0808
 xor a
 call rectangle
levelLoop:
 call satStart
 ld a,(clock)
 and 8
 jr nz,levelMarker
 ld a,(cursor)
 or a
 jr z,heightMarker
levelMarker:
 ld a,(startLevel)
 ld bc,0x0538 ; five columns, first digit x=56
 call gridCursor
heightMarker:
 ld a,(modeB)
 or a
 jr z,levelRead
 ld a,(clock)
 and 8
 jr nz,markHeight
 ld a,(cursor)
 or a
 jr nz,levelRead
markHeight:
 ld a,(heightB)
 ld bc,0x03a0
 call gridCursor
levelRead:
 call satEnd
 call frame
 call audioTick
 ld a,(pressed)
 bit 4,a
 jr z,editLevel
 ld a,(held)
 bit 5,a
 jp z,newGame
 ld a,(startLevel)
 add a,10
 ld (startLevel),a
 jp newGame
editLevel:
 bit 5,a
 jr z,gridMove
 ld a,(held)
 bit 0,a
 jp nz,typeMenu
 ld a,(modeB)
 or a
 jp z,typeMenu
 ld hl,cursor
 ld a,(hl)
 xor 1
 ld (hl),a
 jp levelLoop
gridMove:
 ld a,(cursor)
 or a
 ld hl,startLevel
 ld b,5
 jr z,gridKey
 ld hl,heightB
 ld b,3
gridKey:
 ld a,(pressed)
 ld c,a
 ld a,(hl)
 bit 0,c
 jr z,gridDown
 sub b
 jr gridBound
gridDown:
 bit 1,c
 jr z,gridLeft
 add a,b
 jr gridBound
gridLeft:
 bit 2,c
 jr z,gridRight
 dec a
 jr gridBound
gridRight:
 bit 3,c
 jp z,levelLoop
 inc a
gridBound:
 ld c,a
 ld a,b
 add a,a
 cp c
 jp c,levelLoop
 jp z,levelLoop
 ld (hl),c
 jp levelLoop
gridCursor:
 ld d,63
 cp b
 jr c,gridX
 sub b
 ld d,79
gridX:
 rlca
 rlca
 rlca
 rlca
 add a,c
 ld e,a
 xor a
 jp marker
satStart:
 ld hl,0x1b00
 jp setAddr
; DE = pixel Y-1, X; A = sprite pattern
marker:
 ld c,a
 ld a,d
 out (0xbe),a
 push hl
 pop hl
 ld a,e
 out (0xbe),a
 push hl
 pop hl
 ld a,c
 out (0xbe),a
 push hl
 pop hl
 ld a,11
 out (0xbe),a
 ret
satEnd:
 ld a,0xd0
 out (0xbe),a
 ret
typeLabel:
 ld hl,0x1800+13
 call setAddr
 ld a,(modeB)
 add a,65
 out (0xbe),a
 ret

; Attract mode runs the normal engine with the NTSC recording (repeat count
; is the number of *additional* frames). Never update the player's records.
demoStart:
 ld hl,modeB
 ld de,savedOpts
 ld bc,3
 ldir
 ld a,(music)
 ld (savedOpts+3),a
 xor a
 ld (modeB),a
 ld (heightB),a
 ld (startLevel),a
 ld (demoIndex),a
 ld (demoCount),a
 ld (music),a
 inc a
 ld (demo),a
 ld hl,demoInput
 ld (demoPtr),hl
 jp newGame
demoPad:
 ld a,b
 and 48
 jr nz,demoLeave
 ld a,(demoCount)
 or a
 jr z,demoFetch
 dec a
 ld (demoCount),a
 ld a,(held)
 ld b,a
 ret
demoFetch:
 ld hl,(demoPtr)
 ld de,demoEnd
 or a
 sbc hl,de
 jr z,demoLeave
 add hl,de
 ld b,(hl)
 inc hl
 ld a,(hl)
 inc hl
 ld (demoCount),a
 ld (demoPtr),hl
 ret
demoChoose:
 ld hl,demoIndex
 ld a,(hl)
 inc (hl)
 ld hl,demoPieces
 call indexA
 ld a,(hl)
 ld (nextPiece),a
 ret
demoLeave:
 ; The recording may finish inside any frame wait (including line clear).
 ld sp,0xc400
 ld a,b
 ld (held),a
 ld hl,savedOpts
 ld de,modeB
 ld bc,3
 ldir
 ld a,(savedOpts+3)
 ld (music),a
 xor a
 ld (demo),a
 jp title

hideWell:
 ld hl,0x1800
 call setAddr
 ld bc,768
 xor a
 jp fillVram
rectangle:
 ; Tile rectangle: HL=name address, B=rows, C=columns, A=tile.
 push af
 call setAddr
 pop af
 push bc
 ld b,c
rectRow:
 out (0xbe),a
 push hl
 pop hl
 djnz rectRow
 pop bc
 ld de,32
 add hl,de
 djnz rectangle
 ret
lost:
 ld a,(demo)
 or a
 jp nz,demoLeave
 call mute
 ld hl,0x1800+3*32+12
 ld b,20
curtainRow:
 ld a,20
 sub b
 push hl
 ld hl,curtainNoise
 call indexA
 ld a,(hl)
 out (0x7f),a
 ld a,0xf8
 out (0x7f),a
 pop hl
 push bc
 push hl
 ld bc,0x010a
 ld a,1
 call rectangle
 ld b,4
curtainWait:
 push bc
 call frame
 pop bc
 djnz curtainWait
 pop hl
 ld de,32
 add hl,de
 pop bc
 djnz curtainRow
 call mute
 ld a,(modeB)
 or a
 jr nz,gameOver
 ld a,(score+2)
 cp 3
 jp nc,rocketEnding
gameOver:
 ld hl,lostMsg
 call banner
lostWait:
 call frame
 ld a,(pressed)
 bit 4,a
 jr z,lostWait
 jp postGame

won:
 ld a,5
 call startTrack
 ld hl,wonMsg
 call banner
 ld b,120
goalWait:
 push bc
 call frame
 call audioTick
 pop bc
 djnz goalWait
 ld a,(level)
 cp 10
 jr c,endingLevel
 sub 10
endingLevel:
 ld (actorId),a
 cp 9
 ld hl,sceneConcert
 jr z,endingScreen
 ld hl,sceneCathedral
endingScreen:
 call screen
 ld a,0xf4
 call digitInk
 ld a,(actorId)
 cp 9
 jr nz,endingPoints
 ld a,(heightB)
 add a,a
 ld hl,concertPatches
 call indexA
concertPatch:
 ld e,(hl)
 inc hl
 ld d,(hl)
 inc hl
 ld a,d
 or e
 jr z,endingPoints
 push hl
 ex de,hl
 call patchScene
 pop hl
 jr concertPatch
endingPoints:
 ld hl,0x1800+1*32+14
 call setAddr
 ld hl,score+2
 call printScore
 ld a,(actorId)
 call tens
 ld (bonusL),a
 ld a,(heightB)
 call tens
 ld (bonusH),a
 call tallyDisplay
 jp endingStart
tens:
 add a,a
 ld b,a
 add a,a
 add a,a
 add a,b
 ret
; Pay out each B-Type bonus in hundreds while the ending actors perform.
tallyTick:
 ld a,(clock)
 and 3
 ret nz
 ld hl,bonusL
 ld a,(hl)
 or a
 jr nz,payHundred
 inc hl
 ld a,(hl)
 or a
 ret z
payHundred:
 dec (hl)
 ld de,0x0100
 ld b,1
 call scoreAdd
tallyDisplay:
 ld hl,0x1800+2*32+15
 call setAddr
 ld a,(bonusL)
 call hundreds
 ld hl,0x1800+3*32+15
 call setAddr
 ld a,(bonusH)
 call hundreds
 ld hl,0x1800+6*32+14
 call setAddr
 ld hl,score+2
 jp printScore
hundreds:
 ld l,a
 ld h,0
 call number3
 xor a
 call digit
 xor a
 jp digit
rocketEnding:
 ld hl,sceneRocket
 call screen
 ld a,0xf4
 call digitInk
 ld a,(score+2)
 cp 0x12
 ld hl,ending_patchToPpu_typeAOver120k
 call nc,patchScene
 ld hl,0x1800+32+14
 call setAddr
 ld hl,score+2
 call printScore
 ld a,(score+2)
 ld hl,rocketLevels
 ld b,4
rocketClass:
 cp (hl)
 jr c,rocketFound
 inc hl
 djnz rocketClass
rocketFound:
 ld a,4
 sub b
 ld (actorId),a
 ld a,167
 ld (rocketY),a
 ld a,240
 ld (launchWait),a
endingStart:
 ld a,7
 call startTrack
 xor a
 ld (animTime),a
endingLoop:
 call satStart
 xor a
 ld (actorCount),a
 ld a,(animTime)
 ld c,a
 ld a,(modeB)
 or a
 jp z,launch
 ld a,(actorId)
 cp 9
 jr z,concert
 ; The NES level selects the creature, direction, speed and six lanes;
 ; height determines how many members of the procession appear.
 ld hl,creatures
 call indexA
 ld a,c
 and 8
 rrca
 rrca
 rrca
 add a,(hl)
 ld (creatureFrame),a
 ld a,(actorId)
 ld hl,creatureSteps
 call indexA
 ld b,(hl)
 ld a,c
 bit 7,b
 jr z,creatureRight
 neg
creatureRight:
 bit 1,b
 jr z,creatureSpeed
 add a,a
creatureSpeed:
 ld c,a
 ld a,(actorId)
 add a,a
 ld b,a
 add a,a
 add a,b
 ld hl,creatureLanes
 call indexA
 ld a,(heightB)
 inc a
 ld b,a
creatureLoop:
 ld a,(hl)
 sub 24
 ld d,a
 ld e,c
 ld a,(creatureFrame)
 push hl
 push bc
 call actor
 pop bc
 pop hl
 inc hl
 ld a,c
 add a,42
 ld c,a
 djnz creatureLoop
 jp endingRendered
concert:
 ; Cycle SAT priority across performers (the TMS can show only four
 ; sprites on a scanline). At height 5 the four domes also lift off.
 ld a,(heightB)
 cp 5
 jr nz,concertPeople
 ld a,(clock)
 and 3
 add a,a
 ld hl,domeParts
 call indexA
 ld e,(hl)
 inc hl
 ld b,(hl)
 ld a,(animTime)
 srl a
 ld d,a
 ld a,162
 sub d
 ld d,a
 push de
 ld a,b
 call actor
 pop de
 ld a,(clock)
 and 4
 rrca
 rrca
 add a,81
 call actor
concertPeople:
 ld a,(heightB)
 inc a
 cp 6
 jr nz,castCount
 ld a,8
castCount:
 ld b,a
 ld a,(animTime)
castMod:
 cp b
 jr c,castFirst
 sub b
 jr castMod
castFirst:
 ld c,a
 ld a,b
 ld (castSize),a
concertActor:
 ld a,c
 add a,a
 add a,c
 ld hl,concertCast
 call indexA
 ld e,(hl)
 inc hl
 ld d,(hl)
 inc hl
 ld a,(animTime)
 and 16
 rrca
 rrca
 rrca
 rrca
 add a,(hl)
 inc hl
 push hl
 push bc
 call actor
 pop bc
 pop hl
 inc c
 ld a,(castSize)
 cp c
 jr nz,castNext
 ld c,0
castNext:
 djnz concertActor
 jr endingRendered
launch:
 ld hl,launchWait
 ld a,(hl)
 or a
 jr z,liftOff
 dec (hl)
 jr drawRocket
liftOff:
 ld hl,rocketY
 ld a,(hl)
 or a
 jr z,endingRendered
 dec (hl)
drawRocket:
 ld a,(actorId)
 ld hl,rocketX
 call indexA
 ld e,(hl)
 ld a,(rocketY)
 ld d,a
 push de
 ld a,(actorId)
 ld hl,rocketBodies
 call indexA
 pop de
 ld a,(hl)
 push de
 call actor
 pop de
 ld a,(actorId)
 add a,a
 ld hl,rocketJets
 call indexA
 ld a,(clock)
 and 2
 rrca
 add a,l
 ld l,a
 jr nc,jetFrame
 inc h
jetFrame:
 ld a,(hl)
 call actor
endingRendered:
 call satEnd
 call frame
 call audioTick
 ld a,(modeB)
 or a
 call nz,tallyTick
 ld hl,animTime
 inc (hl)
 ld a,(pressed)
 bit 4,a
 jp z,endingLoop
 ld hl,(bonusL)
 ld a,h
 or l
 jp nz,endingLoop
 jp postGame
rocketX:
 db 84,84,80,72,160
creatures:
 db 44,46,84,50,52,54,75,56,58
domeParts:
 db 96,77,144,80,112,78,126,79
concertPatches:
 dw ending_patchToPpu_typeBConcertHeight0,ending_patchToPpu_typeBConcertHeight1
 dw ending_patchToPpu_typeBConcertHeight2,ending_patchToPpu_typeBConcertHeight3
 dw ending_patchToPpu_typeBConcertHeight4,0
concertCast:
 db 40,95,22,200,188,24,168,188,26,64,95,29,48,143,31,200,47,33,160,127,39,192,127,41
rocketLevels:
 db 5,7,0x10,0x12
rocketBodies:
 db 62,65,68,71,74
rocketJets:
 db 63,64,66,67,69,70,72,73,35,36
; Convert a metasprite's signed offsets to the TMS SAT. Never wrap the SAT
; into the next VRAM allocation, even for the oversized cathedral rocket.
actor:
 ld (anchorX),de
 add a,a
 ld hl,actorTable
 call indexA
 ld e,(hl)
 inc hl
 ld d,(hl)
 ex de,hl
 ld b,(hl)
 inc hl
 ld a,b
 or a
 ret z
 ld c,0
 cp 32
 jr c,actorPart
 ; Interlace the two halves of the large cathedral instead of cutting it off.
 inc c
 inc b
 srl b
 ld a,(clock)
 rra
 jr nc,actorPart
 dec b
 inc hl
 inc hl
 inc hl
 inc hl
actorPart:
 ld a,(actorCount)
 cp 31
 ret nc
 inc a
 ld (actorCount),a
 ld a,(anchorY)
 add a,(hl)
 inc hl
 out (0xbe),a
 ld a,(anchorX)
 add a,(hl)
 inc hl
 out (0xbe),a
 ld a,(hl)
 inc hl
 nop
 nop
 out (0xbe),a
 ld a,(hl)
 inc hl
 nop
 nop
 out (0xbe),a
 ld a,c
 or a
 jr z,nextPart
 inc hl
 inc hl
 inc hl
 inc hl
nextPart:
 djnz actorPart
 ret

rankDefaults:
 db 0,0,1,9
 dm "HOWARD"
 db 0,0x75,0,5
 dm "OTASAN"
 db 0,0x50,0,0
 dm "LANCE "
 db 0,0x20,0,9
 dm "ALEX  "
 db 0,0x10,0,5
 dm "TONY  "
 db 0,5,0,0
 dm "NINTEN"
rankBase:
 ld a,(modeB)
 or a
 ld hl,ranks
 ret z
 ld hl,ranks+30
 ret
showRanks:
 call rankBase
 ld de,0x1800+17*32+9
 ld b,3
showRank:
 push bc
 push de
 push hl
 ex de,hl
 call setAddr
 ex de,hl
 ld de,4
 add hl,de
 ld bc,6
 call transfer
 ld a,32
 out (0xbe),a
 pop hl
 inc hl
 inc hl
 push hl
 call printScore
 ld a,32
 out (0xbe),a
 pop hl
 inc hl
 ld a,(hl)
 ld l,a
 ld h,0
 call number2
 pop de
 push de
 ld hl,64
 add hl,de
 ex de,hl
 pop hl
 pop bc
 ; recover next record from the row index
 push de
 call rankBase
 ld de,10
 ld a,4
 sub b
rankOffset:
 add hl,de
 dec a
 jr nz,rankOffset
 pop de
 djnz showRank
 ret
postGame:
 call rankBase
 ld b,3
rankCompare:
 push hl
 inc hl
 inc hl
 ld de,score+2
 ld c,3
rankByte:
 ld a,(de)
 cp (hl)
 jr c,rankLower
 jr nz,qualified
 dec de
 dec hl
 dec c
 jr nz,rankByte
qualified:
 pop hl
 ld (rankPtr),hl
 ld a,b
 dec a
 jr z,writeRank
 ld c,10
 cp 1
 jr z,shiftRanks
 ld c,20
shiftRanks:
 ld b,0
 add hl,bc
 dec hl
 ld de,10
 add hl,de
 ex de,hl
 ld hl,0xfff6
 add hl,de
 lddr
writeRank:
 ld hl,score
 ld de,(rankPtr)
 ld bc,3
 ldir
 ld a,(level)
 ld (de),a
 inc de
 ex de,hl
 ld b,6
 ld a,32
clearName:
 ld (hl),a
 inc hl
 djnz clearName
 xor a
 ld (letter),a
 ld hl,sceneName
 call screen
 ld a,0xf1
 call digitInk
 call typeLabel
 ld a,6
 call startTrack
 jp nameLoop
rankLower:
 pop hl
 ld de,10
 add hl,de
 djnz rankCompare
 jp levelMenu
nameLoop:
 call showRanks
 call satStart
 call rankBase
 ex de,hl
 ld hl,(rankPtr)
 or a
 sbc hl,de
 ld a,l
 ld d,135
 or a
 jr z,nameMarker
 ld d,151
 cp 10
 jr z,nameMarker
 ld d,167
nameMarker:
 ld a,(letter)
 add a,9
 rlca
 rlca
 rlca
 ld e,a
 xor a
 call marker
 call satEnd
 call frame
 call audioTick
 ld a,(pressed)
 bit 5,a
 jp nz,levelMenu
 ld hl,letter
 bit 2,a
 jr z,nameForward
 ld a,(hl)
 or a
 jp z,nameLoop
 dec (hl)
 jp nameLoop
nameForward:
 and 24
 jr z,nameEdit
 inc (hl)
 ld a,(hl)
 cp 6
 jp z,levelMenu
 jp nameLoop
nameEdit:
 ld a,(letter)
 ld hl,(rankPtr)
 add a,4
 call indexA
 ld a,(pressed)
 and 3
 jp z,nameLoop
 push af
 ex de,hl
 ld a,(de)
 ld hl,alphabet
 ld bc,alphabetEnd-alphabet
 cpir
 pop af
 bit 1,a
 jr z,nameNext
 dec hl
 ld a,(hl)
 cp 32
 jr nz,namePrev
 ld hl,alphabetEnd
namePrev:
 dec hl
 jr storeChar
nameNext:
 ld a,(hl)
 or a
 jr nz,storeChar
 ld hl,alphabet
storeChar:
 ld a,(hl)
 ld (de),a
 jp nameLoop
alphabet:
 dm " ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
alphabetEnd:
 db 0
