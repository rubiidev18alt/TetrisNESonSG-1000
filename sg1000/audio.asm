; NES pulse envelopes mapped to PSG attenuation. Triangle uses tone 2, and
; recorded percussion uses the noise channel. Effects briefly take tone 0.
mute:
 ld a,0x9f
 out (0x7f),a
 ld a,0xbf
 out (0x7f),a
 ld a,0xdf
 out (0x7f),a
 ld a,0xff
 out (0x7f),a
 ret
danger:
 ld hl,board+70     ; NES checks visible row 5 after a lock/clear
 ld b,10
checkDanger:
 ld a,(hl)
 or a
 jr nz,inDanger
 inc hl
 djnz checkDanger
 jr setDanger
inDanger:
 ld a,1
setDanger:
 ld hl,allegro
 cp (hl)
 ret z
 ld (hl),a
musicInit:
 ld a,(music)
startTrack:
 ld (trackId),a
 push af
 call mute
 xor a
 ld (sfxTime),a
 ld (leadPeriod),a
 ld hl,0
 ld (fxPtr),hl
 pop af
 cp 3
 ret z
 ld b,a
 ld hl,normalTempos
 ld a,(allegro)
 or a
 jr z,setTempo
 ld hl,fastTempos
setTempo:
 ld a,b
 call indexA
 ld a,(hl)
 ld (tempoBase),a
 ld a,b
 add a,a
 add a,a
 add a,a
 ld hl,songs
 call indexA
 ld de,voices
 ld b,4
initVoice:
 ld a,(hl)
 ld (de),a
 inc hl
 inc de
 ld a,(hl)
 ld (de),a
 inc hl
 inc de
 ld a,1
 ld (de),a
 inc de
 inc de
 inc de
 djnz initVoice
 ret
normalTempos:
 db 36,36,36,0,36,0,24,36
fastTempos:
 db 0,12,12,0,36,0,24,36
songs:
 dw song1ch0,song1ch1,song1ch2,song1ch3
 dw song2ch0,song2ch1,song2ch2,song2ch3
 dw song3ch0,song3ch1,song3ch2,0
 dw 0,0,0,0
 dw song4ch0,song4ch1,song4ch2,song4ch3
 dw song5ch0,song5ch1,song5ch2,song5ch3
 dw song6ch0,song6ch1,song6ch2,song6ch3
 dw song7ch0,song7ch1,song7ch2,song7ch3
audioTick:
 ld a,(trackId)
 cp 3
 jr z,fxTick
 ld ix,voices
 ld c,0x90
 call voiceTick
 ld ix,voices+5
 ld c,0xb0
 call voiceTick
 ld ix,voices+10
 ld c,0xd0
 call voiceTick
 ld ix,voices+15
 ld c,0xf0
 call voiceTick
fxTick:
 ld hl,(fxPtr)
 ld a,h
 or l
 ret z
 ld a,(sfxTime)
 or a
 jr nz,fxHold
 ld a,(hl)
 or a
 jr z,fxEnd
 ld (sfxTime),a
 inc hl
 ld a,(hl)
 ld (fxNote),a
 inc hl
 ld (fxPtr),hl
fxHold:
 ld hl,sfxTime
 dec (hl)
 ld a,(fxNote)
 ld b,a
 and 15
 or 0x80
 out (0x7f),a
 ld a,b
 rrca
 rrca
 rrca
 rrca
 and 15
 out (0x7f),a
 ld a,0x95
 out (0x7f),a
 ret
fxEnd:
 ld hl,0
 ld (fxPtr),hl
 ld a,(leadPeriod)
 or a
 jr z,fxSilence
 out (0x7f),a
 bit 4,a
 ret nz
 ld a,(leadPeriod+1)
 out (0x7f),a
 ret
fxSilence:
 ld a,0x9f
 out (0x7f),a
 ret
voiceTick:
 ld l,(ix+0)
 ld h,(ix+1)
 ld a,l
 or h
 ret z
 dec (ix+2)
 jr nz,envelopeTick
 ld a,(hl)
 or a
 jr nz,playNote
 inc hl
 ld e,(hl)
 inc hl
 ld d,(hl)
 ex de,hl
 ld a,h
 or l
 jr nz,loopNote
 ld (ix+0),a
 ld (ix+1),a
 ld a,c
 or 15
 out (0x7f),a
 ret
loopNote:
 ld a,(hl)
playNote:
 push hl
 ld hl,tempoBase
 dec a
 add a,(hl)
 ld hl,durations
 call indexA
 ld a,(hl)
 ld (ix+2),a
 pop hl
 inc hl
 ld a,c
 cp 0x90
 jr nz,sendLatch
 ld a,(hl)
 ld (leadPeriod),a
 inc hl
 ld a,(hl)
 ld (leadPeriod+1),a
 dec hl
sendLatch:
 ld a,(hl)
 inc hl
 out (0x7f),a
 bit 4,a
 jr nz,noteRest
 ld a,(hl)
 out (0x7f),a
 ld a,c
 cp 0xd0
 jr nz,noteRest
 ld a,0xd9
 out (0x7f),a
noteRest:
 inc hl
 ld a,c
 cp 0xd0
 jr nc,saveEvent
 ld a,(hl)
 inc hl
 push hl
 add a,a
 ld hl,envelopeTable
 call indexA
 ld a,(hl)
 ld (ix+3),a
 inc hl
 ld a,(hl)
 ld (ix+4),a
 pop hl
saveEvent:
 ld (ix+0),l
 ld (ix+1),h
envelopeTick:
 ld a,c
 cp 0xd0
 ret nc
 ld l,(ix+3)
 ld h,(ix+4)
 ld a,(hl)
 cp 255
 ret z
 or c
 out (0x7f),a
 inc hl
 ld (ix+3),l
 ld (ix+4),h
 ret
shiftSound:
 ld hl,fxShift
 jr startFx
rotateSound:
 ld hl,fxRotate
 jr startFx
effect:
 ld hl,fxLock
 ld a,(cleared)
 or a
 jr z,startFx
 ld hl,fxClear
 cp 4
 jr nz,startFx
 ld hl,fxTetris
startFx:
 ld (fxPtr),hl
 xor a
 ld (sfxTime),a
 ret
; Pairs of NTSC frames and tone period low, adapted from the NES SQ1 cues.
fxShift:
 db 2,128,0
fxRotate:
 db 4,192,4,160,4,192,0
fxLock:
 db 3,255,3,223,3,191,0
fxClear:
 db 3,112,3,128,3,144,3,160,3,176,3,192,3,208,3,224,0
fxTetris:
 db 4,192,4,137,4,184,4,104,4,160,4,80,4,144,4,64,0
fxLevel:
 db 3,105,3,168,3,105,3,168,3,141,3,83,3,141,3,83,3,141,0
