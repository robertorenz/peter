; ============================================================
;  draw.asm — sprite composition, palette moods, night light,
;  ambient life (fireflies, butterflies, weather, dove)
; ============================================================

; sprite index map
SPI_ACTORS  = 0                  ; 0..7 = actor slots
SPI_DOVE    = 8
SPI_EXCL    = 9
SPI_ZZZ     = 10
SPI_THROWN  = 11                 ; ..14
SPI_NOTE    = 15
SPI_APPLES  = 16                 ; ..25
SPI_ROPE    = 26
SPI_NOOSE   = 27
SPI_HEARTS  = 28                 ; ..30
SPI_MINI    = 32                 ; ..39 minimap dots
SPI_FIRE    = 40                 ; ..51 fireflies
SPI_BFLY    = 52                 ; ..59 butterflies
SPI_WEATHER = 64                 ; ..79
SPI_PARADE  = 80                 ; ..95

Z_NORM = %00001000               ; z=2: between layer0 and layer1

.bss
dbgC:      .res 1
dbgXL:     .res 1
dbgXH:     .res 1
dbgYL:     .res 1
dbgYH:     .res 1
driftL:    .res 1                ; light drift counter
driftH:    .res 1
fadeSeg:   .res 1                ; chase palette segment cache
fireX:     .res 12
fireY:     .res 12
firePh:    .res 12
bflyX:     .res 8
bflyY:     .res 8
bflyPh:    .res 8
wthX:      .res 16
wthY:      .res 16
rainT:     .res 2                ; drizzle timer (0 = none)
ambInit:   .res 1

.code
; ------------------------------------------------------------
; applyMood: bank1 <- level's terrain mood (with season override)
; ------------------------------------------------------------
applyMood:
	ldx level
	lda lvMood,x
	cmp #MOOD_DAY
	bne @notDay
	lda tier
	beq @day
	cmp #1
	beq @autumn
	lda #<palWinter
	sta srcP
	lda #>palWinter
	sta srcP+1
	bra @copy
@autumn:
	lda #<palAutumn
	sta srcP
	lda #>palAutumn
	sta srcP+1
	bra @copy
@day:
	lda #<palDay
	sta srcP
	lda #>palDay
	sta srcP+1
	bra @copy
@notDay:
	cmp #MOOD_GOLDEN
	bne :+
	lda #<palGolden
	sta srcP
	lda #>palGolden
	sta srcP+1
	bra @copy
:	cmp #MOOD_DUSK
	bne :+
	lda #<palDusk
	sta srcP
	lda #>palDusk
	sta srcP+1
	bra @copy
:	lda #<palNight
	sta srcP
	lda #>palNight
	sta srcP+1
@copy:
	VSET (VRAM_PALETTE+32), VINC_1   ; bank 1
	ldy #0
:	lda (srcP),y
	sta VERA_DATA0
	iny
	cpy #32
	bne :-
	stz driftL
	stz driftH
	lda #$FF
	sta fadeSeg
	stz ambInit
	rts

; ------------------------------------------------------------
; palLerp: bank1 <- lerp(srcP, dstP, tmp3=frac 0..16), 16 colors
; ------------------------------------------------------------
palLerp:
	VSET (VRAM_PALETTE+32), VINC_1
	ldy #0
@pair:
	; byte0: G<<4 | B
	lda (srcP),y
	pha
	and #$0F
	sta tmpLo                    ; aB
	pla
	lsr
	lsr
	lsr
	lsr
	sta tmpHi                    ; aG
	lda (dstP),y
	pha
	and #$0F
	sta tmp                      ; bB
	pla
	lsr
	lsr
	lsr
	lsr
	sta tmp2                     ; bG
	; g
	lda tmpHi
	ldx tmp2
	jsr nibLerp
	asl
	asl
	asl
	asl
	sta tmpHi                    ; out G<<4
	lda tmpLo
	ldx tmp
	jsr nibLerp
	ora tmpHi
	sta VERA_DATA0
	iny
	; byte1: R
	lda (srcP),y
	and #$0F
	sta tmpLo
	lda (dstP),y
	and #$0F
	tax
	lda tmpLo
	jsr nibLerp
	sta VERA_DATA0
	iny
	cpy #32
	bne @pair
	rts

; nibLerp: A = a + (X-a)*frac/16   (frac in tmp3)
nibLerp:
	sta mulA                     ; a
	stx mulA+1                   ; b
	txa
	sec
	sbc mulA                     ; b-a (signed)
	php
	bpl :+
	eor #$FF
	inc a
:	; A = |b-a| ; multiply by frac via loop
	sta mulR
	lda #0
	ldx tmp3
	beq @zero
@acc:
	clc
	adc mulR
	dex
	bne @acc
@zero:
	lsr
	lsr
	lsr
	lsr                          ; /16
	plp
	bpl @add
	; negative delta
	sta mulR
	lda mulA
	sec
	sbc mulR
	rts
@add:
	clc
	adc mulA
	rts

; ------------------------------------------------------------
; lightTick: per-level light behaviour
; ------------------------------------------------------------
lightTick:
	ldx level
	lda lvType,x
	cmp #LT_ESCORT
	bne :+
	jmp nightCircle
:	cmp #LT_CHASE
	bne :+
	jmp chaseFade
:	; slow light drift: day -> golden / golden -> dusk / dusk -> night
	inc driftL
	bne :+
	inc driftH
:	lda driftL
	bne @done
	lda driftH
	and #3
	bne @done
	; every 1024 frames: frac = driftH>>2, capped 16
	lda driftH
	lsr
	lsr
	cmp #17
	bcc :+
	lda #16
:	sta tmp3
	ldx level
	lda lvMood,x
	cmp #MOOD_DAY
	bne @g2d
	; day (respect season) -> golden
	lda tier
	bne @done                    ; seasons hold their own light
	lda #<palDay
	sta srcP
	lda #>palDay
	sta srcP+1
	lda #<palGolden
	sta dstP
	lda #>palGolden
	sta dstP+1
	jmp palLerp
@g2d:
	cmp #MOOD_GOLDEN
	bne @d2n
	lda #<palGolden
	sta srcP
	lda #>palGolden
	sta srcP+1
	lda #<palDusk
	sta dstP
	lda #>palDusk
	sta dstP+1
	jmp palLerp
@d2n:
	cmp #MOOD_DUSK
	bne @done
	lda #<palDusk
	sta srcP
	lda #>palDusk
	sta srcP+1
	lda #<palNight
	sta dstP
	lda #>palNight
	sta dstP+1
	jmp palLerp
@done:
	rts

; ---- chase: crossfade day->golden->dusk->night across the run ----
chaseFade:
	lda frame
	and #7
	beq :+
	rts
:	; t = camX >> 5  (0..63);  seg = t>>4, frac = t&15
	lda camX+1
	sta tmpHi
	lda camX
	sta tmpLo
	ldx #5
:	lsr tmpHi
	ror tmpLo
	dex
	bne :-
	lda tmpLo
	lsr
	lsr
	lsr
	lsr
	cmp #3
	bcc :+
	lda #3
:	pha
	lda tmpLo
	and #15
	sta tmp3
	pla
	tax
	lda fadePalLo,x
	sta srcP
	lda fadePalHi,x
	sta srcP+1
	lda fadePalLo+1,x
	sta dstP
	lda fadePalHi+1,x
	sta dstP+1
	jmp palLerp

.rodata
fadePalLo: .byte <palDay,<palGolden,<palDusk,<palNight,<palNight
fadePalHi: .byte >palDay,>palGolden,>palDusk,>palNight,>palNight
.code

; ---- Grandfather's Gate: per-tile light circle around Peter ----
nightCircle:
	; Peter cell
	lda axH+SL_PETER
	sta tmpHi
	lda axL+SL_PETER
	ldx #3
:	lsr tmpHi
	ror
	dex
	bne :-
	sta tmp                      ; petCol
	lda ayH+SL_PETER
	sta tmpHi
	lda ayL+SL_PETER
	ldx #3
:	lsr tmpHi
	ror
	dex
	bne :-
	sta tmp2                     ; petRow
	; camera cell origin
	lda camX+1
	sta tmpHi
	lda camX
	ldx #3
:	lsr tmpHi
	ror
	dex
	bne :-
	sta cellX                    ; camCol
	lda camY+1
	sta tmpHi
	lda camY
	ldx #3
:	lsr tmpHi
	ror
	dex
	bne :-
	sta cellY                    ; camRow
	; alternate row parity per frame
	lda frame
	and #1
	sta tmp3
	; rows 0..31
	ldy #0
@row:
	tya
	and #1
	cmp tmp3
	beq @doRow
	jmp @nextRow
@doRow:
	; rowd = |camRow + y - petRow|
	tya
	clc
	adc cellY
	sec
	sbc tmp2
	bpl :+
	eor #$FF
	inc a
:	sta dyL                      ; rowd
	; VRAM addr: entry = (camRow+y)*128 + camCol -> byte addr *2 +1
	tya
	clc
	adc cellY
	sta VERA_ADDR_M              ; row (narrow map: 256 bytes/row)
	lda cellX
	asl
	ora #1
	sta VERA_ADDR_L
	stz VERA_CTRL
	lda #VINC_2
	sta VERA_ADDR_H
	; d = camCol - petCol (signed, walks +1 per col)
	lda cellX
	sec
	sbc tmp
	sta dxL
	ldx #41
@col:
	; band = max(|d|, rowd)
	lda dxL
	bpl :+
	eor #$FF
	inc a
:	cmp dyL
	bcs :+
	lda dyL
:	cmp #5
	bcc @lit
	cmp #9
	bcc @dim
	lda #$60
	bra @put
@dim:
	lda #$50
	bra @put
@lit:
	lda #$40
@put:
	sta VERA_DATA0
	inc dxL
	dex
	bne @col
@nextRow:
	iny
	cpy #32
	bne @row
	rts

; ------------------------------------------------------------
; drawActors: compose sprites 0..7 (+ overlays)
; ------------------------------------------------------------
.rodata
typeAnchX: .byte 0, 16, 32, 16, 8, 8, 10, 10, 8
typeAnchY: .byte 0, 25, 26, 14, 14, 15, 26, 26, 14
.code

; worldToScreen: slot X -> spXL/H, spYL/H (anchored). C=1 offscreen.
worldToScreen:
	phy
	ldy atype,x
	sec
	lda axL,x
	sbc camX
	sta spXL
	lda axH,x
	sbc camX+1
	sta spXH
	sec
	lda spXL
	sbc typeAnchX,y
	sta spXL
	bcs :+
	dec spXH
:	sec
	lda ayL,x
	sbc camY
	sta spYL
	lda ayH,x
	sbc camY+1
	sta spYH
	sec
	lda spYL
	sbc typeAnchY,y
	sta spYL
	bcs :+
	dec spYH
:	ply
	; visibility: spX+64 in 0..447, spY+64 in 0..351
	clc
	lda spXL
	adc #64
	tay
	lda spXH
	adc #0
	beq @xok                     ; 0..255-64
	cmp #1
	bne @off
	cpy #192
	bcs @off
@xok:
	clc
	lda spYL
	adc #64
	tay
	lda spYH
	adc #0
	beq @yok
	cmp #1
	bne @off
	cpy #96
	bcs @off
@yok:
	clc
	rts
@off:
	sec
	rts

drawActors:
	stz tmp2                     ; excl target found? bit0 excl, bit1 zzz
	ldx #0
@slot:
	stx spIdx
	lda atype,x
	bne @live
	jsr sprHide
	jmp @next
@live:
	; night: wolves outside the light are unseen
	phx
	ldy level
	lda lvType,y
	cmp #LT_ESCORT
	bne @vis2
	plx
	phx
	lda atype,x
	cmp #AT_WOLF
	bne @vis2
	ldy #SL_PETER
	jsr actorDist
	lda distH
	bne @hideN
	lda distL
	cmp #72
	bcc @vis2
@hideN:
	plx
	jsr sprHide
	jmp @next
@vis2:
	plx
	jsr worldToScreen
	bcc @on
	jsr sprHide
	jmp @next
@on:
	jsr actorFrame               ; A = frame, tmp = flags, tmp3 = bank override(0=none)
	sta spFrame
	lda tmp
	sta spFlags
	jsr sprPut
	; palette override (stunned wolf)?
	lda tmp3
	beq @next
	; rewrite shadow byte 7: size bits | override bank
	lda spIdx
	stz tmpHi
	asl
	rol tmpHi
	asl
	rol tmpHi
	asl
	rol tmpHi
	clc
	adc #<sprShadow
	sta dstP
	lda tmpHi
	adc #>sprShadow
	sta dstP+1
	ldy spFrame
	lda sprFrameSz,y
	and #$F0
	ora tmp3
	ldy #7
	sta (dstP),y
@next:
	inx
	cpx #8
	beq @overlays
	jmp @slot
@overlays:
	jmp drawOverlays

; actorFrame: X=slot -> A=frame id, tmp=flags(z|flip), tmp3=bank override
actorFrame:
	stz tmp3
	lda #Z_NORM
	sta tmp
	; flip if facing right (all art faces left; Peter D/U don't flip)
	lda atype,x
	cmp #AT_PETER
	beq @peter
	ldy aface,x
	beq :+
	lda tmp
	ora #1
	sta tmp
:	lda atype,x
	cmp #AT_WOLF
	bne :+
	jmp @wolf
:	cmp #AT_CAT
	bne :+
	jmp @cat
:	cmp #AT_BIRD
	beq @toBird
	cmp #AT_SCOUT
	bne :+
@toBird:
	jmp @bird
:	cmp #AT_DUCK
	bne :+
	jmp @duck
:	cmp #AT_GRANDPA
	bne :+
	jmp @grandpa
:	; hunter
	lda aanim,x
	and #8
	beq :+
	lda #FR_HUNTER_2
	rts
:	lda #FR_HUNTER_1
	rts
@peter:
	; direction frames; side view flips for right
	lda petDir
	cmp #2
	bcc @pdu
	; left/right
	lda petDir
	cmp #3
	bne :+
	lda tmp
	ora #1
	sta tmp
:	lda aanim,x
	and #8
	beq :+
	lda #FR_PETER_L2
	rts
:	lda #FR_PETER_L1
	rts
@pdu:
	lda petDir
	bne @pup
	lda aanim,x
	and #8
	beq :+
	lda #FR_PETER_D2
	rts
:	lda #FR_PETER_D1
	rts
@pup:
	lda aanim,x
	and #8
	beq :+
	lda #FR_PETER_U2
	rts
:	lda #FR_PETER_U1
	rts
@wolf:
	lda astate,x
	cmp #WS_HANG
	bne :+
	lda tmp
	ora #2                       ; vflip: upside-down from the branch
	sta tmp
	lda #FR_WOLF_L1
	rts
:	cmp #WS_CROUCH
	bne :+
	lda #FR_WOLF_CROUCH
	rts
:	cmp #WS_POUNCE
	bne :+
	lda #FR_WOLF_POUNCE
	rts
:	cmp #WS_STUN
	bne @wwalk
	lda #9                       ; gray bank
	sta tmp3
@wwalk:
	lda aanim,x
	and #8
	beq :+
	lda #FR_WOLF_L2
	rts
:	lda #FR_WOLF_L1
	rts
@cat:
	lda astate,x
	cmp #WS_CROUCH
	bne :+
	lda #FR_CAT_CREEP
	rts
:	cmp #WS_STUN
	bne @cwalk
	lda #9
	sta tmp3
@cwalk:
	lda aanim,x
	and #8
	beq :+
	lda #FR_CAT_L2
	rts
:	lda #FR_CAT_L1
	rts
@bird:
	lda aanim,x
	and #4
	beq :+
	lda #FR_BIRD_2
	rts
:	lda #FR_BIRD_1
	rts
@duck:
	lda aanim,x
	and #8
	beq :+
	lda #FR_DUCK_2
	rts
:	lda #FR_DUCK_1
	rts
@grandpa:
	lda aanim,x
	and #8
	beq :+
	lda #FR_GRANDPA_2
	rts
:	lda #FR_GRANDPA_1
	rts

; overlays: ❗ over a crouching foe, Zzz over a stunned one, ♪ over Peter
drawOverlays:
	; excl
	lda #SPI_EXCL
	sta spIdx
	ldx #SL_FOE1
@exclScan:
	lda atype,x
	beq @exclNext
	lda astate,x
	cmp #WS_CROUCH
	beq @exclShow
@exclNext:
	inx
	cpx #SL_FOE3+1
	bne @exclScan
	jsr sprHide
	bra @zzz
@exclShow:
	jsr worldToScreen
	bcs @zzzHideFirst
	; above the head
	sec
	lda spYL
	sbc #10
	sta spYL
	bcs :+
	dec spYH
:	clc
	lda spXL
	adc #28
	sta spXL
	bcc :+
	inc spXH
:	lda frame
	and #4
	beq @exclBlink
	lda #FR_EXCL
	sta spFrame
	lda #Z_NORM
	sta spFlags
	jsr sprPut
	bra @zzz
@exclBlink:
	jsr sprHide
	bra @zzz
@zzzHideFirst:
	jsr sprHide
@zzz:
	lda #SPI_ZZZ
	sta spIdx
	ldx #SL_FOE1
@zzzScan:
	lda atype,x
	beq @zzzNext
	lda astate,x
	cmp #WS_STUN
	beq @zzzShow
@zzzNext:
	inx
	cpx #SL_FOE3+1
	bne @zzzScan
	jsr sprHide
	bra @note
@zzzShow:
	jsr worldToScreen
	bcs @noteHideFirst
	sec
	lda spYL
	sbc #8
	sta spYL
	bcs :+
	dec spYH
:	clc
	lda spXL
	adc #24
	sta spXL
	bcc :+
	inc spXH
:	lda #FR_ZZZ
	sta spFrame
	lda #Z_NORM
	sta spFlags
	jsr sprPut
	bra @note
@noteHideFirst:
	jsr sprHide
@note:
	; whistle note above Peter for ~24 frames after whistling
	lda #SPI_NOTE
	sta spIdx
	lda whistleCd+1
	beq @noteHide
	lda whistleCd
	cmp #<236
	bcc @noteHide
	ldx #SL_PETER
	jsr worldToScreen
	bcs @noteHide
	sec
	lda spYL
	sbc #6
	sta spYL
	bcs :+
	dec spYH
:	clc
	lda spXL
	adc #20
	sta spXL
	bcc :+
	inc spXH
:	lda #FR_NOTE
	sta spFrame
	lda #Z_NORM
	sta spFlags
	jmp sprPut
@noteHide:
	jmp sprHide

; ------------------------------------------------------------
; drawApples: world apples, thrown apples, rope & noose
; ------------------------------------------------------------
drawApples:
	; world apples -> sprites 16..25
	ldx #0
@wa:
	txa
	clc
	adc #SPI_APPLES
	sta spIdx
	cpx appleCnt
	bcs @waHide
	lda appleNum,x
	beq @waHide
	; position
	sec
	lda appleXL,x
	sbc camX
	sta spXL
	lda appleXH,x
	sbc camX+1
	sta spXH
	sec
	lda spXL
	sbc #8
	sta spXL
	bcs :+
	dec spXH
:	sec
	lda appleYL,x
	sbc camY
	sta spYL
	lda #0
	sbc camY+1
	sta spYH
	sec
	lda spYL
	sbc #10
	sta spYL
	bcs :+
	dec spYH
:	; frame: numbered or plain
	lda appleNum,x
	cmp #$FF
	beq @plain
	clc
	adc #FR_APPLE1-1
	bra @waf
@plain:
	lda #FR_APPLE
@waf:
	sta spFrame
	lda #Z_NORM
	sta spFlags
	; the next numbered apple pulses (blink its sprite)
	lda appleNum,x
	cmp nextApple
	bne @waPut
	lda frame
	and #16
	beq @waPut
	; brighten: flip h to shimmer (cheap pulse)
	lda #(Z_NORM|1)
	sta spFlags
@waPut:
	jsr sprPut
	bra @waNext
@waHide:
	jsr sprHide
@waNext:
	inx
	cpx #10
	bne @wa

	; thrown apples -> sprites 11..14
	ldx #0
@ta:
	txa
	clc
	adc #SPI_THROWN
	sta spIdx
	lda thLife,x
	beq @taHide
	sec
	lda thXL,x
	sbc camX
	sta spXL
	lda thXH,x
	sbc camX+1
	sta spXH
	sec
	lda thYL,x
	sbc camY
	sta spYL
	lda thYH,x
	sbc camY+1
	sta spYH
	sec
	lda spXL
	sbc #8
	sta spXL
	bcs :+
	dec spXH
:	sec
	lda spYL
	sbc #8
	sta spYL
	bcs :+
	dec spYH
:	lda #FR_APPLE
	sta spFrame
	lda #Z_NORM
	sta spFlags
	jsr sprPut
	bra @taNext
@taHide:
	jsr sprHide
@taNext:
	inx
	cpx #NTHROWN
	bne @ta

	; dropped rope
	lda #SPI_ROPE
	sta spIdx
	lda ropeDropped
	beq @ropeHide
	sec
	lda ropeDropXL
	sbc camX
	sta spXL
	lda ropeDropXH
	sbc camX+1
	sta spXH
	sec
	lda ropeDropYL
	sbc camY
	sta spYL
	lda #0
	sbc camY+1
	sta spYH
	lda #FR_ROPECOIL
	sta spFrame
	lda #Z_NORM
	sta spFlags
	jsr sprPut
	bra @noose
@ropeHide:
	jsr sprHide
@noose:
	; snare noose hangs at the oak when armed
	lda #SPI_NOOSE
	sta spIdx
	lda snareArmed
	beq @nooseHide
	sec
	lda oakXL
	sbc camX
	sta spXL
	lda oakXH
	sbc camX+1
	sta spXH
	sec
	lda oakYL
	sbc camY
	sta spYL
	lda #0
	sbc camY+1
	sta spYH
	sec
	lda spYL
	sbc #40
	sta spYL
	bcs :+
	dec spYH
:	; sway
	lda frame
	lsr
	lsr
	lsr
	and #15
	tay
	lda sinTab,y
	cmp #$80
	bcs @swayL
	lsr
	lsr
	clc
	adc spXL
	sta spXL
	bcc @sw2
	inc spXH
	bra @sw2
@swayL:
	eor #$FF
	inc a
	lsr
	lsr
	sta tmp
	sec
	lda spXL
	sbc tmp
	sta spXL
	bcs @sw2
	dec spXH
@sw2:
	lda #FR_NOOSE
	sta spFrame
	lda #Z_NORM
	sta spFlags
	jmp sprPut
@nooseHide:
	jmp sprHide

; ------------------------------------------------------------
; ambientTick: fireflies / butterflies / weather / dove
; ------------------------------------------------------------
ambientTick:
	lda ambInit
	bne @tick
	inc ambInit
	; scatter ambient particles
	ldx #11
@fi:
	jsr rnd
	sta fireX,x
	jsr rnd
	and #15
	sta firePh,x
	jsr rnd
	lsr
	clc
	adc #40
	sta fireY,x
	dex
	bpl @fi
	ldx #7
@bi:
	jsr rnd
	sta bflyX,x
	jsr rnd
	and #15
	sta bflyPh,x
	jsr rnd
	lsr
	clc
	adc #60
	sta bflyY,x
	dex
	bpl @bi
	ldx #15
@wi:
	jsr rnd
	sta wthX,x
	jsr rnd
	cmp #240
	bcc :+
	lda #100
:	sta wthY,x
	dex
	bpl @wi
	stz rainT
	stz rainT+1
@tick:
	; fireflies on dusk/night levels
	ldx level
	lda lvMood,x
	cmp #MOOD_DUSK
	bcs @fire
	; hide firefly sprites by day
	ldx #11
@fh:
	txa
	clc
	adc #SPI_FIRE
	sta spIdx
	jsr sprHide
	dex
	bpl @fh
	bra @bflies
@fire:
	ldx #11
@ff:
	txa
	clc
	adc #SPI_FIRE
	sta spIdx
	; drift with sine wobble, blink
	lda frame
	lsr
	lsr
	clc
	adc firePh,x
	and #15
	tay
	lda sinTab,y
	cmp #$80
	bcs @fneg
	lsr
	lsr
	clc
	adc fireX,x
	bra @fx
@fneg:
	eor #$FF
	inc a
	lsr
	lsr
	sta tmp
	lda fireX,x
	sec
	sbc tmp
@fx:
	sta spXL
	stz spXH
	lda fireY,x
	sta spYL
	stz spYH
	; blink: hide 1/4 of the time
	lda frame
	lsr
	lsr
	lsr
	clc
	adc firePh,x
	and #7
	beq @fhide
	lda #FR_FIREFLY
	sta spFrame
	lda #%00001100               ; z=3: above everything (glow)
	sta spFlags
	jsr sprPut
	bra @fnext
@fhide:
	jsr sprHide
@fnext:
	; slow wander
	lda frame
	and #7
	bne :+
	inc fireX,x
:	dex
	bpl @ff
@bflies:
	; butterflies by day/golden
	ldx level
	lda lvMood,x
	cmp #MOOD_DUSK
	bcc @bshow
	ldx #7
@bh:
	txa
	clc
	adc #SPI_BFLY
	sta spIdx
	jsr sprHide
	dex
	bpl @bh
	bra @weather
@bshow:
	ldx #7
@bf:
	txa
	clc
	adc #SPI_BFLY
	sta spIdx
	lda frame
	lsr
	clc
	adc bflyPh,x
	and #15
	tay
	lda sinTab,y
	cmp #$80
	bcs @bneg
	lsr
	clc
	adc bflyX,x
	bra @bx
@bneg:
	eor #$FF
	inc a
	lsr
	sta tmp
	lda bflyX,x
	sec
	sbc tmp
@bx:
	sta spXL
	stz spXH
	lda bflyY,x
	sta spYL
	stz spYH
	lda frame
	and #4
	beq :+
	lda #FR_BUTTERFLY_1
	bra :++
:	lda #FR_BUTTERFLY_2
:	sta spFrame
	lda #Z_NORM
	sta spFlags
	jsr sprPut
	; drift
	lda frame
	and #15
	bne :+
	inc bflyX,x
:	dex
	bpl @bf
@weather:
	jmp weatherTick

; weather: autumn leaves / winter snow / occasional drizzle
weatherTick:
	; drizzle trigger (rare, day/golden moods only)
	lda rainT
	ora rainT+1
	bne @rainOn
	jsr rnd
	bne @kind
	jsr rnd
	cmp #24
	bcs @kind
	lda #<1200
	sta rainT
	lda #>1200
	sta rainT+1
@kind:
	lda tier
	bne @seasonal
	; storybook tier: nothing falling (unless raining)
	ldx #15
@wh:
	txa
	clc
	adc #SPI_WEATHER
	sta spIdx
	jsr sprHide
	dex
	bpl @wh
	rts
@rainOn:
	lda rainT
	bne :+
	dec rainT+1
:	dec rainT
	ldx #15
@rain:
	txa
	clc
	adc #SPI_WEATHER
	sta spIdx
	lda wthY,x
	clc
	adc #6
	sta wthY,x
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
	lda #FR_SPARKLE
	sta spFrame
	lda #%00001100
	sta spFlags
	jsr sprPut
	dex
	bpl @rain
	rts
@seasonal:
	ldx #15
@fall:
	txa
	clc
	adc #SPI_WEATHER
	sta spIdx
	; fall speed: leaves 1px + sway, snow 1px
	lda frame
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
:	; sway
	lda frame
	lsr
	lsr
	clc
	adc wthX,x
	and #63
	lsr
	lsr
	lsr                          ; 0..7 sway
	clc
	adc wthX,x
	sta spXL
	stz spXH
	lda wthY,x
	sta spYL
	stz spYH
	lda tier
	cmp #2
	beq @snow
	lda #FR_DOTORANGE
	bra @wput
@snow:
	lda #FR_DOTWHITE
@wput:
	sta spFrame
	lda #%00001100
	sta spFlags
	jsr sprPut
	dex
	bpl @fall
	rts
