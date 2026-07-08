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
dirX      equ $3c          ; camera heading per axis: 1 / $ff / stale
dirY      equ $3d
renderSt  equ $3e          ; 0 idle, 1 half done, 2 ready (awaiting flip)
rvFirst   equ $3f          ; renderPart params: first row, row count
rvCount   equ $40
level     equ $21          ; 0..5 = the six chapters
frXLo     equ $33          ; friend (bird/duck/grandpa) world pos
frXHi     equ $41
frY       equ $42
frState   equ $43          ; 0=waiting 1=following peter
frFace    equ $44          ; 0=left 1=right
frType    equ $45          ; 0=none 1=bird 2=duck 3=grandpa
carryRope equ $46          ; ch4: rope found, carrying it
snareArm  equ $47          ; snare armed at the oak
rockN     equ $48          ; recorded rocks this level
ropeRock  equ $49          ; which rock hides the rope
preyXLo   equ $4a          ; who the foe hunts this frame
preyXHi   equ $4b
preyY     equ $4c
d015m     equ $4d          ; sprite enable mask under construction
hudMsgT   equ $4e          ; frames until the HUD line is restored
prevJoy   equ $4f
fireEdge  equ $50          ; FIRE newly pressed this frame
autoOn    equ $51          ; autopilot active (test builds / attract)
autGXLo   equ $52          ; autopilot goal
autGXHi   equ $53
autGY     equ $54
autSnapX  equ $55          ; unstick: position snapshot
autSnapY  equ $56
autStuck  equ $57          ; frames since the snapshot moved
foeA      equ $58          ; ..$59 foe sprite bases (front half), by face
foeB      equ $5a          ; ..$5b rear half
foeCol    equ $5c          ; foe sprite color
frBase    equ $5d          ; friend sprite pointer base (left-facing)
musDanger equ $5e          ; 1 = the foe's theme is playing
autWander equ $5f          ; autopilot detour frames left
autDir    equ $60          ; detour joystick bits
autFlip   equ $61          ; alternate detour side per attempt
wolfSlip  equ $62          ; foe horizontal-dodge side (sticky)
wolfDodge equ $63          ; foe committed-dodge frames left
wolfDDir  equ $64          ; dodge direction (0=up/left 1=down/right)
wolfDAxis equ $65          ; dodge axis (0=vertical 1=horizontal)
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
CAMCOLMAX equ 88           ; coarse camera cell limits
CAMROWMAX equ 7

; ============================================================
	org $0801
	; 10 SYS 2061
	dc.b $0b,$08,$0a,$00,$9e,"2061",$00,$00,$00

	IFNCONST START_LEVEL
START_LEVEL equ 0
	ENDIF

start
	sei
	lda #START_LEVEL
	sta level
	lda #0
	sta autoOn
	IFCONST AUTO
	lda #1
	sta autoOn             ; test builds: the game plays itself
	ENDIF
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
	; scroll + sprite registers must land in the border BEFORE
	; the long color blast, or the top of the frame tears
	jsr fineScroll
	jsr updateSprites
	jsr colorBlast
	jmp mlTick
mlNoFlip
	jsr fineScroll
	jsr updateSprites
mlTick
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
	sta $d015              ; 0 peter, 1/2 foe, 3 friend, 4-7 border HUD
	lda #%00001111
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
	; (sprites 4-7; sprite 3 belongs to the friend)
	ldx #3
ivHud
	lda #1
	sta $d02b,x            ; colors of sprites 4-7
	txa
	asl
	tay                    ; $d008+2n / $d009+2n
	lda hudXTab,x
	sta $d008,y
	lda #57                ; floats over the top of the playfield
	sta $d009,y            ; (the VIC blanks sprites in the border)
	txa
	clc
	adc #HUDPTR
	sta SCREENA+$3fc,x     ; pointers in both buffers
	sta SCREENB+$3fc,x
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
	lda state              ; escaped: on to the next chapter
	cmp #2
	bne tkRetry
	inc level
	lda level
	cmp #6
	bcc tkRetry
	lda #0
	sta level
tkRetry
	jsr buildLevel
tkDone
	rts

tickPlay
	jsr movePeter
	jsr updateCamera
	jsr scrollPlan
	jsr levelTick          ; pickups, friend, FIRE action, win checks
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
	ldx level
	lda msgWinLo,x
	ldy msgWinHi,x
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
	beq tpDone
	dec cooldown
tpDone
	rts                    ; sprites are refreshed at frame start

readJoy
	lda $dc00
	eor #$ff
	and #$1f
	sta joy
	lda autoOn
	beq rjEdge
	jsr autoPilot          ; demo/test: synthesize the stick
rjEdge
	lda prevJoy
	eor #$ff
	and joy
	and #%00010000
	sta fireEdge           ; FIRE newly pressed this frame
	lda joy
	sta prevJoy
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
	ldx autoOn
	bne cbClear            ; the demo ghost walks where it pleases
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
	lda #$ff
	sta dirX
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
	lda #1
	sta dirX
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
	lda #$ff
	sta dirY
	lda camY
	sec
	sbc #2
	bcs ucYSet
	lda #0
ucYSet
	sta camY
	rts
ucYHigh
	cmp #121
	bcc ucDone
	lda #1
	sta dirY
	lda camY
	clc
	adc #2
	cmp #CAMYMAX
	bcc ucYSet2
	lda #CAMYMAX
ucYSet2
	sta camY
ucDone
	rts

; ============================================================
; scroll planner: runs every play tick.  Predicts which tile the
; camera is drifting into and renders that view into the back
; buffer in two half-frame slices, so the flip is ready the
; moment the boundary is crossed - no dropped frames, no pops.
; ============================================================
scrollPlan
	; actual coarse camera cell -> tmpLo/tmpHi
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
	; ---- desired X (newXLo) ----
	lda tmpLo
	cmp visCX
	bne spDesXset          ; already crossed / teleported
	lda camXLo
	and #7
	cmp #4
	bcc spXlow
	lda dirX               ; drifting right, past mid-tile
	cmp #1
	bne spDesXvis
	lda visCX
	cmp #CAMCOLMAX
	bcs spDesXvis
	lda visCX
	clc
	adc #1
	jmp spDesXset
spXlow
	lda dirX               ; drifting left, before mid-tile
	cmp #$ff
	bne spDesXvis
	lda visCX
	beq spDesXvis
	sec
	sbc #1
	jmp spDesXset
spDesXvis
	lda visCX
spDesXset
	sta newXLo
	; ---- desired Y (newXHi) ----
	lda tmpHi
	cmp visCY
	bne spDesYset
	lda camY
	and #7
	cmp #4
	bcc spYlow
	lda dirY
	cmp #1
	bne spDesYvis
	lda visCY
	cmp #CAMROWMAX
	bcs spDesYvis
	lda visCY
	clc
	adc #1
	jmp spDesYset
spYlow
	lda dirY
	cmp #$ff
	bne spDesYvis
	lda visCY
	beq spDesYvis
	sec
	sbc #1
	jmp spDesYset
spDesYvis
	lda visCY
spDesYset
	sta newXHi
	; ---- anything to prepare? ----
	lda newXLo
	cmp visCX
	bne spWork
	lda newXHi
	cmp visCY
	bne spWork
	lda #0                 ; view is current: cancel pending work
	sta renderSt
	sta flipReq
	rts
spWork
	lda renderSt
	beq spStart
	lda newXLo             ; retarget if the prediction moved
	cmp camCol
	bne spStart
	lda newXHi
	cmp camRow
	bne spStart
	lda renderSt
	cmp #1
	bne spGate
	lda #13                ; second half of the back buffer
	sta rvFirst
	lda #12
	sta rvCount
	jsr renderPart
	lda #2
	sta renderSt
spGate
	lda renderSt
	cmp #2
	bne spDone
	lda tmpLo              ; flip once the camera actually enters
	cmp camCol             ; the prepared tile
	bne spDone
	lda tmpHi
	cmp camRow
	bne spDone
	inc flipReq
	lda #0
	sta renderSt
spDone
	rts
spStart
	lda newXLo
	sta camCol
	lda newXHi
	sta camRow
	lda #0
	sta rvFirst
	lda #13                ; first half this tick
	sta rvCount
	jsr renderPart
	lda #1
	sta renderSt
	rts

; ============================================================
; render the 40x24 view into the OFF-SCREEN buffer + color
; buffer, then request a flip.  Never touches the visible screen.
; ============================================================
; render rvCount rows starting at view row rvFirst into the
; OFF-SCREEN buffer + color buffer, from the map at camCol/camRow.
; Split into halves by the scroll planner so a slice always fits
; inside one frame's spare CPU - no dropped ticks.
renderPart
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
	; advance both destinations by rvFirst*40
	ldx rvFirst
	beq rpSkip
rpAdv
	lda dstP
	clc
	adc #40
	sta dstP
	bcc rpA1
	inc dstP+1
rpA1
	lda colBufP
	clc
	adc #40
	sta colBufP
	bcc rpA2
	inc colBufP+1
rpA2
	dex
	bne rpAdv
rpSkip
	lda camRow
	clc
	adc rvFirst
	sta tmp                ; current world row
	ldx rvCount
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
	rts

; full synchronous render + flip request (level build/reset)
renderView
	lda #0
	sta rvFirst
	lda #25
	sta rvCount
	jsr renderPart
	lda #0
	sta renderSt
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
	jsr paintGateVisible
	lda #<hudGate          ; "GO EAST!"
	ldy #>hudGate
	jsr renderHud
cpRedraw
	jsr updateHudDigits
	; erase the apple straight off the visible buffer, and let
	; any in-flight back-buffer render restart from the new map
	lda renderSt
	beq cpErase
	lda #0
	sta renderSt
cpErase
	lda lastRow
	sec
	sbc visCY
	cmp #25
	bcs cpEraseDone        ; not on screen
	tax
	lda tmp                ; apple's base column
	sec
	sbc visCX
	cmp #40
	bcs cpEraseDone
	pha
	lda rowLo,x
	sta scrPtr
	ldy visBuf
	lda scrOffTab,y
	clc
	adc rowHi,x
	sta scrPtr+1
	pla
	tay
	lda #32
	sta (scrPtr),y
	iny
	cpy #40
	bcs cpEraseDone
	sta (scrPtr),y
cpEraseDone
	rts

; when the gate opens, recolor any of its cells already on screen
paintGateVisible
	lda #126
	sec
	sbc visCX
	cmp #40
	bcs pgvDone            ; gate not in view
	sta tmp2               ; screen column of the gate's left half
	ldx #12                ; world rows 12..17
pgvRow
	txa
	sec
	sbc visCY
	cmp #25
	bcs pgvNext
	tay
	lda rowLo,y
	sta colPtr
	lda rowHi,y
	clc
	adc #$d4
	sta colPtr+1
	ldy tmp2
	lda #7
	sta (colPtr),y
	iny
	cpy #40
	bcs pgvNext
	sta (colPtr),y
pgvNext
	inx
	cpx #18
	bne pgvRow
pgvDone
	rts

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
	lda level
	cmp #5
	beq mwMove             ; the chase: he runs every frame
	lda frame
	and #1
	bne mwMove             ; else every other frame: half peter's pace
	rts
mwMove
	; ---- committed dodge: slide along the blocker, and bail the
	; moment the blocked axis frees up ----
	lda wolfDodge
	beq mwSeek
	dec wolfDodge
	lda wolfDAxis
	bne mwDodgeH
	; vertical slide
	lda wolfDDir
	beq mwDodU
	lda wolfY
	cmp #235
	bcs mwDodTX
	inc wolfY
	jmp mwDodTX
mwDodU
	lda wolfY
	beq mwDodTX
	dec wolfY
mwDodTX
	jsr mwTryX
	bcs mwDodOut           ; still blocked: keep sliding
	lda #0
	sta wolfDodge
mwDodOut
	rts
mwDodgeH
	; horizontal slide
	lda wolfDDir
	beq mwDodL
	inc wolfXLo
	bne mwDodTY
	inc wolfXHi
	jmp mwDodTY
mwDodL
	lda wolfXLo
	sec
	sbc #1
	sta wolfXLo
	lda wolfXHi
	sbc #0
	sta wolfXHi
	bpl mwDodTY
	lda #0
	sta wolfXLo
	sta wolfXHi
mwDodTY
	jsr mwTryY
	bcs mwDodOut2
	lda #0
	sta wolfDodge
mwDodOut2
	rts

mwSeek
	jsr mwTryX
	bcc mwSeekY            ; moved, or already in line
	; X blocked: commit to a vertical slide
	lda #40
	sta wolfDodge
	lda #0
	sta wolfDAxis
	lda wolfY
	cmp preyY
	beq mwSkEdge
	bcc mwSkDn             ; prey below: slide down
	lda #0
	sta wolfDDir
	jmp mwSeekY
mwSkDn
	lda #1
	sta wolfDDir
	jmp mwSeekY
mwSkEdge
	lda wolfY
	cmp #128
	bcs mwSkUp
	lda #1
	sta wolfDDir
	jmp mwSeekY
mwSkUp
	lda #0
	sta wolfDDir
mwSeekY
	jsr mwTryY
	bcc mwSeekDone
	; Y blocked while X is settled: horizontal slide, alternating
	; sides between attempts so he tries both ways round
	lda wolfDodge
	bne mwSeekDone         ; a vertical slide is already running
	lda #40
	sta wolfDodge
	lda #1
	sta wolfDAxis
	lda wolfSlip
	sta wolfDDir
	eor #1
	sta wolfSlip
mwSeekDone
	rts

; step X one pixel toward the prey.  C=0 moved (or already level /
; at the world edge), C=1 the way is blocked.
mwTryX
	lda wolfXLo
	cmp preyXLo
	bne mwtxGo
	lda wolfXHi
	cmp preyXHi
	bne mwtxGo
	clc                    ; already level: nothing to do
	rts
mwtxGo
	lda wolfXLo
	sta newXLo
	lda wolfXHi
	sta newXHi
	lda wolfXLo
	cmp preyXLo
	lda wolfXHi
	sbc preyXHi
	bcc mwtxR              ; wolf < prey
	lda newXLo
	sec
	sbc #1
	sta newXLo
	lda newXHi
	sbc #0
	sta newXHi
	lda #0
	sta wolfFace
	jmp mwtxTry
mwtxR
	inc newXLo
	bne mwtxFace
	inc newXHi
mwtxFace
	lda #1
	sta wolfFace
	; never past X=976: his probe must stay inside the map
	lda newXHi
	cmp #3
	bne mwtxTry
	lda newXLo
	cmp #$d1
	bcc mwtxTry
	clc                    ; pinned at the edge: treat as settled
	rts
mwtxTry
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
	bcs mwtxNo
	lda newXLo
	sta wolfXLo
	lda newXHi
	sta wolfXHi
	clc
	rts
mwtxNo
	sec
	rts

; step Y one pixel toward the prey.  C=0 moved or level, C=1 blocked.
mwTryY
	lda wolfY
	cmp preyY
	bne mwtyGo
	clc
	rts
mwtyGo
	bcc mwtyDn
	lda wolfY
	sec
	sbc #1
	jmp mwtyTry
mwtyDn
	lda wolfY
	clc
	adc #1
mwtyTry
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
	bcs mwtyNo
	lda tmp
	sta wolfY
	clc
	rts
mwtyNo
	sec
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
	ldx level
	lda msgCaughtLo,x
	ldy msgCaughtHi,x
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
	lda #%11110001         ; peter + HUD 4-7 always; foe/friend opt in
	sta d015m
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
	; ---- foe: visible only when his window overlaps the view ----
	; ch5 is night: the wolf is unseen beyond the fireflies' glow
	lda level
	cmp #4
	bne usFoeCalc
	jsr absDx
	lda tmpHi
	bne usWolfHide
	lda tmpLo
	cmp #96
	bcs usWolfHide
	jsr absDy
	cmp #88
	bcs usWolfHide
usFoeCalc
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
	cmp #58
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
	lda d015m
	ora #%00000110
	sta d015m
usWolfHide
	jsr drawFriend         ; sprite 3 (sets its d015m/d010 bits)
	lda d015m
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
	; ---- foe pointers: base by facing, +4 for the gait frame ----
	lda frame
	and #8
	lsr                    ; 0 or 4
	sta tmpHi
	ldx wolfFace           ; 0=left 1=right
	lda foeA,x
	clc
	adc tmpHi
	sta SCREENA+$3f9
	sta SCREENB+$3f9
	lda foeB,x
	clc
	adc tmpHi
	sta SCREENA+$3fa
	sta SCREENB+$3fa
	; stunned foe flashes white
	ldx foeCol
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
	sta musDanger
	ldx level
	lda lvSong,x
	sta musSong
	tax
	jsr musicSetup
	lda #1                 ; fetch the first note on the next tick
	sta musTimer
	rts

; which song does the foe's distance call for? -> A (song index)
musicDesired
	jsr absDx
	lda tmpHi
	bne mdFar
	jsr absDy
	sta tmp
	ldx musDanger          ; thresholds widen while his theme plays
	lda tmpLo
	cmp musDxThresh,x
	bcs mdFar
	lda tmp
	cmp musDyThresh,x
	bcs mdFar
	lda #1
	sta musDanger
	ldx level
	lda lvDanger,x
	rts
mdFar
	lda #0
	sta musDanger
	ldx level
	lda lvSong,x
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
	ldx level
	lda lvBg,x
	sta $d021              ; the chapter's daylight
	jsr mapClear
	jsr scatterGrass
	jsr drawPonds
	lda level
	bne blNoApples         ; numbered apples are chapter 1's game
	jsr placeApples
blNoApples
	jsr drawOak
	jsr drawGate
	jsr scatterTrees
	lda #0
	sta rockN
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
	sta dirX
	sta dirY
	sta renderSt
	sta frState
	sta frFace
	sta carryRope
	sta snareArm
	sta hudMsgT
	sta autStuck
	sta autWander
	sta wolfSlip
	sta wolfDodge
	lda #1
	sta nextNum
	; ch6: the snare hangs ready at the old oak
	lda level
	cmp #5
	bne blNoSnare
	lda #1
	sta snareArm
blNoSnare
	; ch4: the rope hides under one of the rocks
	lda level
	cmp #3
	bne blNoRope
	jsr rnd
	and #7
blRopeMod
	cmp rockN
	bcc blRopeOk
	sec
	sbc rockN
	jmp blRopeMod
blRopeOk
	sta ropeRock
blNoRope
	; the chapter's HUD line (ch1 restores its live digits first)
	lda level
	bne blHud
	lda #49                ; '1'
	sta hudLine+2
	lda #48                ; '0'
	sta hudLine+9
blHud
	ldx level
	lda lvHudLo,x
	ldy lvHudHi,x
	jsr renderHud
	; spawns from the chapter tables
	ldx level
	lda lvPeterXLo,x
	sta peterXLo
	lda lvPeterXHi,x
	sta peterXHi
	lda lvPeterY,x
	sta peterY
	lda lvFoeXLo,x
	sta wolfXLo
	lda lvFoeXHi,x
	sta wolfXHi
	lda lvFoeY,x
	sta wolfY
	; foe skin: the grey wolf, or chapter 2's ginger cat
	lda lvFoeCol,x
	sta foeCol
	sta $d028
	sta $d029
	lda lvFoeCat,x
	beq blWolfSkin
	lda #$95               ; cat frames (sprites2 block)
	sta foeA
	lda #$96
	sta foeB
	lda #$97
	sta foeA+1
	lda #$98
	sta foeB+1
	bne blFriend
blWolfSkin
	lda #SPRBASE+8
	sta foeA
	lda #SPRBASE+9
	sta foeB
	lda #SPRBASE+10
	sta foeA+1
	lda #SPRBASE+11
	sta foeB+1
blFriend
	; the friend, if this chapter has one
	ldx level
	lda lvFriend,x
	sta frType
	beq blNoFriend
	tay
	lda frBaseTab-1,y
	sta frBase
	lda lvFriendCol,x
	sta $d02a
	lda lvFrXLo,x
	sta frXLo
	lda lvFrXHi,x
	sta frXHi
	lda lvFrY,x
	sta frY
blNoFriend
	; prey defaults to peter until levelTick refines it
	lda peterXLo
	sta preyXLo
	lda peterXHi
	sta preyXHi
	lda peterY
	sta preyY
	; camera: centre peter, clamped to the world
	lda peterXLo
	sec
	sbc #160
	sta camXLo
	lda peterXHi
	sbc #0
	sta camXHi
	bpl blCamCeil
	lda #0
	sta camXLo
	sta camXHi
blCamCeil
	lda camXHi
	cmp #CAMXMAXHI
	bcc blCamCol
	bne blCamCap
	lda camXLo
	cmp #CAMXMAXLO
	bcc blCamCol
blCamCap
	lda #CAMXMAXLO
	sta camXLo
	lda #CAMXMAXHI
	sta camXHi
blCamCol
	lda camXLo
	sta tmpLo
	lda camXHi
	sta tmpHi
	lsr tmpHi
	ror tmpLo
	lsr tmpHi
	ror tmpLo
	lsr tmpHi
	ror tmpLo
	lda tmpLo
	sta camCol
	sta visCX
	lda peterY
	sec
	sbc #96
	bcs blCamY
	lda #0
blCamY
	cmp #CAMYMAX
	bcc blCamY2
	lda #CAMYMAX
blCamY2
	sta camY
	lsr
	lsr
	lsr
	sta camRow
	sta visCY
	jsr musicStart
	jsr renderView
	jmp updateSprites

; char -> color table, rebuilt each level (the gate entry mutates;
; each chapter brings its own light)
initColTab
	ldx #0
	lda #1                 ; default: white (text, digits)
ictFill
	sta COLTAB,x
	inx
	bne ictFill
	; per-chapter char colors: base = lvCharCol + level*9
	lda level
	asl
	asl
	asl
	clc
	adc level              ; *9
	clc
	adc #<lvCharCol
	sta txtPtr
	lda #>lvCharCol
	adc #0
	sta txtPtr+1
	ldy #CHAR_COUNT-1
ictPatch
	lda (txtPtr),y
	sta COLTAB+CHAR_FIRST,y
	dey
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
	; remember the first 8: chapter 4 hides the rope under one
	ldx rockN
	cpx #8
	bcs srSkip
	lda tmp
	sta rockColW,x
	lda tmpHi
	sta rockRowW,x
	lda #0
	sta rockDoneW,x
	inc rockN
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
; A/Y = 12-byte text lo/hi
renderHud
	sta txtPtr
	sty txtPtr+1
	ldy #11
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

; refresh the NEXT/GOT digits inside the live HUD string (ch1)
updateHudDigits
	lda gateOpen
	bne uhdDone
	lda nextNum
	clc
	adc #48
	sta hudLine+2
	lda gotCount
	clc
	adc #48
	sta hudLine+9
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

; per-chapter char colors live in lvCharCol (high section)

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

; per-chapter messages live in the high section

; HUD text: exactly 12 chars = 4 sprites x 3 glyphs
hudLine	dc.b "N:1  GOT:0/5"
hudGate	dc.b "GO EAST! 5/5"
; destination of each glyph column inside the HUD sprite block
hudDstLo
	dc.b <(HUDSPR+0),<(HUDSPR+1),<(HUDSPR+2)
	dc.b <(HUDSPR+64),<(HUDSPR+65),<(HUDSPR+66)
	dc.b <(HUDSPR+128),<(HUDSPR+129),<(HUDSPR+130)
	dc.b <(HUDSPR+192),<(HUDSPR+193),<(HUDSPR+194)
hudDstHi
	dc.b >(HUDSPR+0),>(HUDSPR+1),>(HUDSPR+2)
	dc.b >(HUDSPR+64),>(HUDSPR+65),>(HUDSPR+66)
	dc.b >(HUDSPR+128),>(HUDSPR+129),>(HUDSPR+130)
	dc.b >(HUDSPR+192),>(HUDSPR+193),>(HUDSPR+194)
row3Tab	dc.b 0,3,6,9,12,15,18,21
hudXTab	dc.b 136,160,184,208       ; centred over the view

; sfx tables: (frames,freqHi) pairs, 0 = end
sfxWhistle	dc.b 5,$68,6,$8c,0
sfxBuzz	dc.b 10,$06,0
sfxCaught	dc.b 8,$30,8,$24,8,$1a,12,$10,0
sfxWin	dc.b 7,$40,7,$50,7,$60,14,$80,0

; peter sprite pointer base + walk-frame stride, by peterDir
; layout: $80 D1,$81 D2,$82 U1,$83 U2,$84 L1,$85 R1,$86 L2,$87 R2
peterBase	dc.b SPRBASE+0,SPRBASE+2,SPRBASE+4,SPRBASE+5
peterStride	dc.b 1,1,2,2

; foe sprite pointer bases live in ZP (foeA/foeB), set per chapter

; music: song table + per-song instrument, indexed by song id
; 0 peter, 1 wolf, 2 bird, 3 duck, 4 grandpa, 5 hunters, 6 cat
songLo	dc.b <songPeterData,<songWolfData,<songBirdData,<songDuckData
	dc.b <songGrandpaData,<songHuntersData,<songCatData
songHi	dc.b >songPeterData,>songWolfData,>songBirdData,>songDuckData
	dc.b >songGrandpaData,>songHuntersData,>songCatData
musWaveTab	dc.b $41,$21,$41,$21,$21,$41,$21
musAdTab	dc.b $18,$28,$08,$18,$38,$28,$18
; switch to the foe's theme inside the small box, back to the
; chapter's own only outside the big one (indexed by musDanger)
musDxThresh	dc.b 88,120
musDyThresh	dc.b 80,112

; ============================================================
	org $2000              ; sprite data, pointer $80+
	include "build/sprites.inc"

	org $2540              ; more frames above the HUD block ($95+)
	include "build/sprites2.inc"

; ============================================================
;  chapter logic - lives above the VIC buffers ($5500+).
;  (the loader's zero-fill between here and the sprites lands on
;  buffers that are rebuilt at init: screens, charset, map)
; ============================================================
	org $5500

; ---- per-frame chapter work: prey pick, friend, FIRE, wins ----
levelTick
	; prey: chapter 2/3 foes stalk the waiting friend
	lda peterXLo
	sta preyXLo
	lda peterXHi
	sta preyXHi
	lda peterY
	sta preyY
	lda frType
	beq ltFriendDone
	lda level
	cmp #1
	beq ltPreyF
	cmp #2
	bne ltFriendDone
ltPreyF
	lda frState
	bne ltFriendDone
	lda frXLo
	sta preyXLo
	lda frXHi
	sta preyXHi
	lda frY
	sta preyY
ltFriendDone
	jsr moveFriend
	jsr fireAction
	lda level
	bne ltNoPickup
	jsr checkPickup        ; numbered apples: chapter 1 only
ltNoPickup
	jsr winCheck
	jsr friendCaught
	; timed HUD message: restore the chapter line when it expires
	lda hudMsgT
	beq ltDone
	dec hudMsgT
	bne ltDone
	ldx level
	lda lvHudLo,x
	ldy lvHudHi,x
	jsr renderHud
ltDone
	rts

; ---- friend: waits, then follows peter two steps behind ----
moveFriend
	lda frType
	bne mfGo
	rts
mfGo
	lda frState
	bne mfFollow
	; waiting: has peter come close?
	jsr frDeltaX
	lda tmpHi
	bne mfOut
	lda tmpLo
	cmp #40
	bcs mfOut
	jsr frDeltaY
	cmp #32
	bcs mfOut
	inc frState            ; found!
	lda #<sfxChirp
	ldx #>sfxChirp
	jsr sfxStart
	; grandfather unlocks his gate (ch5)
	lda level
	cmp #4
	bne mfOut
	inc gateOpen
	lda #7
	sta COLTAB+GATE_CH
	jsr paintGateVisible
	lda #<hudGate5
	ldy #>hudGate5
	jmp hudMsg
mfOut
	rts
mfFollow
	; x: step 2 toward peter while farther than 14
	lda peterXLo
	sec
	sbc frXLo
	sta tmpLo
	lda peterXHi
	sbc frXHi
	sta tmpHi
	bpl mfXpos
	lda #0
	sec
	sbc tmpLo
	sta tmpLo
	lda #0
	sbc tmpHi
	sta tmpHi
	lda tmpHi
	bne mfLgo
	lda tmpLo
	cmp #15
	bcc mfY
mfLgo
	lda #0
	sta frFace
	lda frXLo
	sec
	sbc #2
	sta frXLo
	lda frXHi
	sbc #0
	sta frXHi
	jmp mfY
mfXpos
	lda tmpHi
	bne mfRgo
	lda tmpLo
	cmp #15
	bcc mfY
mfRgo
	lda #1
	sta frFace
	lda frXLo
	clc
	adc #2
	sta frXLo
	lda frXHi
	adc #0
	sta frXHi
mfY
	lda peterY
	cmp frY
	bcs mfYdown
	lda frY
	sec
	sbc peterY
	cmp #11
	bcc mfDone
	dec frY
	dec frY
	rts
mfYdown
	lda peterY
	sec
	sbc frY
	cmp #11
	bcc mfDone
	inc frY
	inc frY
mfDone
	rts

frDeltaX               ; |peterX - frX| -> tmpLo/tmpHi
	lda peterXLo
	sec
	sbc frXLo
	sta tmpLo
	lda peterXHi
	sbc frXHi
	sta tmpHi
	bpl fdxP
	lda #0
	sec
	sbc tmpLo
	sta tmpLo
	lda #0
	sbc tmpHi
	sta tmpHi
fdxP
	rts

frDeltaY               ; |peterY - frY| -> A
	lda peterY
	sec
	sbc frY
	bcs fdyP
	eor #$ff
	clc
	adc #1
fdyP
	rts

; ---- friend sprite (3): called inside updateSprites ----
drawFriend
	lda frType
	bne dfGo
	rts
dfGo
	lda frXLo
	sec
	sbc camXLo
	sta newXLo
	lda frXHi
	sbc camXHi
	sta newXHi
	bmi dfHide
	beq dfY
	cmp #1
	bne dfHide
	lda newXLo
	cmp #58
	bcs dfHide
dfY
	lda frY
	sec
	sbc camY
	bcc dfHide
	cmp #168
	bcs dfHide
	clc
	adc #54
	sta $d007
	lda newXLo
	clc
	adc #31
	sta $d006
	lda newXHi
	adc #0
	and #1
	beq dfNoHi
	lda tmp
	ora #%00001000
	sta tmp
dfNoHi
	lda d015m
	ora #%00001000
	sta d015m
	; pointer: base + face + gait
	lda frame
	and #8
	lsr
	lsr                    ; 0 or 2
	clc
	adc frBase
	clc
	adc frFace
	sta SCREENA+$3fb
	sta SCREENB+$3fb
dfHide
	rts

; ---- FIRE: whistle everywhere; in ch4 search rocks / set snare ----
fireAction
	lda level
	cmp #3
	beq faRope
	jmp whistle
faRope
	lda fireEdge
	bne faEdge
	rts
faEdge
	jsr nearRock
	bcc faOak
	; search this rock
	lda #1
	sta rockDoneW,x
	cpx ropeRock
	beq faFound
	lda #<hudNoRope
	ldy #>hudNoRope
	jsr hudMsg
	lda #<sfxBuzz
	ldx #>sfxBuzz
	jmp sfxStart
faFound
	lda #1
	sta carryRope
	lda #<hudRope
	ldy #>hudRope
	jsr hudMsg
	lda #<sfxWin
	ldx #>sfxWin
	jmp sfxStart
faOak
	lda carryRope
	beq faWhistle
	jsr nearOak
	bcc faWhistle
	lda #0
	sta carryRope
	lda #1
	sta snareArm
	lda #<hudSnare
	ldy #>hudSnare
	jsr hudMsg
	lda #<sfxWin
	ldx #>sfxWin
	jmp sfxStart
faWhistle
	jmp whistle

; ---- is peter beside an unsearched rock? C=1, X=index ----
nearRock
	lda peterXLo
	clc
	adc #12
	sta tmpLo
	lda peterXHi
	adc #0
	lsr
	ror tmpLo
	lsr
	ror tmpLo
	lsr
	ror tmpLo              ; tmpLo = peter's column
	lda peterY
	clc
	adc #18
	lsr
	lsr
	lsr
	sta tmpHi              ; peter's row
	ldx rockN
	beq nrNo
	dex
nrLoop
	lda rockDoneW,x
	bne nrNext
	lda rockColW,x
	sec
	sbc tmpLo
	jsr abs8
	cmp #2
	bcs nrNext
	lda rockRowW,x
	sec
	sbc tmpHi
	jsr abs8
	cmp #2
	bcs nrNext
	sec
	rts
nrNext
	dex
	bpl nrLoop
nrNo
	clc
	rts

abs8
	bpl abs8Done
	eor #$ff
	clc
	adc #1
abs8Done
	rts

; ---- is peter at the big oak? C=1 ----
nearOak
	lda peterXLo
	clc
	adc #12
	sta tmpLo
	lda peterXHi
	adc #0
	sta tmpHi
	lda tmpLo
	sec
	sbc #<496
	sta tmpLo
	lda tmpHi
	sbc #>496
	sta tmpHi
	bpl noAbs
	lda #0
	sec
	sbc tmpLo
	sta tmpLo
	lda #0
	sbc tmpHi
	sta tmpHi
noAbs
	lda tmpHi
	bne noFar
	lda tmpLo
	cmp #40
	bcs noFar
	lda peterY
	clc
	adc #18
	sec
	sbc #112
	jsr abs8
	cmp #44
	bcs noFar
	sec
	rts
noFar
	clc
	rts

; ---- is the foe under the oak? C=1 ----
wolfAtOak
	lda wolfXLo
	clc
	adc #24
	sta tmpLo
	lda wolfXHi
	adc #0
	sta tmpHi
	lda tmpLo
	sec
	sbc #<496
	sta tmpLo
	lda tmpHi
	sbc #>496
	sta tmpHi
	bpl waAbs
	lda #0
	sec
	sbc tmpLo
	sta tmpLo
	lda #0
	sbc tmpHi
	sta tmpHi
waAbs
	lda tmpHi
	bne waNo
	lda tmpLo
	cmp #44
	bcs waNo
	lda wolfY
	clc
	adc #18
	sec
	sbc #112
	jsr abs8
	cmp #48
	bcs waNo
	sec
	rts
waNo
	clc
	rts

; ---- per-chapter win conditions ----
winCheck
	lda level
	beq wcDone             ; ch1: walking the gate sets winFlag
	cmp #1
	beq wcBird
	cmp #2
	beq wcDuck
	cmp #3
	beq wcSnare
	cmp #4
	beq wcDone             ; ch5: the gate again
wcSnare
	lda snareArm
	beq wcDone
	jsr wolfAtOak
	bcc wcDone
	inc winFlag
	rts
wcBird
	lda frState
	beq wcDone
	jsr nearOak
	bcc wcDone
	inc winFlag
	rts
wcDuck
	lda frState
	beq wcDone
	lda peterXLo
	clc
	adc #12
	sta tmpLo
	lda peterXHi
	adc #0
	cmp #2                 ; pond zone: x 544..648
	bne wcDone
	lda tmpLo
	cmp #32
	bcc wcDone
	cmp #137
	bcs wcDone
	lda peterY
	clc
	adc #18
	cmp #28                ; y 28..84
	bcc wcDone
	cmp #85
	bcs wcDone
	inc winFlag
wcDone
	rts

; ---- the foe takes the waiting friend: lose ----
friendCaught
	lda frType
	beq fcDone
	lda frState
	bne fcDone
	lda level
	cmp #1
	beq fcGo
	cmp #2
	bne fcDone
fcGo
	lda wolfXLo
	clc
	adc #24
	sta tmpLo
	lda wolfXHi
	adc #0
	sta tmpHi
	lda frXLo
	clc
	adc #6
	sta newXLo
	lda frXHi
	adc #0
	sta newXHi
	lda tmpLo
	sec
	sbc newXLo
	sta tmpLo
	lda tmpHi
	sbc newXHi
	sta tmpHi
	bpl fcAbs
	lda #0
	sec
	sbc tmpLo
	sta tmpLo
	lda #0
	sbc tmpHi
	sta tmpHi
fcAbs
	lda tmpHi
	bne fcDone
	lda tmpLo
	cmp #22
	bcs fcDone
	lda wolfY
	sec
	sbc frY
	jsr abs8
	cmp #18
	bcs fcDone
	; the friend is taken!
	lda #1
	sta state
	lda #40
	sta msgTimer
	ldx level
	lda msgFriendLo,x
	ldy msgFriendHi,x
	jsr drawMsg
	lda #<sfxCaught
	ldx #>sfxCaught
	jmp sfxStart
fcDone
	rts

; A/Y = 12-char line: show it on the HUD for ~3 seconds
hudMsg
	jsr renderHud
	lda #150
	sta hudMsgT
	rts


; ============================================================
;  autopilot: the game plays itself (test builds / demo)
; ============================================================
autoPilot
	lda state
	beq apPlay
	lda frame              ; message screens: tap FIRE
	and #15
	bne apIdle
	lda #%00010000
	sta joy
	rts
apIdle
	lda #0
	sta joy
	rts
apPlay
	jsr apGoal
	lda #0
	sta joy
	; steer x
	lda peterXLo
	sec
	sbc autGXLo
	sta tmpLo
	lda peterXHi
	sbc autGXHi
	sta tmpHi
	bpl apXpos
	lda #0
	sec
	sbc tmpLo
	sta tmpLo
	lda #0
	sbc tmpHi
	sta tmpHi
	lda tmpHi
	bne apRight
	lda tmpLo
	cmp #4
	bcc apY
apRight
	lda joy
	ora #%00001000
	sta joy
	jmp apY
apXpos
	lda tmpHi
	bne apLeft
	lda tmpLo
	cmp #4
	bcc apY
apLeft
	lda joy
	ora #%00000100
	sta joy
apY
	; steer y
	lda peterY
	cmp autGY
	beq apStuck
	bcs apUp
	lda autGY
	sec
	sbc peterY
	cmp #4
	bcc apStuck
	lda joy
	ora #%00000010
	sta joy
	jmp apStuck
apUp
	lda peterY
	sec
	sbc autGY
	cmp #4
	bcc apStuck
	lda joy
	ora #%00000001
	sta joy
apStuck
	; committed detour in progress? slide along the obstacle
	lda autWander
	beq apChkStuck
	dec autWander
	lda joy
	ora autDir
	sta joy
	jmp apFireBtn
apChkStuck
	; wedged against something? detour perpendicular for a while
	lda joy
	and #%00001111
	beq apFireBtn
	lda peterXLo
	cmp autSnapX
	bne apMoved
	lda peterY
	cmp autSnapY
	bne apMoved
	inc autStuck
	lda autStuck
	cmp #40
	bcc apFireBtn
	lda #0
	sta autStuck
	lda #55
	sta autWander
	lda autFlip
	eor #1
	sta autFlip
	; steering mostly horizontal? detour vertically (and vice versa)
	lda joy
	and #%00001100
	beq apDetH
	lda autFlip
	beq apDetDown
	lda #%00000001         ; up
	sta autDir
	jmp apFireBtn
apDetDown
	lda #%00000010         ; down
	sta autDir
	jmp apFireBtn
apDetH
	lda autFlip
	beq apDetRight
	lda #%00000100         ; left
	sta autDir
	jmp apFireBtn
apDetRight
	lda #%00001000         ; right
	sta autDir
	jmp apFireBtn
apMoved
	lda peterXLo
	sta autSnapX
	lda peterY
	sta autSnapY
	lda #0
	sta autStuck
apFireBtn
	; FIRE: ch4 searches and arms; otherwise whistle when hunted
	lda level
	cmp #3
	bne apWhistle
	jsr nearRock
	bcs apPress
	lda carryRope
	beq apWhistle
	jsr nearOak
	bcs apPress
apWhistle
	lda level
	cmp #5
	beq apDone             ; the chase: lead him in, don't stun him
	cmp #3
	bne apWh2
	lda snareArm
	bne apDone             ; snare set: let him blunder into it
apWh2
	lda cooldown
	bne apDone
	jsr absDx
	lda tmpHi
	bne apDone
	lda tmpLo
	cmp #64
	bcs apDone
	jsr absDy
	cmp #48
	bcs apDone
apPress
	lda frame
	and #7
	bne apDone
	lda joy
	ora #%00010000
	sta joy
apDone
	rts

apWander	dc.b %00000001,%00001000,%00000010,%00000100

; where should the autopilot walk? -> autGX/autGY
apGoal
	lda level
	beq agApples
	cmp #1
	bne agN2
	jmp agFriendOak
agN2
	cmp #2
	bne agN3
	jmp agFriendPond
agN3
	cmp #3
	bne agN4
	jmp agRope
agN4
	cmp #4
	bne agN5
	jmp agFriendGate
agN5
	jmp agOak              ; ch6: wait by the oak
agApples
	lda gateOpen
	bne agGate
	ldx #N_APPLES-1
agAscan
	lda appleNumW,x
	cmp nextNum
	beq agAfound
	dex
	bpl agAscan
agGate
	lda #<1000
	sta autGXLo
	lda #>1000
	sta autGXHi
	lda #110
	sta autGY
	rts
agAfound
	lda #0
	sta autGXHi
	lda appleColW,x
	asl
	rol autGXHi
	asl
	rol autGXHi
	asl
	rol autGXHi
	sec
	sbc #8
	sta autGXLo
	bcs agAy
	dec autGXHi
agAy
	lda appleRowW,x
	asl
	asl
	asl
	sec
	sbc #14
	jsr agClampY
	sta autGY
	rts
agFriendOak
	lda frState
	bne agOak
agFriendGoto
	lda frXLo
	sec
	sbc #12
	sta autGXLo
	lda frXHi
	sbc #0
	sta autGXHi
	lda frY
	sta autGY
	rts
agOak
	; stand a little WEST of the trunk: the wolf coming from the
	; east then springs the snare well before he reaches peter
	lda #<464
	sta autGXLo
	lda #>464
	sta autGXHi
	lda #106
	sta autGY
	rts
agFriendPond
	lda frState
	beq agFriendGoto
	lda #<584
	sta autGXLo
	lda #>584
	sta autGXHi
	lda #58
	sta autGY
	rts
agRope
	lda snareArm
	bne agOak
	lda carryRope
	bne agOak
	ldx rockN
	beq agOak
	dex
agRscan
	lda rockDoneW,x
	beq agRfound
	dex
	bpl agRscan
	jmp agOak
agRfound
	lda #0
	sta autGXHi
	lda rockColW,x
	asl
	rol autGXHi
	asl
	rol autGXHi
	asl
	rol autGXHi
	sec
	sbc #8
	sta autGXLo
	bcs agRy
	dec autGXHi
agRy
	lda rockRowW,x
	asl
	asl
	asl
	sec
	sbc #14
	jsr agClampY
	sta autGY
	rts
agFriendGate
	lda frState
	beq agFriendGoto
	jmp agGate

agClampY
	cmp #236
	bcc agCyOk
	lda #2                 ; wrapped negative: aim just below the top
agCyOk
	rts

; ============================================================
;  chapter tables
; ============================================================
lvBg	dc.b 13,13,14,0,0,13
; char colors per chapter (9 each):
; tuft flower rock water apple canopy trunkL trunkR gate
lvCharCol
	dc.b 5,7,12,14,2,5,9,9,9      ; 1 day meadow
	dc.b 8,7,12,14,2,5,9,9,9      ; 2 golden afternoon
	dc.b 6,3,12,6,2,6,9,9,9       ; 3 blue dusk
	dc.b 11,12,12,6,2,11,9,9,9    ; 4 night
	dc.b 11,12,12,6,2,11,9,9,9    ; 5 deep night
	dc.b 5,7,12,14,2,5,9,9,9      ; 6 day again
lvFriend	dc.b 0,1,2,0,3,0           ; none/bird/duck/none/grandpa/none
lvFriendCol	dc.b 0,14,1,0,15,0
lvFoeCat	dc.b 0,1,0,0,0,0
lvFoeCol	dc.b 11,8,11,11,11,11
lvSong	dc.b 0,2,3,1,4,5           ; peter bird duck wolf grandpa hunters
lvDanger	dc.b 1,6,1,1,1,1           ; wolf theme, cat theme in ch2
lvPeterXLo	dc.b 48,48,48,48,48,<900
lvPeterXHi	dc.b 0,0,0,0,0,>900
lvPeterY	dc.b 140,140,140,140,140,140
lvFoeXLo	dc.b <700,<700,<700,<700,<700,<960
lvFoeXHi	dc.b >700,>700,>700,>700,>700,>960
lvFoeY	dc.b 60,60,60,60,60,60
lvFrXLo	dc.b 0,<260,<250,0,<500,0
lvFrXHi	dc.b 0,>260,>250,0,>500,0
lvFrY	dc.b 0,200,80,0,170,0
frBaseTab	dc.b $9d,$a1,$a5           ; bird, duck, grandpa (left base)

; HUD lines (12 chars each)
hud2	dc.b "2 SAVE BIRD "
hud3	dc.b "3 TO POND   "
hud4	dc.b "4 FIND ROPE "
hud5	dc.b "5 GATE HOME "
hud6	dc.b "6 RUN WEST  "
hudRope	dc.b "ROPE! TO OAK"
hudNoRope	dc.b "NOTHING HERE"
hudSnare	dc.b "SNARE IS SET"
hudGate5	dc.b "TO THE GATE "
lvHudLo	dc.b <hudLine,<hud2,<hud3,<hud4,<hud5,<hud6
lvHudHi	dc.b >hudLine,>hud2,>hud3,>hud4,>hud5,>hud6

; recorded rocks (ch4's hiding places)
rockColW	ds.b 8
rockRowW	ds.b 8
rockDoneW	ds.b 8

; message screens
msgCaughtW	dc.b "THE WOLF GOT YOU!  PRESS FIRE",0
msgCaughtC	dc.b "THE CAT GOT YOU!  PRESS FIRE",0
msgFriendB	dc.b "THE CAT TOOK THE BIRD! PRESS FIRE",0
msgFriendD	dc.b "THE WOLF TOOK THE DUCK! PRESS FIRE",0
msgWin1	dc.b "YOU ESCAPED THE MEADOW! PRESS FIRE",0
msgWin2	dc.b "THE BIRD IS SAFE! PRESS FIRE",0
msgWin3	dc.b "THE DUCK IS HOME! PRESS FIRE",0
msgWin4	dc.b "THE WOLF IS CAUGHT! PRESS FIRE",0
msgWin5	dc.b "SAFE AT THE GATE! PRESS FIRE",0
msgWin6	dc.b "THE WOLF IS CAUGHT! THE END",0
msgWinLo	dc.b <msgWin1,<msgWin2,<msgWin3,<msgWin4,<msgWin5,<msgWin6
msgWinHi	dc.b >msgWin1,>msgWin2,>msgWin3,>msgWin4,>msgWin5,>msgWin6
msgCaughtLo	dc.b <msgCaughtW,<msgCaughtC,<msgCaughtW,<msgCaughtW,<msgCaughtW,<msgCaughtW
msgCaughtHi	dc.b >msgCaughtW,>msgCaughtC,>msgCaughtW,>msgCaughtW,>msgCaughtW,>msgCaughtW
msgFriendLo	dc.b 0,<msgFriendB,<msgFriendD,0,0,0
msgFriendHi	dc.b 0,>msgFriendB,>msgFriendD,0,0,0

sfxChirp	dc.b 4,$50,4,$70,0

	include "build/music.inc"

; custom character bitmaps (copied over the ROM set at init)
	include "build/chars.inc"
