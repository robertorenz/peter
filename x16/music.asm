; ============================================================
;  music.asm — Prokofiev leitmotifs on the YM2151, PSG SFX
;
;  The IRQ owns VERA ADDR port 1 (PSG writes); the main loop
;  owns port 0.  CTRL is saved/restored around IRQ use.
; ============================================================

.zeropage
iPtr:      .res 2                ; IRQ-only scratch (never touched by main)
iTmp:      .res 1
musPtr:    .res 2                ; indirect access -> must live in zp
musBase:   .res 2

.bss
musTimer:  .res 1
musActive: .res 1                ; 0 off, 1 looping, 2 one-shot clip
musClipN:  .res 1                ; notes left in clip mode
musMuted:  .res 1
musSongId: .res 1
; PSG sfx channels (3)
sfxPtr:    .res 6                ; 2 bytes x 3
sfxTimerA: .res 3
sfxOn:     .res 3
sfxNext:   .res 1                ; round-robin channel

.code
; ymWrite: reg A, value X (waits for busy, with a timeout so a
; quirky busy flag can never deadlock the game)
ymWrite:
	phy
	pha
	ldy #0
@w1:
	lda YM_DATA
	bpl @go1
	dey
	bne @w1
@go1:
	pla
	sta YM_ADDR
	ldy #0
@w2:
	lda YM_DATA
	bpl @go2
	dey
	bne @w2
@go2:
	stx YM_DATA
	ply
	rts

; ------------------------------------------------------------
; musicInit: silence chip, set defaults
; ------------------------------------------------------------
musicInit:
	stz musActive
	stz musMuted
	stz sfxOn
	stz sfxOn+1
	stz sfxOn+2
	stz sfxNext
	; key off all channels
	ldy #7
@off:
	phy
	tya
	tax                          ; value = channel bits only (all ops off)
	lda #$08
	jsr ymWrite
	ply
	dey
	bpl @off
	; LFO off
	lda #$18
	ldx #0
	jsr ymWrite
	lda #$19
	ldx #0
	jsr ymWrite
	lda #$1B
	ldx #0
	jsr ymWrite
	; silence PSG (16 voices x 4 regs)
	php
	sei
	lda VERA_CTRL
	pha
	ora #1
	sta VERA_CTRL
	lda #<VRAM_PSG
	sta VERA_ADDR_L
	lda #>VRAM_PSG
	sta VERA_ADDR_M
	lda #((VRAM_PSG >> 16) | VINC_1)
	sta VERA_ADDR_H
	ldx #64
	lda #0
:	sta VERA_DATA1
	dex
	bne :-
	pla
	sta VERA_CTRL
	plp
	rts

; ------------------------------------------------------------
; patches: alg 7 (all carriers), two audible ops
; per song: FBCON, MUL1, MUL2, TL1, TL2, AR, D1R, D1LRR
; ------------------------------------------------------------
.rodata
patFBCON: .byte $C7, $C7, $C7, $C7, $C7, $E7, $CF
patMUL1:  .byte 1, 1, 2, 1, 0, 1, 1
patMUL2:  .byte 2, 3, 4, 3, 1, 1, 2
patTL1:   .byte 28, 26, 30, 26, 24, 22, 22
patTL2:   .byte 42, 48, 50, 46, 40, 34, 36
patAR:    .byte 18, 16, 20, 16, 14, 12, 22
patD1R:   .byte 6, 7, 8, 7, 5, 4, 8
patD1LRR: .byte $46, $47, $58, $47, $35, $34, $69
.code

; loadPatch: Y = song id -> channel 0 setup
loadPatch:
	lda #$20                     ; RL/FB/CON ch0
	ldx patFBCON,y
	jsr ymWrite
	; op M1 (reg base +0)
	lda #$40
	ldx patMUL1,y
	jsr ymWrite
	lda #$60
	ldx patTL1,y
	jsr ymWrite
	lda #$80
	ldx patAR,y
	jsr ymWrite
	lda #$A0
	ldx patD1R,y
	jsr ymWrite
	lda #$C0
	ldx #0
	jsr ymWrite
	lda #$E0
	ldx patD1LRR,y
	jsr ymWrite
	; op 2 (base +8)
	lda #$48
	ldx patMUL2,y
	jsr ymWrite
	lda #$68
	ldx patTL2,y
	jsr ymWrite
	lda #$88
	ldx patAR,y
	jsr ymWrite
	lda #$A8
	ldx patD1R,y
	jsr ymWrite
	lda #$C8
	ldx #0
	jsr ymWrite
	lda #$E8
	ldx patD1LRR,y
	jsr ymWrite
	; ops 3+4 muted (TL = 127)
	lda #$50
	ldx #127
	jsr ymWrite
	lda #$58
	ldx #127
	jsr ymWrite
	; their release fast so they never linger
	lda #$F0
	ldx #$0F
	jsr ymWrite
	lda #$F8
	ldx #$0F
	jsr ymWrite
	rts

; ------------------------------------------------------------
; musicPlay: A = song id (loops)
; ------------------------------------------------------------
musicPlay:
	php
	sei
	sta musSongId
	tay
	tax
	lda songPtrLo,x
	sta musPtr
	sta musBase
	lda songPtrHi,x
	sta musPtr+1
	sta musBase+1
	jsr loadPatch
	lda #1
	sta musTimer
	lda #1
	sta musActive
	plp
	rts

; musicClip: A = song id, first 10 notes one-shot
musicClip:
	php
	sei
	jsr musicPlay                ; plp inside restores I flag... re-sei:
	sei
	lda #2
	sta musActive
	lda #10
	sta musClipN
	plp
	rts

musicStop:
	php
	sei
	stz musActive
	lda #$08
	ldx #0                       ; key off ch0
	jsr ymWrite
	plp
	rts

musicToggle:
	php
	sei
	lda musMuted
	eor #1
	sta musMuted
	beq :+
	lda #$08
	ldx #0
	jsr ymWrite
:	plp
	rts

; ------------------------------------------------------------
; musicTick (IRQ): advance the melody
; ------------------------------------------------------------
musicTick:
	lda musActive
	beq @done
	lda musMuted
	bne @done
	dec musTimer
	beq @next
@done:
	rts
@next:
	lda (musPtr)
	cmp #$FF
	bne @note
	; end: loop or stop
	lda musActive
	cmp #2
	beq @stopClip
	lda musBase
	sta musPtr
	lda musBase+1
	sta musPtr+1
	lda (musPtr)
@note:
	cmp #$FE
	bne @keyOn
	; rest: key off
	pha
	lda #$08
	ldx #0
	jsr ymWrite
	pla
	bra @dur
@keyOn:
	tax
	; key off, set pitch, key on
	pha
	lda #$08
	ldx #0
	jsr ymWrite
	pla
	tax
	lda #$28                     ; KC ch0
	jsr ymWrite
	lda #$08
	ldx #%01111000               ; all ops, ch0
	jsr ymWrite
	; clip countdown
	lda musActive
	cmp #2
	bne @dur
	dec musClipN
	bne @dur
	stz musActive
	bra @off
@dur:
	ldy #1
	lda (musPtr),y
	sta musTimer
	; advance
	clc
	lda musPtr
	adc #2
	sta musPtr
	bcc :+
	inc musPtr+1
:	rts
@stopClip:
	stz musActive
@off:
	lda #$08
	ldx #0
	jsr ymWrite
	rts

; ============================================================
;  PSG sound effects
;  stream: (freqL, freqH, LRvol, wavePW, dur) x N, dur=0 ends
; ============================================================

; sfxPlay: stream ptr in A (lo) / Y (hi) -> next round-robin channel
; (preserves X and Y — callers are mid-loop more often than not)
sfxPlay:
	php
	sei
	phx
	phy
	sta tmp
	sty tmp2
	ldx sfxNext
	txa
	asl
	tay
	lda tmp
	sta sfxPtr,y
	lda tmp2
	sta sfxPtr+1,y
	lda #1
	sta sfxTimerA,x
	sta sfxOn,x
	inx
	cpx #3
	bcc :+
	ldx #0
:	stx sfxNext
	ply
	plx
	plp
	rts

; sfxTick (IRQ): all channels (uses iPtr/iTmp only)
sfxTick:
	lda VERA_CTRL
	pha
	ldx #2
@chan:
	lda sfxOn,x
	beq @next
	dec sfxTimerA,x
	bne @next
	jsr sfxChanSeg
@next:
	dex
	bpl @chan
	pla
	sta VERA_CTRL
	rts

; sfxChanSeg: channel X plays its next segment
sfxChanSeg:
	txa
	asl
	tay
	lda sfxPtr,y
	sta iPtr
	lda sfxPtr+1,y
	sta iPtr+1
	ldy #4
	lda (iPtr),y
	bne @live
	; end: silence this voice
	jsr psgAddr
	stz VERA_DATA1
	stz VERA_DATA1
	stz VERA_DATA1
	stz VERA_DATA1
	stz sfxOn,x
	rts
@live:
	sta sfxTimerA,x
	jsr psgAddr
	lda (iPtr)
	sta VERA_DATA1
	ldy #1
	lda (iPtr),y
	sta VERA_DATA1
	iny
	lda (iPtr),y
	sta VERA_DATA1
	iny
	lda (iPtr),y
	sta VERA_DATA1
	; advance stream by 5
	txa
	asl
	tay
	clc
	lda sfxPtr,y
	adc #5
	sta sfxPtr,y
	bcc :+
	lda sfxPtr+1,y
	inc a
	sta sfxPtr+1,y
:	rts

; psgAddr: point ADDR1 at PSG voice X (X=0..2 -> voices 0..2)
psgAddr:
	lda VERA_CTRL
	ora #1
	sta VERA_CTRL
	txa
	asl
	asl                          ; voice*4
	clc
	adc #<VRAM_PSG
	sta VERA_ADDR_L
	lda #>VRAM_PSG
	adc #0
	sta VERA_ADDR_M
	lda #((VRAM_PSG >> 16) | VINC_1)
	sta VERA_ADDR_H
	rts

; ------------------------------------------------------------
; effect launchers
; ------------------------------------------------------------
.macro SFX name
	lda #<name
	ldy #>name
	jmp sfxPlay
.endmacro

sfxStep:
	SFX sfStep
sfxWhistle:
	SFX sfWhistle
sfxBuzz:
	SFX sfBuzz
sfxPickup:
	SFX sfPickup
sfxThud:
	SFX sfThud
sfxThrow:
	SFX sfThrow
sfxHurt:
	SFX sfHurt
sfxGrowl:
	SFX sfGrowl
sfxYelp:
	SFX sfYelp
sfxChirp:
	SFX sfChirp
sfxHorn:
	SFX sfHorn
sfxDing:
	SFX sfDing
sfxFanfare:
	SFX sfFanfare
sfxLose:
	SFX sfLose
sfxSnap:
	SFX sfSnap
sfxCreak:
	SFX sfCreak

.rodata
; (freqL, freqH, LRvol($C0|vol), wavePW, dur) ... 0-dur = end
sfStep:    .byte $50,$00,$C8,$C0,2,  0,0,0,0,0
sfWhistle: .byte $D2,$0D,$FA,$80,5, $74,$12,$FA,$80,5, $A6,$1B,$FA,$80,8, 0,0,0,0,0
sfBuzz:    .byte $A1,$00,$F4,$40,10, 0,0,0,0,0
sfPickup:  .byte $F8,$0A,$F6,$00,3, $D2,$0D,$F6,$00,4, 0,0,0,0,0
sfThud:    .byte $30,$00,$EC,$C0,4, 0,0,0,0,0
sfThrow:   .byte $3A,$09,$E8,$80,3, 0,0,0,0,0
sfHurt:    .byte $4E,$02,$F6,$40,6, $BA,$01,$F6,$40,8, 0,0,0,0,0
sfGrowl:   .byte $94,$00,$F2,$40,14, $84,$00,$F0,$40,10, 0,0,0,0,0
sfYelp:    .byte $A6,$1B,$F6,$80,3, $74,$12,$F4,$80,5, 0,0,0,0,0
sfChirp:   .byte $A6,$1B,$EE,$00,2, $4B,$1D,$EE,$00,3, 0,0,0,0,0
sfHorn:    .byte $4E,$02,$EE,$40,18, $4E,$02,$00,$40,6, $4E,$02,$EC,$40,24, 0,0,0,0,0
sfDing:    .byte $74,$12,$F0,$80,14, 0,0,0,0,0
sfFanfare: .byte $7C,$05,$F6,$00,7, $E9,$06,$F6,$00,7, $38,$08,$F6,$00,7, $F8,$0A,$F8,$00,14, 0,0,0,0,0
sfLose:    .byte $BE,$02,$F4,$40,9, $4E,$02,$F4,$40,9, $D5,$01,$F4,$40,9, $8A,$01,$F4,$40,14, 0,0,0,0,0
sfSnap:    .byte $00,$10,$F8,$C0,2, $A6,$1B,$F0,$80,3, 0,0,0,0,0
sfCreak:   .byte $70,$00,$E8,$40,5, $60,$00,$E8,$40,5, 0,0,0,0,0
.code
