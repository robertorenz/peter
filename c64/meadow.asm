; ============================================================
;  PETER AND THE WOLF - Level 1: The Meadow
;  Commodore 64 port (dasm syntax)
;
;  A 1024x256 pixel scrolling meadow (128x32 tiles, ~3 screens
;  wide).  Gather the numbered apples IN ORDER, then escape
;  through the gate at the far right - while the wolf hunts you
;  across the whole world, on-screen or off.  Joystick port 2;
;  FIRE blows the whistle, stunning the wolf (long cooldown).
;
;  The view is double buffered: the visible window renders into
;  the off-screen buffer ($0400/$2c00) and flips via $d018 at
;  the frame boundary; color RAM is blasted right behind the
;  flip, racing (and beating) the beam down the screen.
;
;  Build: see build.ps1 (dasm -> meadow.prg -> meadow.d64)
; ============================================================

	processor 6502

; ---------------- zero page ----------------
syncFlag  equ $02          ; set by raster IRQ, consumed by main loop
frame     equ $03
state     equ $04          ; 0=play 1=caught 2=escaped
nextNum   equ $05          ; next apple number to gather (1..5)
gotCount  equ $06
gateOpen  equ $07
stun      equ $08          ; wolf frozen while >0
cooldown  equ $09          ; whistle recharge
joy       equ $0a          ; active-high joystick bits
peterXLo  equ $0b          ; world coords, pixel resolution
peterXHi  equ $0c
peterY    equ $0d          ; world Y fits a byte (0..235)
wolfXLo   equ $0e
wolfXHi   equ $0f
wolfY     equ $10
wolfFace  equ $11          ; 0=left 1=right
moving    equ $12
msgTimer  equ $13          ; delay before FIRE accepted on message screens
buzzTimer equ $14          ; rate-limits the wrong-apple buzz
sfxTimer  equ $15
sfxPtr    equ $16          ; ..$17
lastCol   equ $18          ; world cell, set by getCell
lastRow   equ $19
tmpLo     equ $1a
tmpHi     equ $1b
tmp       equ $1c
dynBuf    equ $1d          ; ..$1f: 3-byte RAM sfx (dur,freq,0)
winFlag   equ $20
newXLo    equ $22          ; candidate X while moving (getCell eats tmpLo)
newXHi    equ $23
musPtr    equ $24          ; ..$25 current music note pointer
musTimer  equ $26
musSong   equ $27          ; 0 = peter's theme, 1 = wolf's theme
musWave   equ $28          ; SID waveform of the current song's voice
camCol    equ $2a          ; coarse origin of the BACK buffer (0..88)
camRow    equ $2b          ; (0..7)
camXLo    equ $2c          ; camera origin, PIXELS (0..704)
camXHi    equ $2d
camY      equ $2e          ; camera Y, pixels (0..56)
visBuf    equ $2f          ; which screen is visible (0=$0400 1=$2c00)
scrOff    equ $30          ; active screen page offset from $04xx
flipReq   equ $31
camMoved  equ $32
seedLo    equ $34          ; 16-bit LFSR
seedHi    equ $35
peterDir  equ $38          ; 0=down 1=up 2=left 3=right
visCX     equ $39          ; coarse origin of the VISIBLE buffer
visCY     equ $3a
tmp2      equ $3b
mapP      equ $f5          ; ..$f6 world map pointer
dstP      equ $f7          ; ..$f8 render destination
colBufP   equ $36          ; ..$37 color buffer pointer (render + blast)
colPtr    equ $f9          ; ..$fa color RAM pointer
scrPtr    equ $fb          ; ..$fc screen RAM pointer
txtPtr    equ $fd          ; ..$fe text pointer

; ---------------- constants ----------------
SCREENA   equ $0400
SCREENB   equ $2c00        ; in VIC bank 0, clear of code/sprites/charset
COLRAM    equ $d800
CHARSET   equ $3800        ; VIC sees this via $d018
MAP       equ $4000        ; 128x32 world cells ($4000-$4fff)
COLORBUF  equ $5000        ; 960-byte color image of the view
COLTAB    equ $5400        ; char -> color, 256 entries (RAM: gate recolors)
SPRBASE   equ $80          ; $2000/64
APPLE_CH  equ 132
GATE_CH   equ 136
N_APPLES  equ 5
MAPW      equ 128
MAPH      equ 32
HUDSPR    equ $2400        ; 5 border sprites carry the status text
HUDPTR    equ $90          ; $2400/64
CAMXMAXLO equ <704         ; camera pixel limit: world 1024 - 320 view
CAMXMAXHI equ >704
CAMYMAX   equ 56           ; world 256 - 200 (25 rendered rows)

; ============================================================
	org $0801
	; 10 SYS 2061
	dc.b $0b,$08,$0a,$00,$9e,"2061",$00,$00,$00

start
	sei
	jsr copyCharset
	; blank the HUD sprite block (glyphs only fill rows 0-7)
	ldx #0
	lda #0
stHudClr
	sta HUDSPR,x
	sta HUDSPR+$100,x
	inx
	bne stHudClr
	jsr initVic
	jsr initSid
	lda #0
	sta visBuf
	sta scrOff
	sta flipReq
	jsr buildLevel
	; raster IRQ at line $fa
	lda #$7f
	sta $dc0d              ; kill CIA timer IRQs
	lda $dc0d
	lda #$01
	sta $d01a
	lda #$fa
	sta $d012
	lda $d011
	and #$7f
	sta $d011
	lda #<irq
	sta $0314
	lda #>irq
	sta $0315
	cli

mainloop
	lda syncFlag
	beq mainloop
	lda #0
	sta syncFlag
	; pending buffer flip: swap screens in the border, then win
	; the race against the beam re-colouring the new image
	lda flipReq
	beq mlNoFlip
	lda #0
	sta flipReq
	lda visBuf
	eor #1
	sta visBuf
	tax
	lda d018Tab,x
	sta $d018
	lda scrOffTab,x
	sta scrOff
	lda camCol             ; the back buffer's origin is live now
	sta visCX
	lda camRow
	sta visCY
	jsr colorBlast
mlNoFlip
	jsr fineScroll
	jsr tick
	jmp mainloop

; ---- fine scroll: hardware-shift the visible buffer by the
; sub-tile part of the camera position (still in border time) ----
fineScroll
	; fineX = clamp(camX - visCX*8, 0..7)
	lda visCX
	sta tmpLo
	lda #0
	sta tmpHi
	asl tmpLo
	rol tmpHi
	asl tmpLo
	rol tmpHi
	asl tmpLo
	rol tmpHi
	lda camXLo
	sec
	sbc tmpLo
	sta tmpLo
	lda camXHi
	sbc tmpHi
	bmi fsX0               ; camera left of the visible origin
	bne fsX7               ; 256+: render lag, clamp
	lda tmpLo
	cmp #8
	bcc fsXok
fsX7
	lda #7
	bne fsXok
fsX0
	lda #0
fsXok
	sta tmp
	lda #7
	sec
	sbc tmp
	ora #$c0               ; 38-column mode, multicolor off
	sta $d016
	; fineY = clamp(camY - visCY*8, 0..7)
	lda visCY
	asl
	asl
	asl
	sta tmp
	lda camY
	sec
	sbc tmp
	bcc fsY0
	cmp #8
	bcc fsYok
	lda #7
	bne fsYok
fsY0
	lda #0
fsYok
	sta tmp
	lda #7
	sec
	sbc tmp
	ora #$10               ; screen on, 24-row mode, text mode
	sta $d011
	rts

irq
	lda $d019
	sta $d019
	inc syncFlag
	jmp $ea81

; ============================================================
; init
; ============================================================
copyCharset
	; bank in the char ROM, copy the uppercase set to CHARSET,
	; then overlay our custom tiles at CHAR_FIRST
	lda $01
	pha
	and #%11111011
	sta $01
	lda #<$d000
	sta txtPtr
	lda #>$d000
	sta txtPtr+1
	lda #<CHARSET
	sta scrPtr
	lda #>CHARSET
	sta scrPtr+1
	ldx #8                 ; 8 pages = 2KB
ccPage
	ldy #0
ccByte
	lda (txtPtr),y
	sta (scrPtr),y
	iny
	bne ccByte
	inc txtPtr+1
	inc scrPtr+1
	dex
	bne ccPage
	pla
	sta $01
	; overlay custom chars
	ldx #0
ccPatch
	lda charData,x
	sta CHARSET+CHAR_FIRST*8,x
	inx
	cpx #CHAR_COUNT*8
	bne ccPatch
	rts

initVic
	lda #$1e               ; screen $0400, charset $3800
	sta $d018
	lda #0
	sta $d020              ; black border
	lda #13
	sta $d021              ; light green meadow
	lda #%11111111
	sta $d015              ; 0 peter, 1/2 wolf, 3-7 border HUD
	lda #%00000111
	sta $d01c              ; game sprites multicolor, HUD hires
	lda #0
	sta $d01d
	sta $d017
	sta $d01b              ; sprites in front of chars
	sta $d025              ; multicolor 1: black
	lda #1
	sta $d026              ; multicolor 2: white
	lda #2
	sta $d027              ; peter: red
	lda #11
	sta $d028              ; wolf: dark grey
	sta $d029
	; HUD sprites: fixed in the top border, white, 24px apart
	ldx #4
ivHud
	lda #1
	sta $d02a,x            ; colors of sprites 3-7
	txa
	asl
	tay                    ; $d006+2n / $d007+2n
	lda hudXTab,x
	sta $d006,y
	lda #57                ; floats over the top of the playfield
	sta $d007,y            ; (the VIC blanks sprites in the border)
	txa
	clc
	adc #HUDPTR
	sta SCREENA+$3fb,x     ; pointers in both buffers
	sta SCREENB+$3fb,x
	dex
	bpl ivHud
	rts

initSid
	ldx #$18
	lda #0
siClear
	sta $d400,x
	dex
	bpl siClear
	lda #$0f
	sta $d418              ; volume
	lda #$08
	sta $d405              ; attack 0 / decay 8
	lda #$a9
	sta $d406              ; sustain a / release 9
	lda #$08
	sta $d403              ; pulse width
	rts

; ============================================================
; per-frame tick
; ============================================================
tick
	inc frame
	jsr readJoy
	jsr sfxUpdate
	jsr musicTick
	lda state
	beq tickPlay
	; --- caught / escaped: wait for FIRE ---
	lda msgTimer
	beq tkMsgFire
	dec msgTimer
	rts
tkMsgFire
	lda joy
	and #%00010000
	beq tkDone
	jsr buildLevel
tkDone
	rts

tickPlay
	jsr movePeter
	jsr updateCamera
	jsr checkPickup
	jsr whistle
	jsr moveWolf
	jsr checkCaught
	lda winFlag
	beq tpNoWin
	lda #0
	sta winFlag
	lda #2
	sta state
	lda #40
	sta msgTimer
	lda #<msgWin
	ldy #>msgWin
	jsr drawMsg
	lda #<sfxWin
	ldx #>sfxWin
	jsr sfxStart
tpNoWin
	lda buzzTimer
	beq tpTimers
	dec buzzTimer
tpTimers
	lda cooldown
	beq tpSprites
	dec cooldown
tpSprites
	jmp updateSprites

readJoy
	lda $dc00
	eor #$ff
	and #$1f
	sta joy
	rts

; ============================================================
; Peter movement (2 px/frame, per-axis so he slides on walls)
; ============================================================
movePeter
	lda #0
	sta moving
	; ---- facing: horizontal wins on diagonals ----
	lda joy
	and #%00001000
	beq mpFaceL
	lda #3                 ; right
	bne mpFaceSet
mpFaceL
	lda joy
	and #%00000100
	beq mpFaceU
	lda #2                 ; left
	bne mpFaceSet
mpFaceU
	lda joy
	and #%00000001
	beq mpFaceD
	lda #1                 ; up: show peter's back
	bne mpFaceSet
mpFaceD
	lda joy
	and #%00000010
	beq mpFaceKeep
	lda #0                 ; down: face the player
mpFaceSet
	sta peterDir
mpFaceKeep
	; ---- horizontal ----
	lda peterXLo
	sta newXLo
	lda peterXHi
	sta newXHi
	lda joy
	and #%00001000
	beq mpTryLeft
	; right +2, clamp to 1000 ($03e8)
	lda newXLo
	clc
	adc #2
	sta newXLo
	lda newXHi
	adc #0
	sta newXHi
	cmp #3
	bcc mpXGo
	lda newXLo
	cmp #$e8
	bcc mpXGo
	lda #$e8
	sta newXLo
	jmp mpXGo
mpTryLeft
	lda joy
	and #%00000100
	beq mpVert
	lda newXLo
	sec
	sbc #2
	sta newXLo
	lda newXHi
	sbc #0
	sta newXHi
	bpl mpXGo              ; went negative: clamp to 0
	lda #0
	sta newXLo
	sta newXHi
mpXGo
	lda newXLo
	sta tmpLo
	lda newXHi
	sta tmpHi
	lda peterY
	jsr getCell
	jsr checkBlocked
	bcs mpVert
	lda newXLo
	sta peterXLo
	lda newXHi
	sta peterXHi
	inc moving
mpVert
	; ---- vertical ----
	lda peterXLo
	sta tmpLo
	lda peterXHi
	sta tmpHi
	lda joy
	and #%00000001
	beq mpTryDown
	lda peterY
	sec
	sbc #2
	bcs mpYGo
	lda #0
	jmp mpYGo
mpTryDown
	lda joy
	and #%00000010
	beq mpDone
	lda peterY
	clc
	adc #2
	cmp #235
	bcc mpYGo
	lda #235
mpYGo
	sta tmp
	jsr getCell
	jsr checkBlocked
	bcs mpDone
	lda tmp
	sta peterY
	inc moving
mpDone
	rts

; ============================================================
; getCell: tmpLo/Hi = world X of a sprite's left edge (the wolf
; adds 24 first so both probe their centre), A = world Y.
; Returns A = map cell char, sets lastCol/lastRow and mapP to
; the cell's row base (Y=lastCol indexes it).  Eats tmpLo/Hi.
; ============================================================
getCell
	clc
	adc #18                ; feet
	lsr
	lsr
	lsr
	sta lastRow
	jsr mapRowBase
	; centre column: (x+12)/8
	lda tmpLo
	clc
	adc #12
	sta tmpLo
	lda tmpHi
	adc #0
	lsr
	ror tmpLo
	lsr
	ror tmpLo
	lsr
	ror tmpLo
	lda tmpLo
	sta lastCol
	tay
	lda (mapP),y
	rts

; A = world row (0..31) -> mapP = MAP + row*128
mapRowBase
	lsr                    ; C = row&1
	ora #$40               ; hi = $40 | row/2
	sta mapP+1
	lda #0
	ror                    ; lo = (row&1)*128
	sta mapP
	rts

; A = screen code -> carry set if blocked.  Walking into the
; open gate sets winFlag instead.
checkBlocked
	cmp #GATE_CH
	beq cbGate
	cmp #130
	bcc cbClear            ; grass, digits, space
	cmp #APPLE_CH
	beq cbClear
	cmp #CHAR_FIRST+CHAR_COUNT
	bcc cbBlocked          ; rock, water, canopy, trunks
cbClear
	clc
	rts
cbGate
	lda gateOpen
	beq cbBlocked
	inc winFlag
cbBlocked
	sec
	rts

; like checkBlocked but the gate is ALWAYS solid to the wolf
checkBlockedWolf
	cmp #130
	bcc cwClear
	cmp #APPLE_CH
	beq cwClear
	cmp #CHAR_FIRST+CHAR_COUNT
	bcc cwBlocked
cwClear
	clc
	rts
cwBlocked
	sec
	rts

; ============================================================
; camera: pixel-resolution dead-zone follow.  Fine motion is
; free (hardware scroll registers); crossing an 8px boundary
; re-renders the back buffer and queues a flip.
; ============================================================
updateCamera
	; ---- horizontal: keep peter's screen x inside [130..170] ----
	lda peterXLo
	sec
	sbc camXLo
	sta tmpLo
	lda peterXHi
	sbc camXHi
	bne ucFar              ; >255: way right of the window
	lda tmpLo
	cmp #130
	bcs ucXHigh
	; camX -= 2, floor 0
	lda camXLo
	sec
	sbc #2
	sta camXLo
	lda camXHi
	sbc #0
	sta camXHi
	bpl ucVert
	lda #0
	sta camXLo
	sta camXHi
	beq ucVert
ucXHigh
	cmp #171
	bcc ucVert
ucFar
	; camX += 2, ceiling 704
	lda camXLo
	clc
	adc #2
	sta camXLo
	lda camXHi
	adc #0
	sta camXHi
	cmp #CAMXMAXHI
	bcc ucVert
	bne ucXCap
	lda camXLo
	cmp #CAMXMAXLO
	bcc ucVert
ucXCap
	lda #CAMXMAXLO
	sta camXLo
	lda #CAMXMAXHI
	sta camXHi
ucVert
	; ---- vertical: keep peter's screen y inside [72..120] ----
	lda peterY
	sec
	sbc camY
	bcc ucYLow             ; above the window
	cmp #72
	bcs ucYHigh
ucYLow
	lda camY
	sec
	sbc #2
	bcs ucYSet
	lda #0
ucYSet
	sta camY
	jmp ucCoarse
ucYHigh
	cmp #121
	bcc ucCoarse
	lda camY
	clc
	adc #2
	cmp #CAMYMAX
	bcc ucYSet2
	lda #CAMYMAX
ucYSet2
	sta camY
ucCoarse
	; did the camera cross a tile boundary? -> re-render
	lda camXLo
	sta tmpLo
	lda camXHi
	sta tmpHi
	lsr tmpHi
	ror tmpLo
	lsr tmpHi
	ror tmpLo
	lsr tmpHi
	ror tmpLo              ; tmpLo = camX>>3 (0..88)
	lda camY
	lsr
	lsr
	lsr
	sta tmpHi              ; camY>>3 (0..7)
	lda tmpLo
	cmp camCol
	bne ucRender
	lda tmpHi
	cmp camRow
	bne ucRender
	rts
ucRender
	lda tmpLo
	sta camCol
	lda tmpHi
	sta camRow
	jmp renderView

; ============================================================
; render the 40x24 view into the OFF-SCREEN buffer + color
; buffer, then request a flip.  Never touches the visible screen.
; ============================================================
renderView
	; dest = inactive screen, all 25 rows (the HUD lives in
	; border sprites now, so the whole screen scrolls)
	lda visBuf
	eor #1
	tax
	lda scrOffTab,x
	clc
	adc #>SCREENA
	sta dstP+1
	lda #0
	sta dstP
	lda #<COLORBUF
	sta colBufP
	lda #>COLORBUF
	sta colBufP+1
	lda camRow
	sta tmp                ; current world row
	ldx #25
rvRow
	txa
	pha
	lda tmp
	jsr mapRowBase
	lda mapP
	clc
	adc camCol
	sta mapP               ; row base + camCol (never crosses a page)
	ldy #39
rvCell
	lda (mapP),y
	sta (dstP),y
	tax
	lda COLTAB,x
	sta (colBufP),y
	dey
	bpl rvCell
	; advance dest pointers by 40
	lda dstP
	clc
	adc #40
	sta dstP
	bcc rvD1
	inc dstP+1
rvD1
	lda colBufP
	clc
	adc #40
	sta colBufP
	bcc rvD2
	inc colBufP+1
rvD2
	inc tmp
	pla
	tax
	dex
	bne rvRow
	inc flipReq
	rts

; copy the color buffer into color RAM top-down; starting in the
; border it stays ahead of the raster beam all the way
colorBlast
	lda #<COLORBUF
	sta colBufP
	lda #>COLORBUF
	sta colBufP+1
	lda #<COLRAM
	sta colPtr
	lda #>COLRAM
	sta colPtr+1
	ldx #25
cbRow
	ldy #39
cbCell
	lda (colBufP),y
	sta (colPtr),y
	dey
	bpl cbCell
	lda colBufP
	clc
	adc #40
	sta colBufP
	bcc cbA1
	inc colBufP+1
cbA1
	lda colPtr
	clc
	adc #40
	sta colPtr
	bcc cbA2
	inc colPtr+1
cbA2
	dex
	bne cbRow
	rts

; ============================================================
; apples: stand on the circle or its digit to gather it
; ============================================================
checkPickup
	lda peterXLo
	sta tmpLo
	lda peterXHi
	sta tmpHi
	lda peterY
	jsr getCell
	cmp #APPLE_CH
	bne cpDigit
	lda lastCol
	jmp cpFind
cpDigit
	cmp #49                ; '1'
	bcc cpDone
	cmp #49+N_APPLES
	bcs cpDone
	lda lastCol
	sec
	sbc #1
cpFind
	sta tmp                ; base column of the apple
	ldx #N_APPLES-1
cpLoop
	lda appleRowW,x
	cmp lastRow
	bne cpNext
	lda appleColW,x
	cmp tmp
	beq cpFound
cpNext
	dex
	bpl cpLoop
cpDone
	rts
cpFound
	lda appleNumW,x
	cmp nextNum
	beq cpCollect
	; wrong apple: low buzz (rate limited)
	lda buzzTimer
	bne cpDone
	lda #40
	sta buzzTimer
	lda #<sfxBuzz
	ldx #>sfxBuzz
	jmp sfxStart
cpCollect
	lda #$ff
	sta appleRowW,x        ; gone
	txa
	pha
	; erase from the world map, then re-render the view
	lda lastRow
	jsr mapRowBase
	lda #32
	ldy tmp
	sta (mapP),y
	iny
	sta (mapP),y
	pla
	tax
	inc gotCount
	inc nextNum
	; rising pickup note
	lda #6
	sta dynBuf
	lda gotCount
	asl
	asl
	asl
	clc
	adc #$38
	sta dynBuf+1
	lda #0
	sta dynBuf+2
	lda #<dynBuf
	ldx #0                 ; dynBuf lives in zero page
	jsr sfxStart
	lda gotCount
	cmp #N_APPLES
	bne cpRedraw
	inc gateOpen
	lda #7                 ; the gate lights up yellow
	sta COLTAB+GATE_CH
	lda #<hudGate          ; "GO EAST!"
	ldy #>hudGate
	jsr renderHud
cpRedraw
	jsr updateHudDigits
	jmp renderView

; ============================================================
; whistle: FIRE stuns the wolf, then needs a long recharge
; ============================================================
whistle
	lda joy
	and #%00010000
	beq whDone
	lda cooldown
	bne whDone
	lda #120
	sta stun
	lda #250
	sta cooldown
	lda #<sfxWhistle
	ldx #>sfxWhistle
	jmp sfxStart
whDone
	rts

; ============================================================
; wolf: hunts Peter across the world, respecting obstacles and
; sidestepping around whatever blocks the straight line
; ============================================================
moveWolf
	lda stun
	beq mwGo
	dec stun
	rts
mwGo
	lda frame
	and #1
	bne mwMove             ; wolf moves every other frame: half peter's pace
	rts
mwMove
	; ---- X axis ----
	lda wolfXLo
	cmp peterXLo
	bne mwXmove
	lda wolfXHi
	cmp peterXHi
	beq mwYAxis            ; same X
mwXmove
	lda wolfXLo
	sta newXLo
	lda wolfXHi
	sta newXHi
	lda wolfXLo
	cmp peterXLo
	lda wolfXHi
	sbc peterXHi
	bcc mwRight            ; wolf < peter
	lda newXLo
	sec
	sbc #1
	sta newXLo
	lda newXHi
	sbc #0
	sta newXHi
	lda #0
	sta wolfFace
	jmp mwXtry
mwRight
	inc newXLo
	bne mwFaceR
	inc newXHi
mwFaceR
	lda #1
	sta wolfFace
	; never past X=976: his probe must stay inside the map
	lda newXHi
	cmp #3
	bne mwXtry
	lda newXLo
	cmp #$d1
	bcs mwYAxis
mwXtry
	; probe the wolf's centre: getCell adds the +12 itself
	lda newXLo
	clc
	adc #24
	sta tmpLo
	lda newXHi
	adc #0
	sta tmpHi
	lda wolfY
	jsr getCell
	jsr checkBlockedWolf
	bcs mwXblocked
	lda newXLo
	sta wolfXLo
	lda newXHi
	sta wolfXHi
	jmp mwYAxis
mwXblocked
	; something in the way and already level with peter: sidestep
	lda wolfY
	cmp peterY
	bne mwYAxis
	cmp #128
	bcs mwSideUp
	inc wolfY
	rts
mwSideUp
	dec wolfY
	rts
mwYAxis
	lda wolfY
	cmp peterY
	beq mwDone
	bcc mwDown
	lda wolfY
	sec
	sbc #1
	jmp mwYtry
mwDown
	lda wolfY
	clc
	adc #1
mwYtry
	sta tmp
	lda wolfXLo
	clc
	adc #24
	sta tmpLo
	lda wolfXHi
	adc #0
	sta tmpHi
	lda tmp
	jsr getCell
	jsr checkBlockedWolf
	bcs mwYblocked
	lda tmp
	sta wolfY
	rts
mwYblocked
	; blocked and vertically aligned: sidestep in X
	lda wolfXLo
	cmp peterXLo
	bne mwDone
	lda wolfXHi
	cmp peterXHi
	bne mwDone
	lda wolfXHi
	bne mwSideL
	inc wolfXLo
	bne mwDone
	inc wolfXHi
	rts
mwSideL
	lda wolfXLo
	sec
	sbc #1
	sta wolfXLo
	lda wolfXHi
	sbc #0
	sta wolfXHi
mwDone
	rts

; |peter centre - wolf centre| -> tmpLo/Hi (16 bit)
absDx
	lda wolfXLo
	clc
	adc #24
	sta newXLo
	lda wolfXHi
	adc #0
	sta newXHi
	lda peterXLo
	clc
	adc #12
	sta tmpLo
	lda peterXHi
	adc #0
	sta tmpHi
	lda tmpLo
	sec
	sbc newXLo
	sta tmpLo
	lda tmpHi
	sbc newXHi
	sta tmpHi
	bpl adDone
	lda #0
	sec
	sbc tmpLo
	sta tmpLo
	lda #0
	sbc tmpHi
	sta tmpHi
adDone
	rts

; |peterY - wolfY| -> A
absDy
	lda peterY
	sec
	sbc wolfY
	bpl adyDone
	eor #$ff
	clc
	adc #1
adyDone
	rts

checkCaught
	jsr absDx
	lda tmpHi
	bne ccDone
	lda tmpLo
	cmp #26
	bcs ccDone
	jsr absDy
	cmp #18
	bcs ccDone
	; caught!
	lda #1
	sta state
	lda #40
	sta msgTimer
	lda #<msgCaught
	ldy #>msgCaught
	jsr drawMsg
	lda #<sfxCaught
	ldx #>sfxCaught
	jmp sfxStart
ccDone
	rts

; ============================================================
; sprites -> VIC registers (world - camera = screen)
; ============================================================
updateSprites
	; screen = world - camera + K, where K absorbs the fine-
	; scroll register convention: +31 in x, +54 in y
	; ---- peter (always on screen: the camera follows him) ----
	lda peterXLo
	sec
	sbc camXLo
	sta tmpLo
	lda peterXHi
	sbc camXHi
	sta tmpHi
	lda tmpLo
	clc
	adc #31
	sta $d000
	lda tmpHi
	adc #0
	and #1
	sta tmp                ; d010 accumulator, bit 0
	lda peterY
	sec
	sbc camY
	clc
	adc #54
	sta $d001
	; ---- wolf: visible only when his window overlaps the view ----
	lda wolfXLo
	sec
	sbc camXLo
	sta newXLo
	lda wolfXHi
	sbc camXHi
	sta newXHi
	bmi usWolfHide         ; left of the view
	beq usWolfY            ; 0..255: on
	cmp #1
	bne usWolfHide         ; 512+ px away
	lda newXLo
	cmp #34
	bcs usWolfHide         ; too far right
usWolfY
	lda wolfY
	sec
	sbc camY
	bcc usWolfHide         ; above the view
	cmp #168
	bcs usWolfHide         ; below it
	clc
	adc #54
	sta $d003
	sta $d005
	; front half x
	lda newXLo
	clc
	adc #31
	sta $d002
	lda newXHi
	adc #0
	and #1
	asl
	ora tmp
	sta tmp
	; rear half x = +24 more
	lda newXLo
	clc
	adc #55
	sta $d004
	lda newXHi
	adc #0
	and #1
	asl
	asl
	ora tmp
	sta tmp
	lda #%11111111
	bne usEnable
usWolfHide
	lda #%11111001
usEnable
	sta $d015
	lda tmp
	sta $d010
	; ---- peter: facing picks the frame pair, walk cycle animates ----
	ldx peterDir
	lda peterBase,x
	sta tmp2
	lda moving
	beq usPeterSet
	lda frame
	and #8
	beq usPeterSet
	lda tmp2
	clc
	adc peterStride,x
	sta tmp2
usPeterSet
	lda tmp2
	sta SCREENA+$3f8
	sta SCREENB+$3f8
	; ---- wolf pointers: base by facing, +4 for the gait frame ----
	lda frame
	and #8
	lsr                    ; 0 or 4
	sta tmpHi
	ldx wolfFace           ; 0=left 1=right
	lda wolfBaseA,x
	clc
	adc tmpHi
	sta SCREENA+$3f9
	sta SCREENB+$3f9
	lda wolfBaseB,x
	clc
	adc tmpHi
	sta SCREENA+$3fa
	sta SCREENB+$3fa
	; stunned wolf flashes white
	ldx #11
	lda stun
	beq usWolfCol
	lda frame
	and #4
	beq usWolfCol
	ldx #1
usWolfCol
	stx $d028
	stx $d029
	rts

; ============================================================
; sound effects: table of (dur,freqHi) pairs, dur=0 ends
; ============================================================
sfxStart
	sta sfxPtr
	stx sfxPtr+1
	ldy #0
	lda (sfxPtr),y
	sta sfxTimer
	iny
	lda (sfxPtr),y
	sta $d401
	lda #0
	sta $d400
	lda #$40               ; retrigger pulse
	sta $d404
	lda #$41
	sta $d404
	rts

sfxUpdate
	lda sfxTimer
	beq sfxDone
	dec sfxTimer
	bne sfxDone
	; advance to next pair
	lda sfxPtr
	clc
	adc #2
	sta sfxPtr
	bcc sfxRead
	inc sfxPtr+1
sfxRead
	ldy #0
	lda (sfxPtr),y
	beq sfxEnd
	sta sfxTimer
	iny
	lda (sfxPtr),y
	sta $d401
	lda #$40
	sta $d404
	lda #$41
	sta $d404
	rts
sfxEnd
	lda #$40               ; gate off
	sta $d404
sfxDone
	rts

; ============================================================
; music: Prokofiev's leitmotifs on voice 2.  Peter's theme
; loops in the meadow; when the wolf gets close, his theme
; takes over (with hysteresis so it doesn't flap).  Songs are
; (freqLo,freqHi,dur) triplets, 0,0,0 = loop point.
; ============================================================
; X = song index -> point at its start and set its instrument
musicSetup
	lda songLo,x
	sta musPtr
	lda songHi,x
	sta musPtr+1
	lda musWaveTab,x
	sta musWave
	lda musAdTab,x
	sta $d40c
	lda #$a9               ; sustain/release
	sta $d40d
	lda #$02
	sta $d40a              ; thin pulse for peter (harmless for saw)
	rts

musicStart
	lda #0
	sta musSong
	tax
	jsr musicSetup
	lda #1                 ; fetch the first note on the next tick
	sta musTimer
	rts

; which song does the wolf's distance call for? -> A (0/1)
musicDesired
	jsr absDx
	lda tmpHi
	bne mdFar
	jsr absDy
	sta tmp
	ldx musSong            ; thresholds widen while his theme plays
	lda tmpLo
	cmp musDxThresh,x
	bcs mdFar
	lda tmp
	cmp musDyThresh,x
	bcs mdFar
	lda #1
	rts
mdFar
	lda #0
	rts

musicTick
	lda state
	beq mtPlay
	lda musWave            ; caught/escaped: release the note so the
	and #$fe               ; voice-1 jingle stands alone
	sta $d40b
	rts
mtPlay
	dec musTimer
	bne mtRts
mtFetch
	jsr musicDesired
	cmp musSong
	beq mtSame
	sta musSong
	tax
	jsr musicSetup         ; switch songs at the note boundary
mtSame
	ldy #2
	lda (musPtr),y
	bne mtNote
	ldx musSong            ; hit the terminator: loop
	jsr musicSetup
	jmp mtFetch
mtNote
	sta musTimer
	ldy #0
	lda (musPtr),y
	sta $d407
	iny
	lda (musPtr),y
	sta $d408
	tax                    ; X=0 means this entry is a rest
	lda musPtr
	clc
	adc #3
	sta musPtr
	bcc mtGate
	inc musPtr+1
mtGate
	lda musWave
	and #$fe
	sta $d40b              ; gate off (stays off for a rest)
	cpx #0
	beq mtRts
	lda musWave
	sta $d40b              ; retrigger
mtRts
	rts

; ============================================================
; level build: paint the 128x32 world map, then show it
; ============================================================
buildLevel
	jsr initColTab
	jsr mapClear
	jsr scatterGrass
	jsr drawPonds
	jsr placeApples
	jsr drawOak
	jsr drawGate
	jsr scatterTrees
	jsr scatterRocks

	; reset game state
	lda #0
	sta state
	sta gateOpen
	sta gotCount
	sta stun
	sta cooldown
	sta buzzTimer
	sta winFlag
	sta moving
	sta wolfFace
	sta peterDir           ; facing the player
	lda #1
	sta nextNum
	; restore the hud line's digits and show it
	lda #49                ; '1'
	sta hudLine+5
	lda #48                ; '0'
	sta hudLine+12
	lda #<hudLine
	ldy #>hudLine
	jsr renderHud
	; positions: peter west of centre, wolf far east
	lda #48
	sta peterXLo
	lda #0
	sta peterXHi
	lda #140
	sta peterY
	lda #<700
	sta wolfXLo
	lda #>700
	sta wolfXHi
	lda #60
	sta wolfY
	lda #11
	sta $d028
	sta $d029
	; camera: pixel origin near peter, clamped to the world
	lda #0
	sta camXLo
	sta camXHi
	sta camCol
	sta visCX
	lda #44                ; peterY 140 - 96 -> mid-window
	sta camY
	lsr
	lsr
	lsr
	sta camRow             ; 5
	sta visCY
	jsr musicStart
	jsr renderView
	jmp updateSprites

; char -> color table, rebuilt each level (the gate entry mutates)
initColTab
	ldx #0
	lda #1                 ; default: white (text, digits)
ictFill
	sta COLTAB,x
	inx
	bne ictFill
	ldx #CHAR_COUNT-1
ictPatch
	lda charColors,x
	sta COLTAB+CHAR_FIRST,x
	dex
	bpl ictPatch
	rts

mapClear
	lda #<MAP
	sta mapP
	lda #>MAP
	sta mapP+1
	ldx #16                ; 16 pages = 4KB
	lda #32
	ldy #0
mcPage
	sta (mapP),y
	iny
	bne mcPage
	inc mapP+1
	dex
	bne mcPage
	rts

; 16-bit LFSR (Galois, poly $002d) - the map masks line up with
; its byte perfectly: col = rnd&127, row = rnd&31
rnd
	asl seedLo
	rol seedHi
	bcc rndOk
	lda seedLo
	eor #$2d
	sta seedLo
rndOk
	lda seedLo
	rts

scatterGrass
	lda #$a7
	sta seedLo
	lda #$3c
	sta seedHi
	ldx #0
sgLoop
	txa
	pha
	jsr rnd
	and #127
	sta tmp                ; column
	jsr rnd
	and #31
	jsr mapRowBase
	ldy tmp
	lda (mapP),y
	cmp #32
	bne sgSkip
	jsr rnd
	and #1
	clc
	adc #128               ; tuft or flower
	sta (mapP),y
sgSkip
	pla
	tax
	inx
	cpx #250
	bne sgLoop
	ldx #0                 ; two passes: 500 attempts over 4096 cells
sgLoop2
	txa
	pha
	jsr rnd
	and #127
	sta tmp
	jsr rnd
	and #31
	jsr mapRowBase
	ldy tmp
	lda (mapP),y
	cmp #32
	bne sgSkip2
	jsr rnd
	and #1
	clc
	adc #128
	sta (mapP),y
sgSkip2
	pla
	tax
	inx
	cpx #250
	bne sgLoop2
	rts

; two ponds, drawn row by row from the table
drawPonds
	ldx #0
dpLoop
	lda pondRow,x
	jsr mapRowBase
	lda pondLen,x
	sta tmp
	ldy pondCol,x
dpCell
	lda #131
	sta (mapP),y
	iny
	dec tmp
	bne dpCell
	inx
	cpx #N_PONDROWS
	bne dpLoop
	rts

placeApples
	ldx #N_APPLES-1
paCopy
	lda appleCol,x
	sta appleColW,x
	lda appleRow,x
	sta appleRowW,x
	lda appleNum,x
	sta appleNumW,x
	dex
	bpl paCopy
	ldx #0
paDraw
	txa
	pha
	lda appleRow,x
	jsr mapRowBase
	lda appleNum,x
	clc
	adc #48
	sta tmp                ; digit char
	pla
	tax
	ldy appleCol,x
	lda #APPLE_CH
	sta (mapP),y
	iny
	lda tmp
	sta (mapP),y
	inx
	cpx #N_APPLES
	bne paDraw
	rts

; the big oak: 4x2 canopy + 2-cell trunk at world (60,12)
drawOak
	lda #12
	jsr mapRowBase
	jsr doCanopy
	lda #13
	jsr mapRowBase
	jsr doCanopy
	lda #14
	jsr mapRowBase
	ldy #61
	lda #134
	sta (mapP),y
	iny
	lda #135
	sta (mapP),y
	rts
doCanopy
	ldy #60
	lda #133
doCan1
	sta (mapP),y
	iny
	cpy #64
	bne doCan1
	rts

drawGate
	lda #12
	sta tmp
dgLoop
	lda tmp
	jsr mapRowBase
	ldy #126
	lda #GATE_CH
	sta (mapP),y
	iny
	sta (mapP),y
	inc tmp
	lda tmp
	cmp #18
	bne dgLoop
	rts

; trees are 2x2 (canopy pair over trunk pair), placed by the
; LFSR wherever a 2x2 patch of plain meadow allows
scatterTrees
	ldx #0
stLoop
	txa
	pha
	jsr rnd
	and #127
	cmp #124
	bcs stSkip
	sta tmp                ; column
	jsr rnd
	and #31
	cmp #1
	bcc stSkip
	cmp #29
	bcs stSkip
	sta tmpHi              ; row
	jsr patchFree
	bcs stSkip
	; plant it
	lda tmpHi
	jsr mapRowBase
	ldy tmp
	lda #133
	sta (mapP),y
	iny
	sta (mapP),y
	lda tmpHi
	clc
	adc #1
	jsr mapRowBase
	ldy tmp
	lda #134
	sta (mapP),y
	iny
	lda #135
	sta (mapP),y
stSkip
	pla
	tax
	inx
	cpx #64
	bne stLoop
	rts

; is the 2x2 patch at (tmp,tmpHi) plain meadow? C clear = yes
patchFree
	lda tmpHi
	jsr mapRowBase
	ldy tmp
	jsr cellPlain
	bcs pfNo
	iny
	jsr cellPlain
	bcs pfNo
	lda tmpHi
	clc
	adc #1
	jsr mapRowBase
	ldy tmp
	jsr cellPlain
	bcs pfNo
	iny
	jsr cellPlain
pfNo
	rts

cellPlain
	lda (mapP),y
	cmp #32
	beq cpYes
	cmp #128
	beq cpYes
	cmp #129
	beq cpYes
	sec
	rts
cpYes
	clc
	rts

scatterRocks
	ldx #0
srLoop
	txa
	pha
	jsr rnd
	and #127
	sta tmp
	jsr rnd
	and #31
	sta tmpHi
	lda tmpHi
	jsr mapRowBase
	ldy tmp
	jsr cellPlain
	bcs srSkip
	lda #130
	sta (mapP),y
srSkip
	pla
	tax
	inx
	cpx #28
	bne srLoop
	rts

; ============================================================
; HUD: 15 characters of status text rendered into the five
; hires sprites parked in the top border (immune to scrolling).
; Each sprite carries 3 glyphs copied from the charset.
; ============================================================
; A/Y = 15-byte text lo/hi
renderHud
	sta txtPtr
	sty txtPtr+1
	ldy #14
rhChar
	tya
	pha
	lda (txtPtr),y
	cmp #64                ; ASCII letters -> screen codes
	bcc rhCode
	sec
	sbc #64
rhCode
	; glyph address = CHARSET + code*8
	sta scrPtr
	lda #0
	sta scrPtr+1
	asl scrPtr
	rol scrPtr+1
	asl scrPtr
	rol scrPtr+1
	asl scrPtr
	rol scrPtr+1
	lda scrPtr+1
	clc
	adc #>CHARSET
	sta scrPtr+1
	; destination inside the HUD sprite block
	lda hudDstLo,y
	sta colPtr
	lda hudDstHi,y
	sta colPtr+1
	ldx #7
rhRow
	txa
	tay
	lda (scrPtr),y
	pha
	lda row3Tab,x
	tay
	pla
	sta (colPtr),y
	dex
	bpl rhRow
	pla
	tay
	dey
	bpl rhChar
	rts

; refresh the NEXT/GOT digits inside the live HUD string
updateHudDigits
	lda gateOpen
	bne uhdDone
	lda nextNum
	clc
	adc #48
	sta hudLine+5
	lda gotCount
	clc
	adc #48
	sta hudLine+12
	lda #<hudLine
	ldy #>hudLine
	jmp renderHud
uhdDone
	rts

; A/Y = text lo/hi -> draw centred-ish on row 12 of whichever
; buffer will be visible next frame (a flip may be pending)
drawMsg
	sta txtPtr
	sty txtPtr+1
	ldx #12
	lda rowLo,x
	clc
	adc #5
	sta scrPtr
	sta colPtr
	lda visBuf
	eor flipReq
	tay
	lda scrOffTab,y
	clc
	adc rowHi,x
	sta scrPtr+1
	lda rowHi,x
	clc
	adc #$d4
	sta colPtr+1
	; fall through
drawText
	ldy #0
dtxLoop
	lda (txtPtr),y
	beq dtxDone
	cmp #64                ; letters need ASCII->screen code
	bcc dtxStore
	sec
	sbc #64
dtxStore
	sta (scrPtr),y
	lda #1                 ; white
	sta (colPtr),y
	iny
	bne dtxLoop
dtxDone
	rts


; ============================================================
; data
; ============================================================
; screen row base addresses ($0400 + 40*row); add scrOff for the
; active buffer, +$d4 to the high byte for color RAM
rowLo
	dc.b <(SCREENA+0),<(SCREENA+40),<(SCREENA+80),<(SCREENA+120),<(SCREENA+160)
	dc.b <(SCREENA+200),<(SCREENA+240),<(SCREENA+280),<(SCREENA+320),<(SCREENA+360)
	dc.b <(SCREENA+400),<(SCREENA+440),<(SCREENA+480),<(SCREENA+520),<(SCREENA+560)
	dc.b <(SCREENA+600),<(SCREENA+640),<(SCREENA+680),<(SCREENA+720),<(SCREENA+760)
	dc.b <(SCREENA+800),<(SCREENA+840),<(SCREENA+880),<(SCREENA+920),<(SCREENA+960)
rowHi
	dc.b >(SCREENA+0),>(SCREENA+40),>(SCREENA+80),>(SCREENA+120),>(SCREENA+160)
	dc.b >(SCREENA+200),>(SCREENA+240),>(SCREENA+280),>(SCREENA+320),>(SCREENA+360)
	dc.b >(SCREENA+400),>(SCREENA+440),>(SCREENA+480),>(SCREENA+520),>(SCREENA+560)
	dc.b >(SCREENA+600),>(SCREENA+640),>(SCREENA+680),>(SCREENA+720),>(SCREENA+760)
	dc.b >(SCREENA+800),>(SCREENA+840),>(SCREENA+880),>(SCREENA+920),>(SCREENA+960)

; $d018 per visible buffer (charset at $3800 -> index 7)
d018Tab	dc.b $1e,$be           ; screens $0400 and $2c00
; page offset of each buffer relative to SCREENA
scrOffTab	dc.b 0,>(SCREENB-SCREENA)

; per-char colors for the custom tiles (indexed from CHAR_FIRST)
; grass flower rock water apple canopy trunkL trunkR gate
charColors	dc.b 5,7,12,14,2,5,9,9,9

; ponds: (row,col,len) per drawn row
N_PONDROWS equ 8
pondRow	dc.b 24,25,26,27, 5,6,7,8
pondCol	dc.b 9,8,8,9,     71,70,70,71
pondLen	dc.b 6,8,8,6,     6,8,8,6

; apples: world cells spread across the meadow, shuffled numbers
appleCol	dc.b 12,30,55,90,110
appleRow	dc.b 4,26,15,7,27
appleNum	dc.b 3,1,5,2,4
; working copies (apples get eaten)
appleColW	dc.b 0,0,0,0,0
appleRowW	dc.b 0,0,0,0,0
appleNumW	dc.b 0,0,0,0,0

msgCaught	dc.b "THE WOLF GOT YOU!  PRESS FIRE",0
msgWin	dc.b "YOU ESCAPED THE MEADOW! PRESS FIRE",0

; HUD text: exactly 15 chars = 5 sprites x 3 glyphs
hudLine	dc.b "NEXT:1  GOT:0/5"
hudGate	dc.b "GO EAST!    5/5"
; destination of each glyph column inside the HUD sprite block
hudDstLo
	dc.b <(HUDSPR+0),<(HUDSPR+1),<(HUDSPR+2)
	dc.b <(HUDSPR+64),<(HUDSPR+65),<(HUDSPR+66)
	dc.b <(HUDSPR+128),<(HUDSPR+129),<(HUDSPR+130)
	dc.b <(HUDSPR+192),<(HUDSPR+193),<(HUDSPR+194)
	dc.b <(HUDSPR+256),<(HUDSPR+257),<(HUDSPR+258)
hudDstHi
	dc.b >(HUDSPR+0),>(HUDSPR+1),>(HUDSPR+2)
	dc.b >(HUDSPR+64),>(HUDSPR+65),>(HUDSPR+66)
	dc.b >(HUDSPR+128),>(HUDSPR+129),>(HUDSPR+130)
	dc.b >(HUDSPR+192),>(HUDSPR+193),>(HUDSPR+194)
	dc.b >(HUDSPR+256),>(HUDSPR+257),>(HUDSPR+258)
row3Tab	dc.b 0,3,6,9,12,15,18,21
hudXTab	dc.b 124,148,172,196,220   ; centred over the view

; sfx tables: (frames,freqHi) pairs, 0 = end
sfxWhistle	dc.b 5,$68,6,$8c,0
sfxBuzz	dc.b 10,$06,0
sfxCaught	dc.b 8,$30,8,$24,8,$1a,12,$10,0
sfxWin	dc.b 7,$40,7,$50,7,$60,14,$80,0

; peter sprite pointer base + walk-frame stride, by peterDir
; layout: $80 D1,$81 D2,$82 U1,$83 U2,$84 L1,$85 R1,$86 L2,$87 R2
peterBase	dc.b SPRBASE+0,SPRBASE+2,SPRBASE+4,SPRBASE+5
peterStride	dc.b 1,1,2,2

; wolf sprite pointer bases, indexed by wolfFace (0=left 1=right)
; layout: $88 L1a,$89 L1b,$8a R1a,$8b R1b, +4 for gait frame 2
wolfBaseA	dc.b SPRBASE+8,SPRBASE+10  ; screen-left half
wolfBaseB	dc.b SPRBASE+9,SPRBASE+11  ; screen-right half

; music: song table + per-song instrument, indexed by musSong
songLo	dc.b <songPeterData,<songWolfData
songHi	dc.b >songPeterData,>songWolfData
musWaveTab	dc.b $41,$21               ; peter pulse, wolf sawtooth
musAdTab	dc.b $18,$28               ; wolf gets a slower attack
; switch to the wolf's theme inside the small box, back to
; peter's only outside the big one
musDxThresh	dc.b 88,120
musDyThresh	dc.b 80,112

	include "build/music.inc"

; custom character bitmaps (copied over the ROM set at init)
	include "build/chars.inc"

; ============================================================
	org $2000              ; sprite data, pointer $80+
	include "build/sprites.inc"
