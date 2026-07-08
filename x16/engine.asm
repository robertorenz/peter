; ============================================================
;  engine.asm — VERA setup, sprites, camera, input, text, math
; ============================================================

NSPR = 112                       ; sprites we manage (of 128)

.bss
sprShadow:  .res 1024            ; sprite attributes (NSPR*8 used), flushed each frame
worldWL:    .res 1               ; world size in pixels
worldWH:    .res 1
worldHL:    .res 1
worldHH:    .res 1
mapWide:    .res 1               ; 0 = 128x64 map, 1 = 256x32 (chase)
camMaxXL:   .res 1               ; worldW - 320
camMaxXH:   .res 1
camMaxYL:   .res 1               ; worldH - 240
camMaxYH:   .res 1

.code

; ------------------------------------------------------------
; videoInit: 320x240, layer1 text HUD, layer0 4bpp tile world
; ------------------------------------------------------------
videoInit:
	stz VERA_CTRL
	lda #64
	sta VERA_DC_HSCALE
	sta VERA_DC_VSCALE

	lda #%00010000               ; 1bpp text 16-col, map 64x32
	sta VERA_L1_CONFIG
	lda #(VRAM_HUDMAP >> 9)
	sta VERA_L1_MAPBASE
	lda #((VRAM_CHARSET >> 11) << 2)
	sta VERA_L1_TILEBASE
	stz VERA_L1_HSCROLL_L
	stz VERA_L1_HSCROLL_H
	stz VERA_L1_VSCROLL_L
	stz VERA_L1_VSCROLL_H

	lda #%01100010               ; 4bpp tiles, map 128x64
	sta VERA_L0_CONFIG
	lda #(VRAM_MAP >> 9)
	sta VERA_L0_MAPBASE
	lda #((VRAM_TILES >> 11) << 2)
	sta VERA_L0_TILEBASE
	stz VERA_L0_HSCROLL_L
	stz VERA_L0_HSCROLL_H
	stz VERA_L0_VSCROLL_L
	stz VERA_L0_VSCROLL_H

	lda #%01110001               ; VGA + L0 + L1 + sprites
	sta VERA_DC_VIDEO
	rts

; ------------------------------------------------------------
; uploadAssets: tile + sprite data and palette into VRAM
; ------------------------------------------------------------
uploadAssets:
	lda #<tileData
	sta srcP
	lda #>tileData
	sta srcP+1
	VSET VRAM_TILES, VINC_1
	ldx #<TILE_DATA_LEN
	ldy #>TILE_DATA_LEN
	jsr copyToVram

	lda #<sprData
	sta srcP
	lda #>sprData
	sta srcP+1
	VSET VRAM_SPRITES, VINC_1
	ldx #<SPR_DATA_LEN
	ldy #>SPR_DATA_LEN
	jsr copyToVram

	lda #<paletteData
	sta srcP
	lda #>paletteData
	sta srcP+1
	VSET VRAM_PALETTE, VINC_1
	ldx #<512
	ldy #>512
	; fall through

; copyToVram: srcP -> DATA0, X=len lo, Y=len hi
copyToVram:
	cpy #0
	beq @tail
	phy
	ldy #0
@page:
	lda (srcP),y
	sta VERA_DATA0
	iny
	bne @page
	inc srcP+1
	ply
	dey
	bne @pageNext
	bra @tail
@pageNext:
	phy
	ldy #0
	bra @page
@tail:
	cpx #0
	beq @done
	ldy #0
@rest:
	lda (srcP),y
	sta VERA_DATA0
	iny
	dex
	bne @rest
@done:
	rts

; ------------------------------------------------------------
; sprites: shadow table, composed by sprPut, flushed per frame
; ------------------------------------------------------------
clearSprShadow:
	lda #<sprShadow
	sta dstP
	lda #>sprShadow
	sta dstP+1
	ldx #4                       ; 1024 bytes
	ldy #0
	tya
@clr:
	sta (dstP),y
	iny
	bne @clr
	inc dstP+1
	dex
	bne @clr
	; and the real attribute VRAM — random at power-on, all 128 sprites
	VSET VRAM_SPRATTR, VINC_1
	ldx #4
	ldy #0
	lda #0
@vclr:
	sta VERA_DATA0
	iny
	bne @vclr
	dex
	bne @vclr
	rts

flushSprites:
	VSET VRAM_SPRATTR, VINC_1
	lda #<sprShadow
	sta srcP
	lda #>sprShadow
	sta srcP+1
	ldx #(NSPR*8)/256
	ldy #0
@page:
	lda (srcP),y
	sta VERA_DATA0
	iny
	bne @page
	inc srcP+1
	dex
	bne @page
	ldy #0
@tail:
	cpy #(NSPR*8) & 255
	beq @done
	lda (srcP),y
	sta VERA_DATA0
	iny
	bra @tail
@done:
	rts

; sprPut: write one sprite from spIdx/spFrame/spX/spY/spFlags
; (preserves X and Y — every caller loops on them)
sprPut:
	phx
	phy
	lda spIdx
	stz tmpHi
	asl
	rol tmpHi
	asl
	rol tmpHi
	asl
	rol tmpHi                    ; idx*8 (16-bit)
	clc
	adc #<sprShadow
	sta dstP
	lda tmpHi
	adc #>sprShadow
	sta dstP+1
	ldx spFrame
	ldy #0
	lda sprFrameA0,x
	sta (dstP),y
	iny
	lda sprFrameA1,x
	sta (dstP),y
	iny
	lda spXL
	sta (dstP),y
	iny
	lda spXH
	and #$03
	sta (dstP),y
	iny
	lda spYL
	sta (dstP),y
	iny
	lda spYH
	and #$03
	sta (dstP),y
	iny
	lda spFlags
	sta (dstP),y
	iny
	lda sprFrameSz,x
	sta (dstP),y
	ply
	plx
	rts

; sprHide: hide sprite spIdx (z = 0); preserves X and Y
sprHide:
	phy
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
	ldy #6
	lda #0
	sta (dstP),y
	ply
	rts

; ------------------------------------------------------------
; camera: follow (camTX,camTY) softly; write scroll registers
; ------------------------------------------------------------
.bss
camTX:      .res 2
camTY:      .res 2
.code

applyCamera:
	lda camX
	sta VERA_L0_HSCROLL_L
	lda camX+1
	sta VERA_L0_HSCROLL_H
	lda camY
	sta VERA_L0_VSCROLL_L
	lda camY+1
	sta VERA_L0_VSCROLL_H
	rts

; camTick: camX += (camTX-camX)/8 (per axis, 16-bit)
camTick:
	; X axis
	sec
	lda camTX
	sbc camX
	sta tmpLo
	lda camTX+1
	sbc camX+1
	sta tmpHi
	jsr asr3_16
	clc
	lda camX
	adc tmpLo
	sta camX
	lda camX+1
	adc tmpHi
	sta camX+1
	; Y axis
	sec
	lda camTY
	sbc camY
	sta tmpLo
	lda camTY+1
	sbc camY+1
	sta tmpHi
	jsr asr3_16
	clc
	lda camY
	adc tmpLo
	sta camY
	lda camY+1
	adc tmpHi
	sta camY+1
	rts

; arithmetic shift right x3 of tmpHi:tmpLo (signed)
asr3_16:
	ldx #3
@s:
	lda tmpHi
	asl                          ; copy sign into carry
	ror tmpHi
	ror tmpLo
	dex
	bne @s
	rts

; ------------------------------------------------------------
; input: KERNAL joystick 0 + GETIN character
; ------------------------------------------------------------
.bss
attract:   .res 1                ; demo mode: the game plays itself
idleT:     .res 2
autoPX:    .res 1                ; autopilot stuck detection
autoPY:    .res 1
autoStk:   .res 1
detourT:   .res 1                ; frames left in a committed detour
detourDir: .res 1                ; rotating 0..3
lastKey:   .res 1                ; DIAG
lastJoyB:  .res 1                ; DIAG: last non-$FF hardware joyB
humanT:    .res 1                ; consecutive human-input frames
humanPrev: .res 1
killVal:   .res 1                ; DIAG
killCnt:   .res 1                ; DIAG
.code

.rodata
Sidestep: .byte <~JB_UP, <~JB_RIGHT, <~JB_DOWN, <~JB_LEFT
.code

readInput:
	lda joyB
	sta joyBPrev
	lda joyX
	sta joyXPrev
	php
	sei                          ; atomic vs the KERNAL's IRQ scan
	lda #0
	jsr JOYSTICK_GET
	plp
	sta joyB
	stx joyX
	; a human touch ends attract: the SAME single button seen on two
	; consecutive frames (filters the phantom multi-bit noise)
	lda joyB
	and joyX
	eor #$FF                     ; pressed bits
	beq @noHuman
	tay
	; single bit?  (p & (p-1)) == 0
	sec
	sbc #1
	sta tmp
	tya
	and tmp
	bne @noHuman
	tya
	cmp humanPrev
	bne @firstSeen
	inc humanT
	lda humanT
	cmp #2
	bcc @edges
	sty killVal                  ; DIAG: what killed attract
	inc killCnt
	stz attract
	bra @edges
@firstSeen:
	sty humanPrev
	lda #1
	sta humanT
	bra @edges
@noHuman:
	stz humanT
	stz humanPrev
	lda attract
	beq @edges
	jsr autoPilot
@edges:
	; active low: pressed-now = ~joy; edge = changed & pressed-now
	lda joyBPrev
	eor joyB
	sta tmp
	lda joyB
	eor #$FF
	and tmp
	sta joyBEdge
	lda joyXPrev
	eor joyX
	sta tmp
	lda joyX
	eor #$FF
	and tmp
	sta joyXEdge
	php
	sei
	jsr GETIN
	plp
	sta keyChar                  ; (keys don't end attract — joystick does)
	rts

; ------------------------------------------------------------
; autoPilot: synthesize joystick input during the demo
; ------------------------------------------------------------
autoPilot:
	lda gameState
	cmp #GS_PLAY
	beq @play
	; cards: press B briefly every ~2s
	lda frame
	and #127
	cmp #2
	bcs @done
	lda joyB
	and #<~JB_B
	sta joyB
@done:
	rts
@play:
	; mid-detour? commit to it — no re-aiming into the same tree
	lda detourT
	beq @chkStuck
	dec detourT
	ldx detourDir
	lda joyB
	and Sidestep,x
	sta joyB
	rts
@chkStuck:
	; stuck against something? start a long detour
	lda axL
	cmp autoPX
	bne @unstuck
	lda ayL
	cmp autoPY
	bne @unstuck
	inc autoStk
	lda autoStk
	cmp #40
	bcc @aim
	; commit: next direction in rotation, ~1.5 s
	stz autoStk
	lda #90
	sta detourT
	inc detourDir
	lda detourDir
	and #3
	sta detourDir
	rts
@unstuck:
	lda axL
	sta autoPX
	lda ayL
	sta autoPY
	stz autoStk
@aim:
	; walk toward the current objective
	jsr autoTarget               ; -> tgXL/H, tgYL/H
	ldx #SL_PETER
	jsr distToPoint
	; X axis
	lda dxH
	bne @moveX
	lda dxL
	cmp #4
	bcc @yAxis
@moveX:
	lda sgnX
	bmi @left
	lda joyB
	and #<~JB_RIGHT
	sta joyB
	bra @yAxis
@left:
	lda joyB
	and #<~JB_LEFT
	sta joyB
@yAxis:
	lda dyH
	bne @moveY
	lda dyL
	cmp #4
	bcc @acts
@moveY:
	lda sgnY
	bmi @up
	lda joyB
	and #<~JB_DOWN
	sta joyB
	bra @acts
@up:
	lda joyB
	and #<~JB_UP
	sta joyB
@acts:
	; near the target on the rope level? press the button (search/set)
	ldx level
	lda lvType,x
	cmp #LT_ROPE
	bne @acts2
	lda distH
	bne @acts2
	lda distL
	cmp #26
	bcs @acts2
	lda frame
	and #15
	bne @acts2
	lda joyB
	and #<~JB_B
	sta joyB
@acts2:
	; throw an apple when the wolf is close
	phx
	ldy #SL_PETER
	ldx #SL_FOE1
	lda atype,x
	beq @noFoe
	jsr actorDist
	lda distH
	bne @noFoe
	lda distL
	cmp #70
	bcs @noFoe
	lda frame
	and #31
	bne @noFoe
	lda joyB
	and #<~JB_B
	sta joyB
@noFoe:
	plx
	; whistle now and then
	lda frame
	bne :+
	lda joyX
	and #<~JX_A
	sta joyX
:	rts

; autoTarget: what is Peter after right now?
autoTarget:
	ldx level
	lda lvType,x
	cmp #LT_APPLES
	bne @notApples
	; next numbered apple (else the gate once open)
	ldx #9
@scan:
	lda appleNum,x
	cmp nextApple
	beq @apple
	dex
	bpl @scan
	jmp @goal
@apple:
	lda appleXL,x
	sta tgXL
	lda appleXH,x
	sta tgXH
	lda appleYL,x
	sta tgYL
	lda appleYH,x
	sta tgYH
	rts
@notApples:
	; rescue/escort: fetch the friend before heading for the goal
	cmp #LT_BIRD
	beq @friendFirst
	cmp #LT_DUCK
	beq @friendFirst
	cmp #LT_ESCORT
	beq @friendFirst
	cmp #LT_ROPE
	beq @ropePlan
	bra @goal
@friendFirst:
	lda atype+SL_FRIEND
	beq @goal
	lda astate+SL_FRIEND
	cmp #FS_FOLLOW
	beq @goal
	lda axL+SL_FRIEND
	sta tgXL
	lda axH+SL_FRIEND
	sta tgXH
	lda ayL+SL_FRIEND
	sta tgYL
	lda ayH+SL_FRIEND
	sta tgYH
	rts
@ropePlan:
	; no rope yet? search the rocks one by one
	lda carryRope
	bne @goal                    ; carrying (or set): head for the oak
	lda ropeDropped
	bne @dropped
	; nearest unsearched rock
	ldx rockCnt
	beq @goal
	dex
@rock:
	lda rockDone,x
	beq @thisRock
	dex
	bpl @rock
	bra @goal
@thisRock:
	lda rockXL,x
	sta tgXL
	lda rockXH,x
	sta tgXH
	lda rockYL,x
	sta tgYL
	lda rockYH,x
	sta tgYH
	rts
@dropped:
	lda ropeDropXL
	sta tgXL
	lda ropeDropXH
	sta tgXH
	lda ropeDropYL
	sta tgYL
	lda ropeDropYH
	sta tgYH
	rts
@goal:
	; oak/pond/gate by level type
	ldx level
	lda lvType,x
	cmp #LT_DUCK
	beq @pond
	cmp #LT_BIRD
	beq @oak
	cmp #LT_ROPE
	beq @oak
	cmp #LT_CHASE
	beq @oak
	; gate / endless: right edge middle
	lda #<1000
	sta tgXL
	lda #>1000
	sta tgXH
	lda #<240
	sta tgYL
	stz tgYH
	rts
@oak:
	lda oakXL
	sta tgXL
	lda oakXH
	sta tgXH
	lda oakYL
	clc
	adc #16
	sta tgYL
	stz tgYH
	rts
@pond:
	lda pondXL
	sta tgXL
	lda pondXH
	sta tgXH
	lda pondYL
	sta tgYL
	lda pondYH
	sta tgYH
	rts

; button masks (joyB, active low)
JB_RIGHT = $01
JB_LEFT  = $02
JB_DOWN  = $04
JB_UP    = $08
JB_START = $10
JB_SEL   = $20                   ; Left Shift = tip-toe
JB_Y     = $40
JB_B     = $80                   ; Z key = action
; joyX
JX_A     = $80                   ; X key = whistle
JX_X     = $40                   ; S key = drop rope

; ------------------------------------------------------------
; RNG: 16-bit LFSR
; ------------------------------------------------------------
rnd:
	lda rngHi
	lsr
	ror rngLo
	bcc @noEor
	eor #$B4
@noEor:
	sta rngHi
	lda rngLo
	rts

; rndMask: A = rnd & mask(X)
rndMask:
	jsr rnd
	txa
	and rngLo
	rts

; ------------------------------------------------------------
; distance: |dx|,|dy| -> approx dist = max + min/2 (16-bit)
; inputs dxL/H dyL/H (already absolute); result distL/H
; ------------------------------------------------------------
distApprox:
	; compare dx,dy
	lda dxH
	cmp dyH
	bne @cmpDone
	lda dxL
	cmp dyL
@cmpDone:
	bcs @dxBig
	; dy is max
	lda dxH
	lsr
	sta tmpHi
	lda dxL
	ror
	sta tmpLo
	clc
	lda dyL
	adc tmpLo
	sta distL
	lda dyH
	adc tmpHi
	sta distH
	rts
@dxBig:
	lda dyH
	lsr
	sta tmpHi
	lda dyL
	ror
	sta tmpLo
	clc
	lda dxL
	adc tmpLo
	sta distL
	lda dxH
	adc tmpHi
	sta distH
	rts

; absDiff16: (tmpLo/tmpHi = a-b) -> abs in tmpLo/tmpHi, sign in A ($01/$FF)
abs16:
	lda tmpHi
	bpl @pos
	sec
	lda #0
	sbc tmpLo
	sta tmpLo
	lda #0
	sbc tmpHi
	sta tmpHi
	lda #$FF
	rts
@pos:
	lda #$01
	rts

; ------------------------------------------------------------
; text
; ------------------------------------------------------------
; printAt: uppercase-ASCII 0-terminated string at (X=col, Y=row),
; color = textCol
printAt:
	stz VERA_CTRL
	tya
	lsr
	ora #>VRAM_HUDMAP
	sta VERA_ADDR_M
	lda #0
	ror
	sta tmp
	txa
	asl
	ora tmp
	sta VERA_ADDR_L
	lda #VINC_1
	sta VERA_ADDR_H
	ldy #0
@loop:
	lda (txtPtr),y
	beq @done
	and #$3F
	sta VERA_DATA0
	lda textCol
	sta VERA_DATA0
	iny
	bne @loop
@done:
	rts

; printMsg: A = message id.  Messages: .byte col,row,"TEXT",0
; (table msgPtrLo/msgPtrHi defined in hud.asm)
printMsg:
	tax
	lda msgPtrLo,x
	sta txtPtr
	lda msgPtrHi,x
	sta txtPtr+1
	lda (txtPtr)
	pha                          ; col
	ldy #1
	lda (txtPtr),y
	pha                          ; row
	clc
	lda txtPtr
	adc #2
	sta txtPtr
	bcc :+
	inc txtPtr+1
:	ply
	plx
	jmp printAt

; clearHudRow: Y=row, clears to spaces (color $01 on transparent)
clearHudRow:
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
	ldy #64
	lda #$20
@c:
	sta VERA_DATA0
	stz VERA_DATA0               ; color 0/0: transparent over world
	dey
	bne @c
	rts

clearHud:
	ldy #0
@row:
	phy
	jsr clearHudRow
	ply
	iny
	cpy #32
	bne @row
	rts

; hexOut: A -> two char+color cells via DATA0 (set ADDR + VINC_1 first)
hexOut:
	pha
	lsr
	lsr
	lsr
	lsr
	jsr @dig
	pla
	and #$0F
@dig:
	cmp #10
	bcc :+
	adc #6
:	adc #'0'
	and #$3F
	sta VERA_DATA0
	lda textCol
	sta VERA_DATA0
	rts
