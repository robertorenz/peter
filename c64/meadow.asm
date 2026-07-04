; ============================================================
;  PETER AND THE WOLF - Level 1: The Meadow
;  Commodore 64 port skeleton (dasm syntax)
;
;  Gather the numbered apples IN ORDER, then escape through
;  the gate on the right - while the wolf hunts you down.
;  Joystick port 2 moves Peter; FIRE blows the whistle, which
;  stuns the wolf for a moment (long cooldown).
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
peterXLo  equ $0b
peterXHi  equ $0c
peterY    equ $0d
wolfXLo   equ $0e
wolfXHi   equ $0f
wolfY     equ $10
wolfFace  equ $11          ; 0=left 2=right (sprite pointer offset)
moving    equ $12
msgTimer  equ $13          ; delay before FIRE accepted on message screens
buzzTimer equ $14          ; rate-limits the wrong-apple buzz
sfxTimer  equ $15
sfxPtr    equ $16          ; ..$17
lastCol   equ $18          ; set by getCell
lastRow   equ $19
tmpLo     equ $1a
tmpHi     equ $1b
tmp       equ $1c
dynBuf    equ $1d          ; ..$1f: 3-byte RAM sfx (dur,freq,0)
winFlag   equ $20
rndSeed   equ $21
newXLo    equ $22          ; candidate X while moving (getCell eats tmpLo)
newXHi    equ $23
musPtr    equ $24          ; ..$25 current music note pointer
musTimer  equ $26
musSong   equ $27          ; 0 = peter's theme, 1 = wolf's theme
musWave   equ $28          ; SID waveform of the current song's voice
colPtr    equ $f9          ; ..$fa color RAM pointer
scrPtr    equ $fb          ; ..$fc screen RAM pointer
txtPtr    equ $fd          ; ..$fe text pointer

; ---------------- constants ----------------
SCREEN    equ $0400
COLRAM    equ $d800
CHARSET   equ $3800        ; VIC sees this via $d018=$1e
SPRBASE   equ $80          ; $2000/64
APPLE_CH  equ 132
GATE_CH   equ 136
N_APPLES  equ 5

; ============================================================
	org $0801
	; 10 SYS 2061
	dc.b $0b,$08,$0a,$00,$9e,"2061",$00,$00,$00

start
	sei
	jsr copyCharset
	jsr initVic
	jsr initSid
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
	jsr tick
	jmp mainloop

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
	lda #%00000111
	sta $d015              ; sprites 0 (peter) + 1/2 (wolf front + rear)
	sta $d01c              ; all multicolor
	lda #0
	sta $d01d              ; no expansion: the wolf is two real sprites
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
	; ---- horizontal ----
	lda peterXLo
	sta newXLo
	lda peterXHi
	sta newXHi
	lda joy
	and #%00001000
	beq mpTryLeft
	; right +2
	lda newXLo
	clc
	adc #2
	sta newXLo
	lda newXHi
	adc #0
	sta newXHi
	; clamp to 318 ($013e)
	beq mpXGo
	lda newXLo
	cmp #$3e
	bcc mpXGo
	lda #$3e
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
	; clamp to 24
	bne mpXGo
	lda newXLo
	cmp #24
	bcs mpXGo
	lda #24
	sta newXLo
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
	cmp #44
	bcs mpYGo
	lda #44
	jmp mpYGo
mpTryDown
	lda joy
	and #%00000010
	beq mpDone
	lda peterY
	clc
	adc #2
	cmp #228
	bcc mpYGo
	lda #228
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
; getCell: tmpLo/Hi = pixel X (sprite coords), A = pixel Y.
; Returns A = screen code at Peter's feet, sets lastCol/lastRow
; and scrPtr/colPtr to the row base.  Clobbers tmpLo/Hi.
; ============================================================
getCell
	sec
	sbc #32                ; sprite Y -> foot row: (y-50+18)/8
	lsr
	lsr
	lsr
	sta lastRow
	tax
	lda rowLo,x
	sta scrPtr
	sta colPtr
	lda rowHi,x
	sta scrPtr+1
	clc
	adc #$d4               ; $0400 screen -> $d800 color
	sta colPtr+1
	; sprite X -> centre column: (x-24+12)/8
	lda tmpLo
	sec
	sbc #12
	sta tmpLo
	lda tmpHi
	sbc #0
	lsr
	ror tmpLo
	lsr
	ror tmpLo
	lsr
	ror tmpLo
	lda tmpLo
	sta lastCol
	tay
	lda (scrPtr),y
	rts

; A = screen code -> carry set if blocked.  Walking into the
; open gate sets winFlag instead.
checkBlocked
	cmp #GATE_CH
	beq cbGate
	cmp #130
	bcc cbClear            ; grass, text, digits, space
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
	lda #32
	ldy tmp
	sta (scrPtr),y
	iny
	sta (scrPtr),y
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
	beq cpAllDone
	jmp drawStatusDigits
cpAllDone
	inc gateOpen
	lda #<statusB          ; "GATE OPEN! RUN RIGHT"
	ldy #>statusB
	jsr drawStatus
	; light the gate up yellow
	ldx #10
cpGateCol
	lda rowLo,x
	sta colPtr
	lda rowHi,x
	clc
	adc #$d4
	sta colPtr+1
	ldy #38
	lda #7
	sta (colPtr),y
	iny
	sta (colPtr),y
	inx
	cpx #15
	bne cpGateCol
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
; wolf: hunts Peter but respects trees/rocks/water, sidestepping
; around whatever blocks the straight line
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
mwXtry
	; wolf centre foot cell: getCell expects centre+12 like peter
	lda newXLo
	clc
	adc #36
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
	adc #36
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

; like checkBlocked but the gate is ALWAYS solid to the wolf
; (and never sets winFlag)
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
; sprites -> VIC registers
; ============================================================
updateSprites
	lda peterXLo
	sta $d000
	lda peterY
	sta $d001
	; wolf: two sprites side by side, rear half at +24
	lda wolfXLo
	sta $d002
	lda wolfY
	sta $d003
	sta $d005
	lda wolfXLo
	clc
	adc #24
	sta $d004
	lda wolfXHi
	adc #0
	and #1
	asl
	asl
	sta tmp                ; sprite 2 MSB, in place
	; X MSBs: bit0 peter, bit1 wolf front, bit2 wolf rear
	lda peterXHi
	and #1
	sta tmpHi
	lda wolfXHi
	and #1
	asl
	ora tmpHi
	ora tmp
	sta $d010
	; peter animation: walk cycle only while moving
	ldx #SPRBASE
	lda moving
	beq usPeterSet
	lda frame
	and #8
	beq usPeterSet
	inx
usPeterSet
	stx SCREEN+$3f8
	; wolf pointers: base by facing, +4 for the second gait frame
	lda frame
	and #8
	lsr                    ; 0 or 4
	sta tmp
	ldx wolfFace           ; 0=left 1=right
	lda wolfBaseA,x
	clc
	adc tmp
	sta SCREEN+$3f9
	lda wolfBaseB,x
	clc
	adc tmp
	sta SCREEN+$3fa
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
; level build / reset
; ============================================================
buildLevel
	; clear playfield rows 1..24
	ldx #1
blClrRow
	lda rowLo,x
	sta scrPtr
	lda rowHi,x
	sta scrPtr+1
	lda #32
	ldy #39
blClrCol
	sta (scrPtr),y
	dey
	bpl blClrCol
	inx
	cpx #25
	bne blClrRow

	jsr scatterGrass
	jsr drawPond
	jsr drawTrees
	jsr drawRocks
	jsr drawGate
	jsr resetApples

	lda #<statusA
	ldy #>statusA
	jsr drawStatus

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
	lda #1
	sta nextNum
	jsr drawStatusDigits
	; positions: peter mid-left, wolf top-right
	lda #50
	sta peterXLo
	lda #0
	sta peterXHi
	lda #180
	sta peterY
	lda #$18               ; 280 = $0118
	sta wolfXLo
	lda #$01
	sta wolfXHi
	lda #70
	sta wolfY
	lda #11
	sta $d028
	sta $d029
	jsr musicStart
	jmp updateSprites

; ---- deterministic grass + flowers via 8-bit LFSR ----
scatterGrass
	lda #$a7
	sta rndSeed
	ldx #0
sgLoop
	txa
	pha
	jsr rnd
	and #63
	cmp #40
	bcs sgSkip
	sta tmp                ; column
	jsr rnd
	and #31
	cmp #2
	bcc sgSkip
	cmp #25
	bcs sgSkip
	tax                    ; row
	lda rowLo,x
	sta scrPtr
	sta colPtr
	lda rowHi,x
	sta scrPtr+1
	clc
	adc #$d4
	sta colPtr+1
	ldy tmp
	lda (scrPtr),y
	cmp #32
	bne sgSkip
	jsr rnd
	and #1
	beq sgTuft
	lda #129               ; flower
	sta (scrPtr),y
	lda #7                 ; yellow
	sta (colPtr),y
	jmp sgSkip
sgTuft
	lda #128
	sta (scrPtr),y
	lda #5                 ; green
	sta (colPtr),y
sgSkip
	pla
	tax
	inx
	cpx #200
	bne sgLoop
	rts

rnd
	lda rndSeed
	asl
	bcc rndNoEor
	eor #$1d
rndNoEor
	sta rndSeed
	rts

; ---- pond, bottom left ----
drawPond
	ldx #0
dpLoop
	lda pondRow,x
	tay
	lda rowLo,y
	sta scrPtr
	sta colPtr
	lda rowHi,y
	sta scrPtr+1
	clc
	adc #$d4
	sta colPtr+1
	lda pondLen,x
	sta tmp
	ldy pondCol,x
dpCell
	lda #131
	sta (scrPtr),y
	lda #14                ; light blue
	sta (colPtr),y
	iny
	dec tmp
	bne dpCell
	inx
	cpx #4
	bne dpLoop
	rts

; ---- trees: 2x2 (canopy pair over trunk pair); oak is 4x2+trunk ----
drawTrees
	ldx #0
dtLoop
	txa
	pha
	lda treeRow,x
	pha
	lda treeCol,x
	tay
	pla
	tax                    ; X=row Y=col
	jsr setRowPtrs
	lda #133
	sta (scrPtr),y
	iny
	sta (scrPtr),y
	dey
	lda #5
	sta (colPtr),y
	iny
	sta (colPtr),y
	inx
	jsr setRowPtrs
	dey
	lda #134
	sta (scrPtr),y
	iny
	lda #135
	sta (scrPtr),y
	dey
	lda #9                 ; brown
	sta (colPtr),y
	iny
	sta (colPtr),y
	pla
	tax
	inx
	cpx #N_TREES
	bne dtLoop
	; ---- the big oak: canopy 4 wide x 2 tall at (19,10), trunk row 12 ----
	ldx #10
dtOakRow
	jsr setRowPtrs
	ldy #19
dtOakCell
	lda #133
	sta (scrPtr),y
	lda #5
	sta (colPtr),y
	iny
	cpy #23
	bne dtOakCell
	inx
	cpx #12
	bne dtOakRow
	jsr setRowPtrs         ; x=12: trunk
	ldy #20
	lda #134
	sta (scrPtr),y
	lda #9
	sta (colPtr),y
	iny
	lda #135
	sta (scrPtr),y
	lda #9
	sta (colPtr),y
	rts

; X=row -> scrPtr/colPtr (preserves X and Y)
setRowPtrs
	lda rowLo,x
	sta scrPtr
	sta colPtr
	lda rowHi,x
	sta scrPtr+1
	clc
	adc #$d4
	sta colPtr+1
	rts

drawRocks
	ldx #0
drLoop
	txa
	pha
	lda rockRow,x
	pha
	lda rockCol,x
	tay
	pla
	tax
	jsr setRowPtrs
	lda #130
	sta (scrPtr),y
	lda #12                ; grey
	sta (colPtr),y
	pla
	tax
	inx
	cpx #N_ROCKS
	bne drLoop
	rts

drawGate
	; two columns wide so Peter's foot cell can actually reach it
	ldx #10
dgLoop
	jsr setRowPtrs
	ldy #38
	lda #GATE_CH
	sta (scrPtr),y
	lda #9
	sta (colPtr),y
	iny
	lda #GATE_CH
	sta (scrPtr),y
	lda #9
	sta (colPtr),y
	inx
	cpx #15
	bne dgLoop
	rts

resetApples
	ldx #N_APPLES-1
raCopy
	lda appleCol,x
	sta appleColW,x
	lda appleRow,x
	sta appleRowW,x
	lda appleNum,x
	sta appleNumW,x
	dex
	bpl raCopy
	ldx #0
raDraw
	txa
	pha
	lda appleRow,x
	pha
	lda appleNum,x
	sta tmp
	lda appleCol,x
	tay
	pla
	tax
	jsr setRowPtrs
	lda #APPLE_CH
	sta (scrPtr),y
	lda #2                 ; red apple
	sta (colPtr),y
	iny
	lda tmp
	clc
	adc #48                ; digit screen code
	sta (scrPtr),y
	lda #1                 ; white digit
	sta (colPtr),y
	pla
	tax
	inx
	cpx #N_APPLES
	bne raDraw
	rts

; ============================================================
; text
; ============================================================
; A/Y = text lo/hi -> draw at row 0 col 0
drawStatus
	sta txtPtr
	sty txtPtr+1
	lda #<SCREEN
	sta scrPtr
	sta colPtr
	lda #>SCREEN
	sta scrPtr+1
	clc
	adc #$d4
	sta colPtr+1
	jmp drawText

; A/Y = text lo/hi -> draw centred-ish on row 12
drawMsg
	sta txtPtr
	sty txtPtr+1
	ldx #12
	jsr setRowPtrs
	lda scrPtr
	clc
	adc #5
	sta scrPtr
	lda colPtr
	clc
	adc #5
	sta colPtr
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

; refresh the NEXT and GOT digits on status line A
drawStatusDigits
	lda gateOpen
	bne dsdDone
	lda nextNum
	clc
	adc #48
	sta SCREEN+13
	lda gotCount
	clc
	adc #48
	sta SCREEN+20
dsdDone
	rts

; ============================================================
; data
; ============================================================
; screen row base addresses ($0400 + 40*row)
rowLo
	dc.b <(SCREEN+0),<(SCREEN+40),<(SCREEN+80),<(SCREEN+120),<(SCREEN+160)
	dc.b <(SCREEN+200),<(SCREEN+240),<(SCREEN+280),<(SCREEN+320),<(SCREEN+360)
	dc.b <(SCREEN+400),<(SCREEN+440),<(SCREEN+480),<(SCREEN+520),<(SCREEN+560)
	dc.b <(SCREEN+600),<(SCREEN+640),<(SCREEN+680),<(SCREEN+720),<(SCREEN+760)
	dc.b <(SCREEN+800),<(SCREEN+840),<(SCREEN+880),<(SCREEN+920),<(SCREEN+960)
rowHi
	dc.b >(SCREEN+0),>(SCREEN+40),>(SCREEN+80),>(SCREEN+120),>(SCREEN+160)
	dc.b >(SCREEN+200),>(SCREEN+240),>(SCREEN+280),>(SCREEN+320),>(SCREEN+360)
	dc.b >(SCREEN+400),>(SCREEN+440),>(SCREEN+480),>(SCREEN+520),>(SCREEN+560)
	dc.b >(SCREEN+600),>(SCREEN+640),>(SCREEN+680),>(SCREEN+720),>(SCREEN+760)
	dc.b >(SCREEN+800),>(SCREEN+840),>(SCREEN+880),>(SCREEN+920),>(SCREEN+960)

; small trees (col,row of canopy-left; trunk sits one row below)
N_TREES equ 6
treeCol	dc.b 6,14,30,33,11,25
treeRow	dc.b 6,15,6,17,10,20

N_ROCKS equ 5
rockCol	dc.b 4,28,17,35,9
rockRow	dc.b 9,13,22,4,17

; pond (per drawn row: screen row, start col, length)
pondRow	dc.b 20,21,22,23
pondCol	dc.b 3,2,2,3
pondLen	dc.b 6,8,8,6

; apples: fixed spots, shuffled numbers
appleCol	dc.b 7,34,12,27,18
appleRow	dc.b 3,8,19,17,5
appleNum	dc.b 3,1,5,2,4
; working copies (apples get eaten)
appleColW	dc.b 0,0,0,0,0
appleRowW	dc.b 0,0,0,0,0
appleNumW	dc.b 0,0,0,0,0

statusA	dc.b "MEADOW  NEXT:1  GOT:0/5  FIRE=WHISTLE",0
statusB	dc.b "MEADOW  GATE OPEN! RUN RIGHT  GOT:5/5",0
msgCaught	dc.b "THE WOLF GOT YOU!  PRESS FIRE",0
msgWin	dc.b "YOU ESCAPED THE MEADOW! PRESS FIRE",0

; sfx tables: (frames,freqHi) pairs, 0 = end
sfxWhistle	dc.b 5,$68,6,$8c,0
sfxBuzz	dc.b 10,$06,0
sfxCaught	dc.b 8,$30,8,$24,8,$1a,12,$10,0
sfxWin	dc.b 7,$40,7,$50,7,$60,14,$80,0

; wolf sprite pointer bases, indexed by wolfFace (0=left 1=right)
wolfBaseA	dc.b SPRBASE+2,SPRBASE+4   ; screen-left half
wolfBaseB	dc.b SPRBASE+3,SPRBASE+5   ; screen-right half

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
