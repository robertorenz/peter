; ============================================================
;  hud.asm — score, HUD, minimap, messages, game screens
; ============================================================

.bss
score:     .res 3                ; BCD, little-endian (6 digits)
bestScore: .res 3
stars:     .res 1
flashT:    .res 1                ; message clear timer
chapSel:   .res 1                ; title chapter select 0..6
msgDelay:  .res 1                ; input lockout on cards
endlessSec:.res 1

.code
; ------------------------------------------------------------
; scoring
; ------------------------------------------------------------
scoreReset:
	stz score
	stz score+1
	stz score+2
	rts

; scoreAddBCD: A = BCD low pair, X = BCD mid pair
scoreAddBCD:
	sed
	clc
	adc score
	sta score
	txa
	adc score+1
	sta score+1
	lda score+2
	adc #0
	sta score+2
	cld
	rts

score50:
	lda #$50
	ldx #$00
	bra scoreAddBCD
score500:
	lda #$00
	ldx #$05
	bra scoreAddBCD
score150:
	lda #$50
	ldx #$01
	bra scoreAddBCD
score5:
	lda #$05
	ldx #$00
	bra scoreAddBCD

; scoreAddBonus: add binary bonusL/H as BCD (1 per loop)
scoreAddBonus:
	lda bonusL
	ora bonusH
	beq @done
	sed
@loop:
	clc
	lda score
	adc #1
	sta score
	lda score+1
	adc #0
	sta score+1
	lda score+2
	adc #0
	sta score+2
	; dec bonus
	lda bonusL
	bne :+
	dec bonusH
:	dec bonusL
	lda bonusL
	ora bonusH
	bne @loop
	cld
@done:
	rts

; bestCheck: best = max(best, score)
bestCheck:
	lda score+2
	cmp bestScore+2
	bcc @no
	bne @yes
	lda score+1
	cmp bestScore+1
	bcc @no
	bne @yes
	lda score
	cmp bestScore
	bcc @no
@yes:
	lda score
	sta bestScore
	lda score+1
	sta bestScore+1
	lda score+2
	sta bestScore+2
@no:
	rts

; printScoreAt: 6 BCD digits at col X, row Y
printScoreAt:
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
	lda #$01
	sta textCol
	lda score+2
	jsr hexOut
	lda score+1
	jsr hexOut
	lda score
	jmp hexOut

; ------------------------------------------------------------
; flash messages (row 3, centered-ish)
; ------------------------------------------------------------
MSG_HUNTERS   = 0
MSG_GATEOPEN  = 1
MSG_SNARESET  = 2
MSG_ROPEFOUND = 3
MSG_NOROPE    = 4
MSG_WHISTLE   = 5

.rodata
msg0: .byte 12,3, "THE HUNTERS PASS BY!",0
msg1: .byte 10,3, "THE GATE SWINGS OPEN!",0
msg2: .byte 9,3, "THE SNARE IS SET. LURE HIM!",0
msg3: .byte 8,3, "THE ROPE! CARRY IT TO THE OAK",0
msg4: .byte 12,3, "NOTHING UNDER THIS ROCK",0
msg5: .byte 15,3, "TWEEET!",0
msgPtrLo: .byte <msg0,<msg1,<msg2,<msg3,<msg4,<msg5
msgPtrHi: .byte >msg0,>msg1,>msg2,>msg3,>msg4,>msg5
.code

flashMsg:
	pha
	lda #$01                     ; white on transparent
	sta textCol
	ldy #3
	jsr clearHudRow
	pla
	jsr printMsg
	lda #100
	sta flashT
	rts

flashTick:
	lda flashT
	beq @done
	dec flashT
	bne @done
	ldy #3
	jsr clearHudRow
@done:
	rts

printPaused:
	lda #$01
	sta textCol
	ldx #17
	ldy #14
	lda #<txtPaused
	sta txtPtr
	lda #>txtPaused
	sta txtPtr+1
	jmp printAt

; ------------------------------------------------------------
; hudInit: static furniture for the play screen
; ------------------------------------------------------------
hudInit:
	jsr clearHud
	lda #$01
	sta textCol
	; level name top-left
	ldx level
	lda lvNameLo,x
	sta txtPtr
	lda lvNameHi,x
	sta txtPtr+1
	ldx #1
	ldy #0
	jsr printAt
	; season tag
	lda tier
	beq @noTier
	cmp #1
	bne @winter
	lda #<txtWild
	sta txtPtr
	lda #>txtWild
	sta txtPtr+1
	bra @tierP
@winter:
	lda #<txtProk
	sta txtPtr
	lda #>txtProk
	sta txtPtr+1
@tierP:
	ldx #17
	ldy #0
	jsr printAt
@noTier:
	; SCORE label
	lda #<txtScore
	sta txtPtr
	lda #>txtScore
	sta txtPtr+1
	ldx #26
	ldy #0
	jsr printAt
	; minimap backing: 6x3 dark cells bottom-right (rows 26..28, cols 33..38)
	ldy #26
@mrow:
	stz VERA_CTRL
	tya
	lsr
	ora #>VRAM_HUDMAP
	sta VERA_ADDR_M
	lda #0
	ror
	ora #(33*2)
	sta VERA_ADDR_L
	lda #VINC_1
	sta VERA_ADDR_H
	ldx #6
:	lda #$20                     ; space
	sta VERA_DATA0
	lda #$B0                     ; bg dark gray
	sta VERA_DATA0
	dex
	bne :-
	iny
	cpy #29
	bne @mrow
	rts

; ------------------------------------------------------------
; hudTick: dynamic HUD bits
; ------------------------------------------------------------
hudTick:
	jsr flashTick
	; score digits
	ldx #32
	ldy #0
	jsr printScoreAt
	; hearts as sprites
	ldx #0
@hearts:
	txa
	clc
	adc #SPI_HEARTS
	sta spIdx
	txa
	asl
	asl
	asl
	clc
	adc #10
	sta spXL
	stz spXH
	lda #12
	sta spYL
	stz spYH
	cpx hearts
	bcc @full
	lda #FR_HEARTEMPTY
	bra @hset
@full:
	lda #FR_HEART
@hset:
	sta spFrame
	lda #%00001100               ; above HUD
	sta spFlags
	jsr sprPut
	inx
	cpx #3
	bne @hearts
	; objective line (row 1): depends on level type
	ldx level
	lda lvType,x
	cmp #LT_APPLES
	bne @ammoHud
	; "APPLES n/N Nx"
	lda #$01
	sta textCol
	lda #<txtApples
	sta txtPtr
	lda #>txtApples
	sta txtPtr+1
	ldx #1
	ldy #1
	jsr printAt
	VSET (VRAM_HUDMAP + (1*64+8)*2), VINC_1
	lda applesGot
	jsr digitOut
	lda #'/'
	jsr charOut
	lda applesAll
	jsr digitOut
	lda #' '
	jsr charOut
	lda #'N'
	jsr charOut
	lda nextApple
	cmp applesAll
	beq :+
	bcs @noNext
:	jsr digitOut
	bra @suspBar
@noNext:
	lda #'-'
	jsr charOut
	bra @suspBar
@ammoHud:
	lda #$01
	sta textCol
	lda #<txtAmmo
	sta txtPtr
	lda #>txtAmmo
	sta txtPtr+1
	ldx #1
	ldy #1
	jsr printAt
	VSET (VRAM_HUDMAP + (1*64+8)*2), VINC_1
	lda ammo
	jsr digitOut
@suspBar:
	; suspicion/danger bar: 8 cells at (30..37, row 1)
	lda wsuspI+SL_FOE1
	lsr
	lsr
	lsr
	lsr                          ; 0..6
	sta tmp                      ; filled cells (0..6)
	; hunting? force full
	lda astate+SL_FOE1
	cmp #WS_HUNT
	bne :+
	lda #8
	sta tmp
:	cmp #WS_POUNCE
	bne :+
	lda #8
	sta tmp
:	VSET (VRAM_HUDMAP + (1*64+30)*2), VINC_1
	ldx #0
@bar:
	cpx tmp
	bcs @empty
	lda #$20                     ; space
	sta VERA_DATA0
	lda #$20                     ; bg red
	sta VERA_DATA0
	bra @barN
@empty:
	lda #$20
	sta VERA_DATA0
	lda #$B0                     ; bg dark gray
	sta VERA_DATA0
@barN:
	inx
	cpx #8
	bne @bar
	; endless: score ticks with survival
	ldx level
	lda lvType,x
	cmp #LT_ENDLESS
	bne @done
	inc endlessSec
	lda endlessSec
	cmp #60
	bcc @done
	stz endlessSec
	jsr score5
@done:
	rts

; digitOut: A (0..9) as one char+color cell via DATA0 (VINC_1)
digitOut:
	cmp #10
	bcc :+
	lda #9
:	clc
	adc #'0'
; charOut: A = ASCII char, emits char + white color
charOut:
	and #$3F
	sta VERA_DATA0
	lda #$01
	sta VERA_DATA0
	rts

; ------------------------------------------------------------
; minimapTick: dots over the backing box (33..38 x 26..28 chars)
; box origin px: (264, 208), 48x24 px
; narrow world: x>>5 wait 1024/48... use x>>5 (0..31) + 8 -> 264+8..
; keep simple: x/32 (0..31), y/32 (0..15) onto 32x16 px at (272,210)
; wide world: x/64, y/16
; ------------------------------------------------------------
minimapTick:
	; Peter dot
	lda #SPI_MINI
	sta spIdx
	ldx #SL_PETER
	lda #FR_DOTGOLD
	jsr miniDot
	; foes
	lda #SPI_MINI+1
	sta spIdx
	ldx #SL_FOE1
	lda #FR_DOTRED
	jsr miniDotIf
	lda #SPI_MINI+2
	sta spIdx
	ldx #SL_FOE2
	lda #FR_DOTRED
	jsr miniDotIf
	lda #SPI_MINI+3
	sta spIdx
	ldx #SL_FOE3
	lda #FR_DOTRED
	jsr miniDotIf
	; friend
	lda #SPI_MINI+4
	sta spIdx
	ldx #SL_FRIEND
	lda #FR_DOTWHITE
	jsr miniDotIf
	; goal
	lda #SPI_MINI+5
	sta spIdx
	jsr miniGoal
	rts

miniDotIf:
	pha
	lda atype,x
	bne @ok
	pla
	jmp sprHide
@ok:
	pla
	; fall through
; miniDot: A = dot frame, X = slot
miniDot:
	sta spFrame
	; sx = 272 + ax>>5 (narrow) / ax>>6 (wide)
	lda axH,x
	sta tmpHi
	lda axL,x
	sta tmpLo
	ldy mapWide
	beq :+
	lsr tmpHi
	ror tmpLo
:	ldy #5
:	lsr tmpHi
	ror tmpLo
	dey
	bne :-
	clc
	lda tmpLo
	adc #<272
	sta spXL
	lda #>272
	adc #0
	sta spXH
	; sy = 210 + ay>>5 (narrow) / ay>>4 (wide)
	lda ayH,x
	sta tmpHi
	lda ayL,x
	sta tmpLo
	ldy mapWide
	beq @nY
	ldy #4
	bra @shY
@nY:
	ldy #5
@shY:
:	lsr tmpHi
	ror tmpLo
	dey
	bne :-
	clc
	lda tmpLo
	adc #210
	sta spYL
	stz spYH
	lda #%00001100
	sta spFlags
	jmp sprPut

miniGoal:
	; goal position by level type -> tgX/tgY, then fake a dot
	ldx level
	lda lvType,x
	cmp #LT_BIRD
	beq @oak
	cmp #LT_ROPE
	beq @oak
	cmp #LT_CHASE
	beq @oak
	cmp #LT_DUCK
	beq @pond
	cmp #LT_ENDLESS
	beq @none
	; gate
	lda #<1008
	sta tgXL
	lda #>1008
	sta tgXH
	lda gateRow
	asl
	asl
	asl
	clc
	adc #16
	sta tgYL
	stz tgYH
	bra @dot
@oak:
	lda oakXL
	sta tgXL
	lda oakXH
	sta tgXH
	lda oakYL
	sta tgYL
	stz tgYH
	bra @dot
@pond:
	lda pondXL
	sta tgXL
	lda pondXH
	sta tgXH
	lda pondYL
	sta tgYL
	stz tgYH
	bra @dot
@none:
	jmp sprHide
@dot:
	; reuse miniDot math on a scratch "actor": temporarily via tg
	lda tgXH
	sta tmpHi
	lda tgXL
	sta tmpLo
	ldy mapWide
	beq :+
	lsr tmpHi
	ror tmpLo
:	ldy #5
:	lsr tmpHi
	ror tmpLo
	dey
	bne :-
	clc
	lda tmpLo
	adc #<272
	sta spXL
	lda #>272
	adc #0
	sta spXH
	lda tgYH
	sta tmpHi
	lda tgYL
	sta tmpLo
	ldy mapWide
	beq @nY
	ldy #4
	bra @shY
@nY:
	ldy #5
@shY:
:	lsr tmpHi
	ror tmpLo
	dey
	bne :-
	clc
	lda tmpLo
	adc #210
	sta spYL
	stz spYH
	lda #FR_DOTGREEN
	sta spFrame
	lda #%00001100
	sta spFlags
	jmp sprPut

; ------------------------------------------------------------
; screens
; ------------------------------------------------------------
.rodata
txtTitle1: .byte "PETER AND THE WOLF",0
txtTitle2: .byte "A STORYBOOK FOR THE COMMANDER X16",0
txtTitle3: .byte "Z OR SPACE - BEGIN THE TALE",0
txtTitle4: .byte "LEFT/RIGHT - CHOOSE A CHAPTER",0
txtTitle5: .byte "ARROWS MOVE - SHIFT TIPTOE - X WHISTLE",0
txtTitle6: .byte "Z THROW/ACT - S DROP ROPE - P PAUSE",0
txtBest:   .byte "BEST",0
txtScore:  .byte "SCORE",0
txtApples: .byte "APPLES",0
txtAmmo:   .byte "APPLES",0
txtWild:   .byte "- WILD",0
txtProk:   .byte "- PROKOFIEV",0
txtPaused: .byte "PAUSED",0
txtStars:  .byte "STARS",0
txtWinGo:  .byte "Z OR SPACE - ONWARD",0
txtLose1:  .byte "THE WOLF WAS TOO CLEVER...",0
txtLose2:  .byte "Z OR SPACE - TRY AGAIN",0

lvName0: .byte "1 THE MEADOW",0
lvName1: .byte "2 SAVE THE BIRD",0
lvName2: .byte "3 RESCUE THE DUCK",0
lvName3: .byte "4 TRAP THE WOLF",0
lvName4: .byte "5 GRANDFATHERS GATE",0
lvName5: .byte "6 THE GREAT CHASE",0
lvName6: .byte "ENDLESS DUSK",0
lvNameLo: .byte <lvName0,<lvName1,<lvName2,<lvName3,<lvName4,<lvName5,<lvName6
lvNameHi: .byte >lvName0,>lvName1,>lvName2,>lvName3,>lvName4,>lvName5,>lvName6

tale0a: .byte "EARLY ONE MORNING PETER OPENED",0
tale0b: .byte "THE GATE INTO THE BIG GREEN MEADOW.",0
tale0c: .byte "GATHER THE APPLES IN ORDER - THEN SLIP",0
tale0d: .byte "OUT THE GATE, OR SNARE THE WOLF AT THE OAK.",0
tale1a: .byte "A LITTLE BIRD ARGUED WITH THE DUCK.",0
tale1b: .byte "THE CAT CREPT CLOSER THROUGH THE GRASS...",0
tale1c: .byte "LEAD THE BIRD TO THE TALL OAK",0
tale1d: .byte "BEFORE THE CAT CATCHES IT.",0
tale2a: .byte "THE DUCK WANDERED FROM THE POND -",0
tale2b: .byte "AND THE WOLF CAME OUT OF THE FOREST.",0
tale2c: .byte "LEAD THE DUCK HOME TO THE WATER",0
tale2d: .byte "BEFORE THE WOLF REACHES IT.",0
tale3a: .byte "JUST THEN GRANDFATHER'S ROPE WENT MISSING.",0
tale3b: .byte "SEARCH THE ROCKS TO FIND IT, CARRY IT",0
tale3c: .byte "TO THE GREAT OAK, SET THE SNARE -",0
tale3d: .byte "AND LURE THE WOLF UNDERNEATH.",0
tale4a: .byte "NIGHT FELL DARK AND DEEP.",0
tale4b: .byte "THE FIREFLIES LIGHT ONLY A LITTLE CIRCLE.",0
tale4c: .byte "WALK OLD GRANDFATHER SAFELY HOME -",0
tale4d: .byte "THE WOLF HUNTS WHOEVER IT CAN SEE.",0
tale5a: .byte "THE WOLF BROKE FREE FOR ONE LAST HUNT!",0
tale5b: .byte "RUN EAST THROUGH DAY AND DUSK AND DARK",0
tale5c: .byte "AND LEAD HIM INTO THE WAITING SNARE",0
tale5d: .byte "AT THE FAR OAK. DO NOT STOP RUNNING!",0
tale6a: .byte "THE MEADOW AT DUSK, WOLVES ALL AROUND.",0
tale6b: .byte "THERE IS NO GATE AND NO SNARE -",0
tale6c: .byte "ONLY YOUR APPLES, YOUR WITS,",0
tale6d: .byte "AND THE LONG BLUE EVENING. SURVIVE.",0
taleLo: .byte <tale0a,<tale1a,<tale2a,<tale3a,<tale4a,<tale5a,<tale6a
taleHi: .byte >tale0a,>tale1a,>tale2a,>tale3a,>tale4a,>tale5a,>tale6a
taleLo2: .byte <tale0b,<tale1b,<tale2b,<tale3b,<tale4b,<tale5b,<tale6b
taleHi2: .byte >tale0b,>tale1b,>tale2b,>tale3b,>tale4b,>tale5b,>tale6b
taleLo3: .byte <tale0c,<tale1c,<tale2c,<tale3c,<tale4c,<tale5c,<tale6c
taleHi3: .byte >tale0c,>tale1c,>tale2c,>tale3c,>tale4c,>tale5c,>tale6c
taleLo4: .byte <tale0d,<tale1d,<tale2d,<tale3d,<tale4d,<tale5d,<tale6d
taleHi4: .byte >tale0d,>tale1d,>tale2d,>tale3d,>tale4d,>tale5d,>tale6d
.code

; hide all managed sprites (screen changes)
hideAllSprites:
	ldx #0
@s:
	stx spIdx
	jsr sprHide
	inx
	cpx #NSPR
	bne @s
	rts

enterTitle:
	stz chapSel
	jsr scoreReset
	jsr hideAllSprites
	jsr musicStop
	; decorative backdrop: the meadow, day palette
	lda #$10
	sta terrBank
	stz level
	stz tier
	jsr buildWorld
	jsr applyMood
	stz camX
	stz camX+1
	stz camY
	stz camY+1
	stz camTX
	stz camTX+1
	stz camTY
	stz camTY+1
	jsr clearHud
	lda #$01
	sta textCol
	ldx #11
	ldy #6
	lda #<txtTitle1
	sta txtPtr
	lda #>txtTitle1
	sta txtPtr+1
	jsr printAt
	ldx #3
	ldy #8
	lda #<txtTitle2
	sta txtPtr
	lda #>txtTitle2
	sta txtPtr+1
	jsr printAt
	ldx #6
	ldy #13
	lda #<txtTitle3
	sta txtPtr
	lda #>txtTitle3
	sta txtPtr+1
	jsr printAt
	ldx #5
	ldy #15
	lda #<txtTitle4
	sta txtPtr
	lda #>txtTitle4
	sta txtPtr+1
	jsr printAt
	ldx #1
	ldy #24
	lda #<txtTitle5
	sta txtPtr
	lda #>txtTitle5
	sta txtPtr+1
	jsr printAt
	ldx #2
	ldy #26
	lda #<txtTitle6
	sta txtPtr
	lda #>txtTitle6
	sta txtPtr+1
	jsr printAt

	jsr titleChapter
	lda #30
	sta msgDelay
	stz attract
	stz idleT
	stz idleT+1
	stz killCnt
	stz killVal
	stz humanT
	stz humanPrev
	lda #GS_TITLE
	sta gameState
	rts

titleChapter:
	ldy #18
	jsr clearHudRow
	lda #$01
	sta textCol
	ldx chapSel
	lda lvNameLo,x
	sta txtPtr
	lda lvNameHi,x
	sta txtPtr+1
	ldx #13
	ldy #18
	jmp printAt

tickTitle:
	lda msgDelay
	beq :+
	dec msgDelay
	jmp stateDone
:	; idle long enough? the tale tells itself
	inc idleT
	bne :+
	inc idleT+1
	lda idleT+1
	cmp #2                       ; ~8.5 s
	bcc :+
	lda #1
	sta attract
	lda #ATTRACT_CHAPTER
	sta chapSel
	bra titleGo
:	lda joyBEdge
	and #JB_LEFT
	beq :+
	lda chapSel
	beq :+
	dec chapSel
	jsr titleChapter
:	lda joyBEdge
	and #JB_RIGHT
	beq :+
	lda chapSel
	cmp #6
	bcs :+
	inc chapSel
	jsr titleChapter
:	; start?
	lda joyBEdge
	and #(JB_B|JB_START)
	bne @go
	lda keyChar
	cmp #' '
	beq @go
	jmp stateDone
@go:
titleGo:
	lda chapSel
	sta level
	inc a
	sta round
	stz tier
	jmp enterStory

enterStory:
	jsr hideAllSprites
	jsr clearHud
	lda #$01
	sta textCol
	; chapter name
	ldx level
	lda lvNameLo,x
	sta txtPtr
	lda lvNameHi,x
	sta txtPtr+1
	ldx #12
	ldy #8
	jsr printAt
	; four tale lines
	ldx level
	lda taleLo,x
	sta txtPtr
	lda taleHi,x
	sta txtPtr+1
	ldx #2
	ldy #12
	jsr printAt
	ldx level
	lda taleLo2,x
	sta txtPtr
	lda taleHi2,x
	sta txtPtr+1
	ldx #2
	ldy #14
	jsr printAt
	ldx level
	lda taleLo3,x
	sta txtPtr
	lda taleHi3,x
	sta txtPtr+1
	ldx #2
	ldy #16
	jsr printAt
	ldx level
	lda taleLo4,x
	sta txtPtr
	lda taleHi4,x
	sta txtPtr+1
	ldx #2
	ldy #18
	jsr printAt
	ldx #10
	ldy #24
	lda #<txtWinGo
	sta txtPtr
	lda #>txtWinGo
	sta txtPtr+1
	jsr printAt
	; the chapter's leitmotif, one-shot
	ldx level
	lda lvSong,x
	jsr musicClip
	lda #40
	sta msgDelay
	lda #GS_STORY
	sta gameState
	jmp stateDone

tickStory:
	lda msgDelay
	beq :+
	dec msgDelay
	jmp stateDone
:	lda joyBEdge
	and #(JB_B|JB_START)
	bne @go
	lda keyChar
	cmp #' '
	beq @go
	jmp stateDone
@go:
	jsr startLevel
	lda #GS_PLAY
	sta gameState
	jmp stateDone

enterWin:
	; tally: +500 clear, + speed bonus, + hearts*150
	jsr score500
	jsr scoreAddBonus
	lda hearts
	beq @noHearts
	sta tmp
:	jsr score150
	dec tmp
	bne :-
@noHearts:
	lda hearts
	bne :+
	lda #1
:	sta stars
	jsr bestCheck
	jsr hideAllSprites
	jsr clearHud
	jsr musicStop
	jsr sfxFanfare
	lda #$01
	sta textCol
	ldx level
	lda lvNameLo,x
	sta txtPtr
	lda lvNameHi,x
	sta txtPtr+1
	ldx #12
	ldy #8
	jsr printAt
	; stars
	ldx #17
	ldy #12
	lda #<txtStars
	sta txtPtr
	lda #>txtStars
	sta txtPtr+1
	jsr printAt
	VSET (VRAM_HUDMAP + (12*64+24)*2), VINC_1
	ldx #0
@st:
	cpx stars
	bcs @dim
	lda #'*'
	jsr charOut
	bra @stN
@dim:
	lda #'.'
	jsr charOut
@stN:
	inx
	cpx #3
	bne @st
	; score line
	lda #<txtScore
	sta txtPtr
	lda #>txtScore
	sta txtPtr+1
	ldx #14
	ldy #14
	jsr printAt
	ldx #20
	ldy #14
	jsr printScoreAt
	ldx #10
	ldy #20
	lda #<txtWinGo
	sta txtPtr
	lda #>txtWinGo
	sta txtPtr+1
	jsr printAt
	lda #40
	sta msgDelay
	lda #GS_WIN
	sta gameState
	jmp stateDone

tickWin:
	lda msgDelay
	beq :+
	dec msgDelay
	jmp stateDone
:	lda joyBEdge
	and #(JB_B|JB_START)
	bne @go
	lda keyChar
	cmp #' '
	beq @go
	jmp stateDone
@go:
	; endless has no "next"
	ldx level
	lda lvType,x
	cmp #LT_ENDLESS
	beq @title
	; chase finale -> curtain call (once)
	cmp #LT_CHASE
	bne @next
	lda curtainShown
	bne @next
	jmp enterCurtain
@next:
	inc round
	lda round
	dec a
	; level = (round-1) mod 6, tier = (round-1)/6 (cap 2)
	sta tmp
	stz tier
:	lda tmp
	cmp #6
	bcc :+
	sec
	sbc #6
	sta tmp
	inc tier
	bra :-
:	lda tier
	cmp #3
	bcc :+
	lda #2
	sta tier
:	lda tmp
	sta level
	jmp enterStory
@title:
	jmp enterTitle

enterLose:
	jsr hideAllSprites
	jsr clearHud
	jsr musicStop
	jsr sfxLose
	lda #$01
	sta textCol
	ldx #7
	ldy #12
	lda #<txtLose1
	sta txtPtr
	lda #>txtLose1
	sta txtPtr+1
	jsr printAt
	ldx #9
	ldy #16
	lda #<txtLose2
	sta txtPtr
	lda #>txtLose2
	sta txtPtr+1
	jsr printAt
	lda #40
	sta msgDelay
	lda #GS_LOSE
	sta gameState
	jmp stateDone

tickLose:
	lda msgDelay
	beq :+
	dec msgDelay
	jmp stateDone
:	lda joyBEdge
	and #(JB_B|JB_START)
	bne @go
	lda keyChar
	cmp #' '
	beq @go
	jmp stateDone
@go:
	jmp enterStory
