; ============================================================
;  world.asm — level data, world builder, tile map, collision
; ============================================================

; level types
LT_APPLES  = 0                   ; ch1 The Meadow
LT_BIRD    = 1                   ; ch2 Save the Bird
LT_DUCK    = 2                   ; ch3 Rescue the Duck
LT_ROPE    = 3                   ; ch4 Trap the Wolf
LT_ESCORT  = 4                   ; ch5 Grandfather's Gate
LT_CHASE   = 5                   ; ch6 The Great Chase
LT_ENDLESS = 6                   ; Endless Dusk

; palette moods
MOOD_DAY    = 0
MOOD_GOLDEN = 1
MOOD_DUSK   = 2
MOOD_NIGHT  = 3

; feature script opcodes
OP_END  = 0
OP_POND = 1                      ; x,y,w,h (cells)
OP_TREE = 2                      ; x,y (canopy top-left)
OP_OAK  = 3                      ; x,y (the big snare oak)
OP_BUSH = 4                      ; x,y
OP_ROCK = 5                      ; x,y
OP_GATE = 6                      ; y (right edge, 4 cells tall)

; The world map reuses the asset blob's RAM: tileData+sprData (13.7KB)
; are dead weight once copied to VRAM at boot, and buildWorld runs after.
worldMap    = tileData           ; tile code per cell (128x64 or 256x32), 8KB

.bss
level:      .res 1               ; 0..6
round:      .res 1               ; 1.. (chapter cycle count)
tier:       .res 1               ; 0 storybook, 1 wild/autumn, 2 prokofiev/winter
terrBank:   .res 1               ; palette offset applied to terrain entries
; recorded features
appleXL:    .res 10              ; world px
appleXH:    .res 10
appleYL:    .res 10
appleYH:    .res 10
appleNum:   .res 10              ; 0 = gone, else 1..9 (or $FF ammo)
appleCnt:   .res 1
bushXL:     .res 6
bushXH:     .res 6
bushYL:     .res 6
bushYH:     .res 6
bushCnt:    .res 1
rockXL:     .res 8
rockXH:     .res 8
rockYL:     .res 8
rockYH:     .res 8
rockDone:   .res 8               ; 1 = searched
rockCnt:    .res 1
treeXL:     .res 16
treeXH:     .res 16
treeYL:     .res 16
treeYH:     .res 16
treeShake:  .res 16              ; shake cooldown (x4 frames)
treeCnt:    .res 1
oakXL:      .res 1               ; snare oak trunk center, world px
oakXH:      .res 1
oakYL:      .res 1
pondXL:     .res 1               ; pond center px
pondXH:     .res 1
pondYL:     .res 1
pondYH:     .res 1
gateRow:    .res 1               ; gate top cell row
gateOpenF:  .res 1
featW:      .res 1               ; feature painter locals (setCell-safe)
featH:      .res 1

.code

; ------------------------------------------------------------
; level tables
; ------------------------------------------------------------
.rodata
lvType:    .byte LT_APPLES, LT_BIRD, LT_DUCK, LT_ROPE, LT_ESCORT, LT_CHASE, LT_ENDLESS
lvWide:    .byte 0,0,0,0,0,1,0
lvMood:    .byte MOOD_DAY, MOOD_GOLDEN, MOOD_DUSK, MOOD_NIGHT, MOOD_NIGHT, MOOD_DAY, MOOD_DUSK
lvSong:    .byte SONG_PETER, SONG_BIRD, SONG_DUCK, SONG_WOLF, SONG_GRANDFATHER, SONG_PETER, SONG_WOLF
lvScrLo:   .byte <scrMeadow,<scrBird,<scrDuck,<scrRope,<scrEscort,<scrChase,<scrEndless
lvScrHi:   .byte >scrMeadow,>scrBird,>scrDuck,>scrRope,>scrEscort,>scrChase,>scrEndless
; wolf/cat base speed, 8.8 (int:frac). web speeds * 0.6.
lvFoeSpdL: .byte $E6, $E6, $EE, $E6, $DE, $F6, $DE
lvFoeSpdH: .byte 0,0,0,0,0,0,0
; vision radius / 2 (px): cat 235*0.6/2=70, wolf3 265*0.6/2=79, wolf5 215*0.6/2=64
lvVisH:    .byte 63, 70, 79, 63, 64, 90, 78
; starts (cells)
lvPeterX:  .byte 8,   8,   6,   8,   6,   4,  62
lvPeterY:  .byte 32,  40,  30,  32,  30,  16, 32
lvFoeX:    .byte 90,  100, 70,  100, 100, 30, 100
lvFoeY:    .byte 20,  16,  40,  40,  20,  16, 48

; ---- feature scripts (cells: x, y) ----
scrMeadow:
	.byte OP_POND, 96, 44, 15, 9
	.byte OP_OAK,  16, 18
	.byte OP_TREE, 34, 8
	.byte OP_TREE, 58, 14
	.byte OP_TREE, 80, 6
	.byte OP_TREE, 26, 44
	.byte OP_TREE, 48, 52
	.byte OP_TREE, 70, 34
	.byte OP_TREE, 100, 14
	.byte OP_TREE, 112, 34
	.byte OP_TREE, 8, 8
	.byte OP_BUSH, 40, 30
	.byte OP_BUSH, 66, 12
	.byte OP_BUSH, 88, 52
	.byte OP_BUSH, 20, 56
	.byte OP_ROCK, 52, 24
	.byte OP_ROCK, 78, 48
	.byte OP_ROCK, 30, 14
	.byte OP_GATE, 28
	.byte OP_END
scrBird:
	.byte OP_TREE, 104, 4       ; the tall oak (goal) — painted big below
	.byte OP_OAK,  108, 2
	.byte OP_TREE, 16, 12
	.byte OP_TREE, 30, 30
	.byte OP_TREE, 44, 10
	.byte OP_TREE, 60, 40
	.byte OP_TREE, 72, 18
	.byte OP_TREE, 88, 44
	.byte OP_TREE, 20, 48
	.byte OP_TREE, 52, 56
	.byte OP_TREE, 96, 26
	.byte OP_TREE, 36, 44
	.byte OP_BUSH, 48, 26
	.byte OP_BUSH, 80, 8
	.byte OP_BUSH, 24, 36
	.byte OP_BUSH, 70, 52
	.byte OP_ROCK, 58, 22
	.byte OP_ROCK, 90, 12
	.byte OP_END
scrDuck:
	.byte OP_POND, 104, 46, 16, 10  ; the goal pond
	.byte OP_TREE, 20, 16
	.byte OP_TREE, 40, 36
	.byte OP_TREE, 64, 12
	.byte OP_TREE, 84, 30
	.byte OP_TREE, 28, 52
	.byte OP_TREE, 56, 48
	.byte OP_TREE, 100, 10
	.byte OP_TREE, 12, 36
	.byte OP_BUSH, 48, 20
	.byte OP_BUSH, 76, 46
	.byte OP_BUSH, 34, 8
	.byte OP_BUSH, 92, 22
	.byte OP_ROCK, 70, 26
	.byte OP_ROCK, 24, 28
	.byte OP_END
scrRope:
	.byte OP_OAK, 112, 16
	.byte OP_TREE, 20, 12
	.byte OP_TREE, 40, 32
	.byte OP_TREE, 64, 8
	.byte OP_TREE, 80, 40
	.byte OP_TREE, 32, 52
	.byte OP_TREE, 96, 34
	.byte OP_TREE, 12, 40
	.byte OP_BUSH, 52, 16
	.byte OP_BUSH, 76, 24
	.byte OP_BUSH, 28, 24
	.byte OP_BUSH, 60, 44
	.byte OP_ROCK, 16, 24
	.byte OP_ROCK, 36, 12
	.byte OP_ROCK, 56, 30
	.byte OP_ROCK, 72, 50
	.byte OP_ROCK, 90, 14
	.byte OP_ROCK, 104, 44
	.byte OP_ROCK, 44, 44
	.byte OP_END
scrEscort:
	.byte OP_TREE, 24, 14
	.byte OP_TREE, 44, 34
	.byte OP_TREE, 68, 10
	.byte OP_TREE, 88, 38
	.byte OP_TREE, 32, 48
	.byte OP_TREE, 60, 52
	.byte OP_TREE, 104, 20
	.byte OP_TREE, 14, 32
	.byte OP_TREE, 76, 26
	.byte OP_BUSH, 38, 22
	.byte OP_BUSH, 82, 50
	.byte OP_BUSH, 56, 30
	.byte OP_ROCK, 48, 12
	.byte OP_ROCK, 94, 8
	.byte OP_GATE, 26
	.byte OP_END
scrChase:                        ; 256x32 cells
	.byte OP_TREE, 30, 6
	.byte OP_TREE, 50, 20
	.byte OP_TREE, 70, 8
	.byte OP_TREE, 90, 22
	.byte OP_TREE, 110, 4
	.byte OP_TREE, 130, 18
	.byte OP_TREE, 150, 8
	.byte OP_TREE, 170, 22
	.byte OP_TREE, 190, 6
	.byte OP_TREE, 210, 18
	.byte OP_TREE, 225, 8
	.byte OP_ROCK, 40, 14
	.byte OP_ROCK, 80, 10
	.byte OP_ROCK, 120, 24
	.byte OP_ROCK, 160, 14
	.byte OP_ROCK, 200, 24
	.byte OP_ROCK, 60, 26
	.byte OP_ROCK, 140, 6
	.byte OP_OAK, 244, 12
	.byte OP_END
scrEndless:
	.byte OP_POND, 100, 46, 12, 8
	.byte OP_TREE, 20, 14
	.byte OP_TREE, 44, 32
	.byte OP_TREE, 68, 10
	.byte OP_TREE, 88, 40
	.byte OP_TREE, 30, 50
	.byte OP_TREE, 108, 22
	.byte OP_BUSH, 52, 22
	.byte OP_BUSH, 78, 48
	.byte OP_BUSH, 24, 30
	.byte OP_ROCK, 60, 40
	.byte OP_ROCK, 96, 12
	.byte OP_END

.code
; ------------------------------------------------------------
; buildWorld: build level in `level` into RAM map + VRAM
; ------------------------------------------------------------
buildWorld:
	ldx level
	lda lvWide,x
	sta mapWide
	beq @narrow
	; chase world: 2048x256
	lda #<2048
	sta worldWL
	lda #>2048
	sta worldWH
	lda #<256
	sta worldHL
	lda #>256
	sta worldHH
	lda #%00110010               ; 4bpp, map 256x32
	sta VERA_L0_CONFIG
	bra @sized
@narrow:
	lda #<1024
	sta worldWL
	lda #>1024
	sta worldWH
	lda #<512
	sta worldHL
	lda #>512
	sta worldHH
	lda #%01100010               ; 4bpp, map 128x64
	sta VERA_L0_CONFIG
@sized:
	; camera clamps
	sec
	lda worldWL
	sbc #<320
	sta camMaxXL
	lda worldWH
	sbc #>320
	sta camMaxXH
	sec
	lda worldHL
	sbc #<240
	sta camMaxYL
	lda worldHH
	sbc #>240
	sta camMaxYH

	; reset feature records
	stz appleCnt
	stz bushCnt
	stz rockCnt
	stz treeCnt
	stz gateRow
	stz gateOpenF
	ldx #7
:	stz rockDone,x
	dex
	bpl :-
	ldx #15
:	stz treeShake,x
	dex
	bpl :-

	jsr clearWorld
	; run the feature script
	ldx level
	lda lvScrLo,x
	sta srcP
	lda lvScrHi,x
	sta srcP+1
@op:
	lda (srcP)
	beq @done
	cmp #OP_POND
	bne :+
	jsr featPond
	bra @op
:	cmp #OP_TREE
	bne :+
	jsr featTree
	bra @op
:	cmp #OP_OAK
	bne :+
	jsr featOak
	bra @op
:	cmp #OP_BUSH
	bne :+
	jsr featBush
	bra @op
:	cmp #OP_ROCK
	bne :+
	jsr featRock
	bra @op
:	cmp #OP_GATE
	bne @done
	jsr featGate
	bra @op
@done:
	rts

; advance script pointer by exactly Y bytes (opcode + args)
scrAdv:
	clc
	tya
	adc srcP
	sta srcP
	bcc :+
	inc srcP+1
:	rts

; fetch arg Y (1-based after opcode) into A
scrArg:
	lda (srcP),y
	rts

; ------------------------------------------------------------
; clearWorld: grass + random decoration everywhere
; ------------------------------------------------------------
clearWorld:
	; RAM map + VRAM in one pass: 8192 entries
	lda #<worldMap
	sta dstP
	lda #>worldMap
	sta dstP+1
	VSET VRAM_MAP, VINC_1
	ldx #32                      ; 32 * 256 = 8192 entries
	ldy #0
@cell:
	jsr rnd
	cmp #14
	bcc @tuft
	cmp #22
	bcc @flw
	cmp #26
	bcc @flg
	cmp #28
	bcc @peb
	lda #TI_GRASS
	bra @put
@tuft:
	lda #TI_TUFT
	bra @put
@flw:
	lda #TI_FLOWERWHITE
	bra @put
@flg:
	lda #TI_FLOWERGOLD
	bra @put
@peb:
	lda #TI_PEBBLE
@put:
	sta (dstP),y
	sta VERA_DATA0
	lda terrBank
	sta VERA_DATA0
	iny
	bne @cell
	inc dstP+1
	dex
	bne @cell
	rts

; ------------------------------------------------------------
; setCell: tile A at (cellX, cellY) -> RAM + VRAM
; ------------------------------------------------------------
setCell:
	pha
	; RAM: offset = wide ? y*256+x : y*128+x
	lda mapWide
	bne @wide
	lda cellY
	lsr                          ; y/2 -> page
	sta tmpHi
	lda #0
	ror                          ; (y&1)*128
	ora cellX
	sta tmpLo
	bra @have
@wide:
	lda cellY
	sta tmpHi
	lda cellX
	sta tmpLo
@have:
	clc
	lda tmpHi
	adc #>worldMap
	sta mapP+1
	lda tmpLo
	sta mapP
	pla
	sta (mapP)
	pha
	; VRAM: narrow entry addr = y*256 + x*2 ; wide = y*512 + x*2
	stz VERA_CTRL
	lda mapWide
	bne @vwide
	lda cellX
	asl
	sta VERA_ADDR_L
	lda cellY
	sta VERA_ADDR_M
	bra @vgo
@vwide:
	lda cellX
	asl                          ; C = x bit7
	sta VERA_ADDR_L
	lda cellY
	rol                          ; y*2 + xbit8
	sta VERA_ADDR_M
@vgo:
	lda #VINC_1
	sta VERA_ADDR_H
	pla
	sta VERA_DATA0
	lda terrBank
	sta VERA_DATA0
	rts

; getCell: A = tile at (cellX, cellY)
getCell:
	lda mapWide
	bne @wide
	lda cellY
	lsr
	sta tmpHi
	lda #0
	ror
	ora cellX
	sta tmpLo
	bra @have
@wide:
	lda cellY
	sta tmpHi
	lda cellX
	sta tmpLo
@have:
	clc
	lda tmpHi
	adc #>worldMap
	sta mapP+1
	lda tmpLo
	sta mapP
	lda (mapP)
	rts

; solidAtPx: X px in sampX, Y px in sampY — C set if solid
; (dedicated registers: never touches the dx/dy velocity pairs)
solidAtPx:
	lda sampX+1
	sta tmp
	lda sampX
	lsr tmp
	ror
	lsr tmp
	ror
	lsr tmp
	ror
	sta cellX
	lda sampY+1
	sta tmp
	lda sampY
	lsr tmp
	ror
	lsr tmp
	ror
	lsr tmp
	ror
	sta cellY
	phx                          ; X is the caller's actor slot — sacred
	jsr getCell
	tax
	lda tileSolid,x
	cmp #1                       ; C set when solid
	plx                          ; (plx leaves carry untouched)
	rts

; ------------------------------------------------------------
; feature painters — each reads args via (srcP),y then advances
; ------------------------------------------------------------
featPond:
	ldy #1
	lda (srcP),y
	sta tmp                      ; x
	iny
	lda (srcP),y
	sta tmp2                     ; y
	iny
	lda (srcP),y
	sta tmp3                     ; w
	iny
	lda (srcP),y
	pha                          ; h
	; record center (px): (x + w/2)*8, (y + h/2)*8
	lda tmp3
	lsr
	clc
	adc tmp
	sta pondXL                   ; cells for now
	stz pondXH
	asl pondXL
	rol pondXH
	asl pondXL
	rol pondXH
	asl pondXL
	rol pondXH
	pla
	pha
	lsr
	clc
	adc tmp2
	sta pondYL
	stz pondYH
	asl pondYL
	rol pondYH
	asl pondYL
	rol pondYH
	asl pondYL
	rol pondYH
	; paint rows (setCell clobbers tmp/tmpLo/tmpHi — use featW/featH)
	lda tmp3
	sta featW
	pla
	sta featH
	lda tmp2
	sta cellY
@row:
	lda tmp
	sta cellX
	ldx featW
@col:
	phx
	jsr rnd
	and #7
	cmp #1
	bne :+
	lda #TI_WATERSPARKLE
	bra :++
:	lda #TI_WATER
:	jsr setCell
	plx
	inc cellX
	dex
	bne @col
	inc cellY
	dec featH
	bne @row
	; a lily + reeds at the rim
	lda tmp
	inc a
	sta cellX
	lda tmp2
	inc a
	sta cellY
	lda #TI_LILY
	jsr setCell
	lda tmp
	clc
	adc tmp3
	dec a
	dec a
	sta cellX
	lda tmp2
	sta cellY
	lda #TI_REED
	jsr setCell
	ldy #5
	jmp scrAdv

featTree:
	ldy #1
	lda (srcP),y
	sta tmp
	iny
	lda (srcP),y
	sta tmp2
	; record trunk pos (px): (x+1.5)*8, (y+2)*8 for shaking
	ldx treeCnt
	cpx #16
	bcs @norec
	lda tmp
	inc a
	stz tmpHi
	asl
	rol tmpHi
	asl
	rol tmpHi
	asl
	rol tmpHi
	clc
	adc #4
	sta treeXL,x
	lda tmpHi
	adc #0
	sta treeXH,x
	lda tmp2
	clc
	adc #2
	stz tmpHi
	asl
	rol tmpHi
	asl
	rol tmpHi
	asl
	rol tmpHi
	sta treeYL,x
	lda tmpHi
	sta treeYH,x
	inc treeCnt
@norec:
	; canopy 3x2
	lda tmp2
	sta cellY
	ldx #2
@crow:
	lda tmp
	sta cellX
	phx
	ldx #3
@ccol:
	phx
	jsr rnd
	and #1
	beq :+
	lda #TI_CANOPYA
	bra :++
:	lda #TI_CANOPYB
:	ldy tier
	cpy #2
	bne @notW
	clc
	adc #(TI_CANOPYWINTERA-TI_CANOPYA)
@notW:
	jsr setCell
	plx
	inc cellX
	dex
	bne @ccol
	plx
	inc cellY
	dex
	bne @crow
	; trunk 2 cells below canopy center
	lda tmp
	inc a
	sta cellX
	lda #TI_TRUNKL
	jsr setCell
	inc cellX
	lda #TI_TRUNKR
	jsr setCell
	ldy #3
	jmp scrAdv

featOak:
	ldy #1
	lda (srcP),y
	sta tmp
	iny
	lda (srcP),y
	sta tmp2
	; record trunk center px: (x+2.5)*8, (y+4)*8
	lda tmp
	clc
	adc #2
	stz tmpHi
	asl
	rol tmpHi
	asl
	rol tmpHi
	asl
	rol tmpHi
	clc
	adc #4
	sta oakXL
	lda tmpHi
	adc #0
	sta oakXH
	lda tmp2
	clc
	adc #4
	asl
	asl
	asl
	sta oakYL
	; canopy 5x3
	lda tmp2
	sta cellY
	ldx #3
@crow:
	lda tmp
	sta cellX
	phx
	ldx #5
@ccol:
	phx
	jsr rnd
	and #1
	beq :+
	lda #TI_CANOPYA
	bra :++
:	lda #TI_CANOPYB
:	ldy tier
	cpy #2
	bne @notW
	clc
	adc #(TI_CANOPYWINTERA-TI_CANOPYA)
@notW:
	jsr setCell
	plx
	inc cellX
	dex
	bne @ccol
	plx
	inc cellY
	dex
	bne @crow
	; trunk 2x2
	lda tmp
	clc
	adc #2
	sta cellX
	lda tmp2
	clc
	adc #3
	sta cellY
	lda #TI_TRUNKL
	jsr setCell
	inc cellX
	lda #TI_TRUNKR
	jsr setCell
	lda tmp
	clc
	adc #2
	sta cellX
	inc cellY
	lda #TI_TRUNKL
	jsr setCell
	inc cellX
	lda #TI_TRUNKR
	jsr setCell
	ldy #3
	jmp scrAdv

featBush:
	ldy #1
	lda (srcP),y
	sta cellX
	iny
	lda (srcP),y
	sta cellY
	ldx bushCnt
	cpx #6
	bcs @norec
	lda cellX
	stz tmpHi
	asl
	rol tmpHi
	asl
	rol tmpHi
	asl
	rol tmpHi
	clc
	adc #8                       ; center of 2x1 bush pair
	sta bushXL,x
	lda tmpHi
	adc #0
	sta bushXH,x
	lda cellY
	stz tmpHi
	asl
	rol tmpHi
	asl
	rol tmpHi
	asl
	rol tmpHi
	clc
	adc #4
	sta bushYL,x
	lda tmpHi
	adc #0
	sta bushYH,x
	inc bushCnt
@norec:
	lda #TI_BUSH
	jsr setCell
	inc cellX
	lda #TI_BUSH
	jsr setCell
	ldy #3
	jmp scrAdv

featRock:
	ldy #1
	lda (srcP),y
	sta cellX
	iny
	lda (srcP),y
	sta cellY
	ldx rockCnt
	cpx #8
	bcs @norec
	lda cellX
	stz tmpHi
	asl
	rol tmpHi
	asl
	rol tmpHi
	asl
	rol tmpHi
	clc
	adc #8                       ; center of the 2x2 boulder
	sta rockXL,x
	lda tmpHi
	adc #0
	sta rockXH,x
	lda cellY
	stz tmpHi
	asl
	rol tmpHi
	asl
	rol tmpHi
	asl
	rol tmpHi
	clc
	adc #8                       ; center of the 2x2 boulder
	sta rockYL,x
	lda tmpHi
	adc #0
	sta rockYH,x
	inc rockCnt
@norec:
	lda #TI_ROCKTL
	jsr setCell
	inc cellX
	lda #TI_ROCKTR
	jsr setCell
	inc cellY
	lda #TI_ROCKBR
	jsr setCell
	dec cellX
	lda #TI_ROCKBL
	jsr setCell
	ldy #3
	jmp scrAdv

featGate:
	ldy #1
	lda (srcP),y
	sta gateRow
	; fence column at x = 126 (world right edge), gap at gateRow..+3
	lda #126
	sta cellX
	stz cellY
@fcol:
	lda cellY
	cmp gateRow
	bcc @fence
	sec
	sbc gateRow
	cmp #4
	bcc @gate
@fence:
	lda #TI_FENCE
	bra @putf
@gate:
	lda #TI_GATEBEAM
@putf:
	jsr setCell
	inc cellY
	lda cellY
	cmp #64
	bne @fcol
	ldy #2
	jmp scrAdv

; openGate: swap gate beams to grass (called when objective complete)
openGate:
	lda gateOpenF
	bne @done
	inc gateOpenF
	lda #126
	sta cellX
	lda gateRow
	sta cellY
	ldx #4
@g:
	phx
	lda #TI_GRASS
	jsr setCell
	plx
	inc cellY
	dex
	bne @g
@done:
	rts
