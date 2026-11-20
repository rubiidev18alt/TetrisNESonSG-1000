; Three PSG tone channels carry the two NES pulse parts and the bass line.
; Use the independent noise channel for percussion on lock and line clear.
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
musicInit:
 ld a,(music)
 cp 3
 ret z
 add a,a
 ld b,a
 add a,a
 add a,b
 ld hl,songs
 call indexA
 ld de,voices
 ld b,3
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
 djnz initVoice
 ret
songs:
 dw song1ch0,song1ch1,song1ch2
 dw song2ch0,song2ch1,song2ch2
 dw song3ch0,song3ch1,song3ch2
audioTick:
 ld hl,sfxTime
 ld a,(hl)
 or a
 jr z,musicTick
 dec (hl)
 jr nz,musicTick
 ld a,0xff
 out (0x7f),a
musicTick:
 ld a,(music)
 cp 3
 ret z
 ld ix,voices
 ld c,0x96
 call voiceTick
 ld ix,voices+3
 ld c,0xb9
 call voiceTick
 ld ix,voices+6
 ld c,0xd9
voiceTick:
 dec (ix+2)
 ret nz
 ld l,(ix+0)
 ld h,(ix+1)
 ld a,(hl)
 or a
 jr nz,playNote
 inc hl
 ld e,(hl)
 inc hl
 ld d,(hl)
 ex de,hl
 ld a,(hl)
playNote:
 ld (ix+2),a
 inc hl
 ld a,(hl)
 inc hl
 out (0x7f),a
 bit 4,a
 jr nz,noteDone
 ld a,(hl)
 out (0x7f),a
 ld a,c
 out (0x7f),a
noteDone:
 inc hl
 ld (ix+0),l
 ld (ix+1),h
 ret
effect:
 ld a,(cleared)
 or a
 ld a,0xe6
 jr z,effectPitch
 ld a,0xe0
effectPitch:
 out (0x7f),a
 ld a,0xf6
 out (0x7f),a
 ld a,6
 ld (sfxTime),a
 ret
