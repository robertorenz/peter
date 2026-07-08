; ============================================================
;  cutscene.asm — snare capture, Triumphal Procession, curtain
; ============================================================

WS_HANG = 8                      ; wolf state: hoisted by the snare

.bss
capT:      .res 1                ; capture timeline
capSlot:   .res 1                ; which wolf got snared
paradeT:   .res 2
paradeX:   .res 2
curtainShown: .res 1
csDelay:   .res 1

.code
; ------------------------------------------------------------
; capture: the rope snaps around the wolf's tail
; ------------------------------------------------------------
enterCapture:
	stz captureFlag
	jsr musicStop
	jsr sfxSnap
	stz capT
	; the wolf nearest the oak is the one snared
	jsr nearestFoe
	cpy #0
	bne :+
	ldy #SL_FOE1
:	sty capSlot
	tya
	tax
	lda #WS_HANG
	sta astate,x
	lda #GS_CAPTURE
	sta gameState
	jmp stateDone

tickCapture:
	inc capT
	ldx capSlot
	lda capT
	cmp #14
	bcs @hoist
	; yank under the branch: quarter-step toward (oakX, oakY-12)
	sec
	lda oakXL
	sbc axL,x
	sta tmpLo
	lda oakXH
	sbc axH,x
	sta tmpHi
	jsr asr3_16                  ; /8 — snappy pull
	clc
	lda axL,x
	adc tmpLo
	sta axL,x
	lda axH,x
	adc tmpHi
	sta axH,x
	sec
	lda oakYL
	sbc #12
	sec
	sbc ayL,x
	sta tmpLo
	lda #0
	sbc ayH,x
	sta tmpHi
	jsr asr3_16
	clc
	lda ayL,x
	adc tmpLo
	sta ayL,x
	lda ayH,x
	adc tmpHi
	sta ayH,x
	jmp @draw
@hoist:
	cmp #64
	bcs @dangle
	; up it goes
	lda capT
	and #1
	beq :+
	jmp @draw
:	lda ayL,x
	bne :+
	dec ayH,x
:	dec ayL,x
	cmp #15
	beq :+
	jmp @draw
:	jsr sfxYelp
	jmp @draw
@dangle:
	; swing gently; creaks
	lda capT
	and #63
	cmp #44
	bne :+
	jsr sfxCreak
:	lda capT
	lsr
	lsr
	and #15
	tay
	lda sinTab,y
	cmp #$80
	bcs @swL
	lsr
	lsr
	lsr
	clc
	adc oakXL
	sta axL,x
	lda oakXH
	adc #0
	sta axH,x
	bra @grandpa
@swL:
	eor #$FF
	inc a
	lsr
	lsr
	lsr
	sta tmp
	sec
	lda oakXL
	sbc tmp
	sta axL,x
	lda oakXH
	sbc #0
	sta axH,x
@grandpa:
	; grandpa hurries over (if he is around)
	lda atype+SL_EXTRA
	cmp #AT_GRANDPA
	bne @draw
	phx
	ldx #SL_EXTRA
	lda oakXL
	sec
	sbc #30
	sta tgXL
	lda oakXH
	sbc #0
	sta tgXH
	lda oakYL
	clc
	adc #10
	sta tgYL
	stz tgYH
	lda #<330
	sta spdF
	lda #>330
	sta spdI
	jsr moveToward
	inc aanim+SL_EXTRA
	plx
@draw:
	; camera drifts to the oak
	sec
	lda oakXL
	sbc #<160
	sta camTX
	lda oakXH
	sbc #>160
	sta camTX+1
	bpl :+
	stz camTX
	stz camTX+1
:	sec
	lda oakYL
	sbc #100
	sta camTY
	bcs :+
	lda #0
:	sta camTY
	stz camTY+1
	jsr camTick
	jsr drawActors
	jsr drawApples
	lda capT
	cmp #200
	bcs @end
	jmp stateDone
@end:
	ldx capSlot
	stz atype,x                  ; carried off in the parade
	jmp enterParade

; ------------------------------------------------------------
; the Triumphal Procession
; ------------------------------------------------------------
enterParade:
	jsr hideAllSprites
	jsr clearHud
	stz paradeT
	stz paradeT+1
	stz paradeX
	stz paradeX+1
	; sunset light
	lda #<palGolden
	sta srcP
	lda #>palGolden
	sta srcP+1
	VSET (VRAM_PALETTE+32), VINC_1
	ldy #0
:	lda (srcP),y
	sta VERA_DATA0
	iny
	cpy #32
	bne :-
	; letterbox: solid black top 4 and bottom 4 rows
	ldy #0
	jsr letterboxRow
	ldy #1
	jsr letterboxRow
	ldy #2
	jsr letterboxRow
	ldy #3
	jsr letterboxRow
	ldy #26
	jsr letterboxRow
	ldy #27
	jsr letterboxRow
	ldy #28
	jsr letterboxRow
	ldy #29
	jsr letterboxRow
	; the Hunters' March
	lda #SONG_HUNTERS
	jsr musicPlay
	lda #GS_PARADE
	sta gameState
	jmp stateDone

letterboxRow:
	stz VERA_CTRL
	tya
	lsr
	ora #>VRAM_HUDMAP
	sta VERA_ADDR_M
	lda #0
	ror
	sta VERA_ADDR_L
	lda #VINC_1
	sta VERA_ADDR_H
	ldx #40
:	lda #$A0                     ; reverse space
	sta VERA_DATA0
	lda #$00                     ; black on black
	sta VERA_DATA0
	dex
	bne :-
	rts

; parade column: sprite index, frame pair, x offset, y, special
tickParade:
	inc paradeT
	bne :+
	inc paradeT+1
:	; column advances 1.25 px/frame
	inc paradeX
	bne :+
	inc paradeX+1
:	lda paradeT
	and #3
	bne :+
	inc paradeX
	bne :+
	inc paradeX+1
:
	; skip?
	lda joyBEdge
	and #(JB_B|JB_START)
	bne @endChk
	lda keyChar
	cmp #' '
	beq @endChk
	; time out at ~700 frames
	lda paradeT+1
	cmp #>700
	bcc @march
	lda paradeT
	cmp #<700
	bcc @march
@endChk:
	jsr musicStop
	ldx level
	lda lvType,x
	cmp #LT_CHASE
	bne :+
	jmp enterCurtain
:	jmp enterWin
@march:
	; the walking cycle
	lda paradeT
	lsr
	lsr
	lsr
	and #1
	sta tmp2                     ; anim phase

	; duck (rear)
	lda #SPI_PARADE
	sta spIdx
	ldx #0                       ; offset index
	jsr paradeMemberPos
	lda #FR_DUCK_1
	clc
	adc tmp2
	jsr paradeMemberPut
	; cat
	lda #SPI_PARADE+1
	sta spIdx
	ldx #1
	jsr paradeMemberPos
	lda #FR_CAT_L1
	clc
	adc tmp2
	jsr paradeMemberPut
	; grandpa
	lda #SPI_PARADE+2
	sta spIdx
	ldx #2
	jsr paradeMemberPos
	lda #FR_GRANDPA_1
	clc
	adc tmp2
	jsr paradeMemberPut
	; hunter 1
	lda #SPI_PARADE+3
	sta spIdx
	ldx #3
	jsr paradeMemberPos
	lda #FR_HUNTER_1
	clc
	adc tmp2
	jsr paradeMemberPut
	; the wolf, slung belly-up
	lda #SPI_PARADE+4
	sta spIdx
	ldx #4
	jsr paradeMemberPos
	sec
	lda spYL
	sbc #10
	sta spYL
	lda #FR_WOLF_L1
	sta spFrame
	lda #(Z_NORM|1|2)            ; hflip + vflip
	sta spFlags
	jsr sprPut
	; hunter 2
	lda #SPI_PARADE+5
	sta spIdx
	ldx #5
	jsr paradeMemberPos
	lda #FR_HUNTER_1
	clc
	adc tmp2
	jsr paradeMemberPut
	; Peter in front
	lda #SPI_PARADE+6
	sta spIdx
	ldx #6
	jsr paradeMemberPos
	lda #FR_PETER_L1
	clc
	adc tmp2
	jsr paradeMemberPut
	; the golden pennant
	lda #SPI_PARADE+7
	sta spIdx
	ldx #7
	jsr paradeMemberPos
	sec
	lda spYL
	sbc #18
	sta spYL
	lda #FR_PENNANT
	sta spFrame
	lda #(Z_NORM|1)
	sta spFlags
	jsr sprPut
	; the bird loops overhead
	lda #SPI_PARADE+8
	sta spIdx
	ldx #6
	jsr paradeMemberPos
	lda paradeT
	lsr
	lsr
	and #15
	tay
	lda sinTab,y
	cmp #$80
	bcs @bup
	clc
	adc #0
	lsr
	sta tmp
	sec
	lda #120
	sbc tmp
	sta spYL
	bra @bput
@bup:
	eor #$FF
	inc a
	lsr
	clc
	adc #120
	sta spYL
@bput:
	stz spYH
	lda #FR_BIRD_1
	clc
	adc tmp2
	sta spFrame
	lda #(Z_NORM|1)
	sta spFlags
	jsr sprPut
	; confetti
	ldx #15
@conf:
	txa
	clc
	adc #SPI_WEATHER
	sta spIdx
	lda paradeT
	and #1
	bne :+
	inc wthY,x
:	lda wthY,x
	cmp #240
	bcc :+
	lda #0
	sta wthY,x
	jsr rnd
	sta wthX,x
:	lda wthX,x
	sta spXL
	stz spXH
	lda wthY,x
	sta spYL
	stz spYH
	txa
	and #3
	cmp #1
	bcs :+
	lda #FR_DOTGOLD
	bra :++
:	cmp #2
	bcs :+
	lda #FR_DOTRED
	bra :++
:	lda #FR_DOTWHITE
:	sta spFrame
	lda #%00001100
	sta spFlags
	jsr sprPut
	dex
	bpl @conf
	jmp stateDone

; paradeMemberPos: X = column position index -> spXL/H, spYL/H
.rodata
paradeOff: .byte 250, 215, 180, 140, 115, 90, 50, 34
.code
paradeMemberPos:
	sec
	lda paradeX
	sbc paradeOff,x
	sta spXL
	lda paradeX+1
	sbc #0
	sta spXH
	; column marches at y=150
	lda #150
	sta spYL
	stz spYH
	rts

paradeMemberPut:
	sta spFrame
	lda #(Z_NORM|1)              ; face right
	sta spFlags
	jmp sprPut

; ------------------------------------------------------------
; curtain call — the whole cast takes a bow
; ------------------------------------------------------------
.rodata
txtEnd1: .byte "THE END",0
txtEnd2: .byte "AND IF YOU LISTEN VERY CAREFULLY",0
txtEnd3: .byte "YOU WILL HEAR THE DUCK QUACKING",0
txtEnd4: .byte "INSIDE THE WOLF...",0
.code

enterCurtain:
	lda #1
	sta curtainShown
	jsr hideAllSprites
	jsr clearHud
	; the stage: red-gold curtain above, boards below
	lda #$F0                     ; palette bank 15
	sta terrBank
	stz cellY
@crow:
	stz cellX
@ccol:
	lda cellY
	cmp #22
	bcs @boards
	lda #TI_CANOPYA
	bra @cput
@boards:
	lda #TI_PATH
@cput:
	jsr setCell
	inc cellX
	lda cellX
	cmp #40
	bne @ccol
	inc cellY
	lda cellY
	cmp #30
	bne @crow
	stz camX
	stz camX+1
	stz camY
	stz camY+1
	stz camTX
	stz camTX+1
	stz camTY
	stz camTY+1
	lda #$01
	sta textCol
	ldx #16
	ldy #4
	lda #<txtEnd1
	sta txtPtr
	lda #>txtEnd1
	sta txtPtr+1
	jsr printAt
	ldx #4
	ldy #7
	lda #<txtEnd2
	sta txtPtr
	lda #>txtEnd2
	sta txtPtr+1
	jsr printAt
	ldx #4
	ldy #9
	lda #<txtEnd3
	sta txtPtr
	lda #>txtEnd3
	sta txtPtr+1
	jsr printAt
	ldx #4
	ldy #11
	lda #<txtEnd4
	sta txtPtr
	lda #>txtEnd4
	sta txtPtr+1
	jsr printAt
	lda #SONG_PETER
	jsr musicPlay
	lda #60
	sta csDelay
	stz paradeT
	stz paradeT+1
	lda #GS_CURTAIN
	sta gameState
	jmp stateDone

.rodata
; bow line: sprite frame + x position (y = 176, bobbing)
bowFrames: .byte FR_PETER_D1, FR_BIRD_1, FR_DUCK_1, FR_CAT_L1, FR_GRANDPA_1, FR_HUNTER_1, FR_HUNTER_1, FR_WOLF_L1
bowX:      .byte 150, 130, 110, 80, 190, 220, 250, 20
.code

tickCurtain:
	inc paradeT
	bne :+
	inc paradeT+1
:	lda csDelay
	beq :+
	dec csDelay
:	; the cast bobs its bow
	ldx #7
@cast:
	txa
	clc
	adc #SPI_PARADE
	sta spIdx
	lda bowX,x
	sta spXL
	stz spXH
	; bob: sin(paradeT/8 + i*2)
	lda paradeT
	lsr
	lsr
	lsr
	sta tmp
	txa
	asl
	clc
	adc tmp
	and #15
	tay
	lda sinTab,y
	cmp #$80
	bcs @bneg
	lsr
	lsr
	clc
	adc #176
	bra @bset
@bneg:
	eor #$FF
	inc a
	lsr
	lsr
	sta tmp
	sec
	lda #176
	sbc tmp
@bset:
	sta spYL
	stz spYH
	lda bowFrames,x
	sta spFrame
	lda #Z_NORM
	sta spFlags
	jsr sprPut
	dex
	bpl @cast
	; continue?
	lda csDelay
	bne @wait
	lda joyBEdge
	and #(JB_B|JB_START)
	bne @go
	lda keyChar
	cmp #' '
	beq @go
	; auto after ~1500
	lda paradeT+1
	cmp #>1500
	bcc @wait
	lda paradeT
	cmp #<1500
	bcc @wait
@go:
	jsr musicStop
	jmp enterWin
@wait:
	jmp stateDone
