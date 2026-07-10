; ============================================================
;  PETER AND THE WOLF — Commander X16
;  65C02 + VERA + YM2151, ca65 syntax
;
;  A port of the browser game: six chapters + Endless Dusk,
;  hardware-scrolled tile worlds, the full cast as sprites,
;  Prokofiev leitmotifs on the FM chip, PSG sound effects.
;
;  Build: build.ps1  (gen_assets/gen_music -> cl65 -> PETER.PRG)
; ============================================================

.pc02

; attract mode starts at this chapter (0-based; testing hook)
.ifndef ATTRACT_CHAPTER
ATTRACT_CHAPTER = 0
.endif

.import __BSS_RUN__, __BSS_SIZE__

.include "x16.inc"

; ---------------- zero page ----------------
.zeropage
frame:      .res 1               ; advances once per frame
lastJiffy:  .res 1
syncFlag:   .res 1
tmp:        .res 1
tmp2:       .res 1
tmp3:       .res 1
tmpLo:      .res 1
tmpHi:      .res 1
txtPtr:     .res 2
srcP:       .res 2
dstP:       .res 2
mapP:       .res 2
oldIrq:     .res 2
rngLo:      .res 1
rngHi:      .res 1
; input
joyB:       .res 1               ; byte0: B Y SEL STA U D L R (active low)
joyX:       .res 1               ; byte1: A X L R ....
joyBPrev:   .res 1
joyXPrev:   .res 1
joyBEdge:   .res 1               ; 1-bits: newly pressed this frame
joyXEdge:   .res 1
keyChar:    .res 1               ; GETIN this frame (0 = none)
; camera
camX:       .res 2
camY:       .res 2
; distance scratch
dxL:        .res 1
dxH:        .res 1
dyL:        .res 1
dyH:        .res 1
distL:      .res 1
distH:      .res 1
sgnX:       .res 1               ; $01 target right of source, $FF left
sgnY:       .res 1
; sprite compose scratch
spIdx:      .res 1
spFrame:    .res 1
spXL:       .res 1
spXH:       .res 1
spYL:       .res 1
spYH:       .res 1
spFlags:    .res 1               ; z bits + flips (byte 6)
; world scratch
cellX:      .res 1
cellY:      .res 1
sampX:      .res 2               ; solidAtPx sample point (px)
sampY:      .res 2
candL:      .res 1               ; axis stepper candidate position
candH:      .res 1
tgXL:       .res 1               ; moveToward target
tgXH:       .res 1
tgYL:       .res 1
tgYH:       .res 1
spdF:       .res 1               ; speed 8.8
spdI:       .res 1
mulA:       .res 2               ; 16-bit multiplicand
mulA2:      .res 1               ; multiplicand bits 16-23 during the shift
mulR:       .res 3               ; 24-bit result
textCol:    .res 1
; actor loop index
ai:         .res 1
curSys:     .res 1               ; DIAG: which subsystem is running
gameState:  .res 1

; game state ids
GS_TITLE    = 0
GS_STORY    = 1                  ; chapter card
GS_PLAY     = 2
GS_WIN      = 3                  ; tally card
GS_LOSE     = 4
GS_CAPTURE  = 5                  ; snare cutscene
GS_PARADE   = 6
GS_CURTAIN  = 7

; DIAG marker: writes a char at HUD (38,0) — freeze forensics
.macro MARK ch
	pha
	stz VERA_CTRL
	lda #<((0*64+38)*2)
	sta VERA_ADDR_L
	lda #(>VRAM_HUDMAP)
	sta VERA_ADDR_M
	lda #VINC_1
	sta VERA_ADDR_H
	lda #(ch & $3F)
	sta VERA_DATA0
	lda #$01
	sta VERA_DATA0
	pla
.endmacro

; DIAG assertion: freeze + dump if Peter leaves the world
.macro APOS ch
	lda axH
	cmp #5
	bcs :+
	lda ayH
	cmp #5
	bcc :++
:	lda #(ch & $3F)
	jsr apossFire
:
.endmacro

; DIAG watchdog: fire if Peter moved more than ~8px since last check
.macro ADELTA ch
	lda #(ch & $3F)
	jsr adeltaCheck
.endmacro

.code
	jmp start

.include "engine.asm"
.include "world.asm"
.include "actors.asm"
.include "actors2.asm"
.include "draw.asm"
.include "hud.asm"
.include "music.asm"
.include "cutscene.asm"

; ============================================================
;  boot
; ============================================================
.code
start:
	sei
	; zero all of BSS — nothing below assumes garbage
	lda #<__BSS_RUN__
	sta dstP
	lda #>__BSS_RUN__
	sta dstP+1
	ldx #>__BSS_SIZE__
	inx                          ; round up to whole pages (padding is fine:
	ldy #0                       ; BSS is the last segment below __HIMEM__)
	tya
@bssClr:
	sta (dstP),y
	iny
	bne @bssClr
	inc dstP+1
	dex
	bne @bssClr
	jsr showSplash               ; painted poster; waits for a keypress
	jsr videoInit
	jsr uploadAssets
	jsr clearSprShadow
	jsr musicInit

	; BRK trap: dump the stack instead of the ROM monitor
	lda #<brkTrap
	sta $0316                    ; CBINV
	lda #>brkTrap
	sta $0317
	cli                          ; KERNAL keeps its own VSYNC IRQ (jiffies)

	lda #$C3                     ; season the RNG
	sta rngLo
	lda #$5A
	sta rngHi

	jsr enterTitle

; ============================================================
;  main loop — one tick per frame (jiffy-clock polled)
; ============================================================
mainLoop:
	jsr RDTIM                    ; jiffy clock: A = low byte (60 Hz)
	cmp lastJiffy
	beq mainLoop
	sta lastJiffy
	inc frame

	jsr musicTick                ; audio first: steady beat
	jsr sfxTick
	jsr applyCamera
	jsr flushSprites
	jsr readInput

	lda gameState
	asl
	tax
	jmp (stateJmp,x)

stateJmp:
	.addr tickTitle
	.addr tickStory
	.addr tickPlay
	.addr tickWin
	.addr tickLose
	.addr tickCapture
	.addr tickParade
	.addr tickCurtain

stateDone:                       ; every tick handler jumps back here
	jmp mainLoop

; adeltaCheck: A = marker; fire when |ax-prevAx| or |ay-prevAy| > 8
adeltaCheck:
	sta tmp3
	; dx
	sec
	lda axL
	sbc prevAxL
	sta tmpLo
	lda axH
	sbc prevAxH
	sta tmpHi
	jsr abs16
	lda tmpHi
	bne @fire
	lda tmpLo
	cmp #9
	bcs @fire
	; dy
	sec
	lda ayL
	sbc prevAyL
	sta tmpLo
	lda ayH
	sbc prevAyH
	sta tmpHi
	jsr abs16
	lda tmpHi
	bne @fire
	lda tmpLo
	cmp #9
	bcs @fire
	; fine: refresh the snapshot
	lda axL
	sta prevAxL
	lda axH
	sta prevAxH
	lda ayL
	sta prevAyL
	lda ayH
	sta prevAyH
	rts
@fire:
	lda tmp3
	jmp apossFire

.bss
prevAxL: .res 1
prevAxH: .res 1
prevAyL: .res 1
prevAyH: .res 1
.code

; adeltaSync: refresh the snapshot (legitimate jumps: spawns)
adeltaSync:
	lda axL
	sta prevAxL
	lda axH
	sta prevAxH
	lda ayL
	sta prevAyL
	lda ayH
	sta prevAyH
	rts

; apossFire: A = marker screen code; dump position, freeze forever
apossFire:
	pha
	VSET (VRAM_HUDMAP + (4*64+2)*2), VINC_1
	lda #$01
	sta textCol
	pla
	sta VERA_DATA0
	lda #$01
	sta VERA_DATA0
	lda axH
	jsr hexOut
	lda axL
	jsr hexOut
	lda #' '
	jsr charOut
	lda ayH
	jsr hexOut
	lda ayL
	jsr hexOut
	lda #' '
	jsr charOut
	lda prevAxH
	jsr hexOut
	lda prevAxL
	jsr hexOut
	lda #' '
	jsr charOut
	lda prevAyH
	jsr hexOut
	lda prevAyL
	jsr hexOut
	lda #' '
	jsr charOut
	lda curSys                   ; which subsystem
	jsr hexOut
	lda astate+1                 ; wolf state
	jsr hexOut
	lda axH+1                    ; wolf position
	jsr hexOut
	lda axL+1
	jsr hexOut
	lda ayH+1
	jsr hexOut
	lda ayL+1
	jsr hexOut
@halt:
	bra @halt

; ------------------------------------------------------------
; brkTrap: something executed a BRK — show the stack trail
; ------------------------------------------------------------
brkTrap:
	sei
	lda #%00100001               ; L1 only
	sta VERA_DC_VIDEO
	stz VERA_L1_HSCROLL_L
	stz VERA_L1_HSCROLL_H
	jsr clearHud
	lda #$01
	sta textCol
	; SP snapshot
	tsx
	phx
	VSET (VRAM_HUDMAP + (6*64+2)*2), VINC_1
	pla
	jsr hexOut
	; dump $01C8..$01FF as 7 rows of 8 bytes
	ldy #8                       ; screen row
	lda #$C8                     ; stack offset
	sta tmp2
@row:
	phy
	stz VERA_CTRL
	tya
	lsr
	ora #>VRAM_HUDMAP
	sta VERA_ADDR_M
	lda #0
	ror
	ora #(2*2)
	sta VERA_ADDR_L
	lda #VINC_1
	sta VERA_ADDR_H
	ldx #8
@byte:
	ldy tmp2
	lda $0100,y
	jsr hexOut
	lda #' '
	jsr charOut
	inc tmp2
	dex
	bne @byte
	ply
	iny
	iny
	cpy #22
	bne @row
@stop:
	bra @stop

; ------------------------------------------------------------
; showSplash: display the painted poster the AUTOBOOT.X16 stub
; already loaded into VRAM $00000 (BASIC: LOAD"SPLASH.BIN",8,2 —
; the KERNAL's VRAM load, which works on SD cards and the
; emulator's Host FS alike; the KERNAL calls fail from ML on
; Host FS, so the stub does the loading and we do the showing).
; The stub marks golden RAM $0400/$0401 with "PW"; no marker
; (PRG launched directly) -> skip straight to the game.
; Holds ~5 s, any key skips; then wipes the map VRAM so the
; tile world comes up clean.
; ------------------------------------------------------------
showSplash:
	lda $0400                    ; marker from the autoboot stub?  ($50 $57 =
	cmp #$50                     ; "PW"; ca65's cx16 charmap turns 'P' into
	bne @toSkip                  ; shifted PETSCII $D0, so compare raw hex)
	lda $0401
	cmp #$57
	beq @present
@toSkip:
	jmp @skip
@present:
	stz $0400                    ; consume it: never show a stale poster
	stz $0401

	stz VERA_CTRL
	stz VERA_DC_VIDEO            ; blank during the mode switch
	lda #64
	sta VERA_DC_HSCALE
	sta VERA_DC_VSCALE

	; poster palette -> $1FA00 (256 entries, 512 bytes)
	VSET VRAM_PALETTE, VINC_1
	lda #<splashPal
	sta srcP
	lda #>splashPal
	sta srcP+1
	ldx #<512
	ldy #>512
	jsr copyToVram

	; layer0 -> 8bpp bitmap, base $00000, 320 wide
	lda #%00000111
	sta VERA_L0_CONFIG
	stz VERA_L0_TILEBASE
	stz VERA_L0_HSCROLL_L
	stz VERA_L0_HSCROLL_H
	lda #%00010001               ; VGA + layer0 only
	sta VERA_DC_VIDEO

	; hold ~4 s (250 jiffies); any key or gamepad button skips.  The BASIC
	; chain-load leaves the input channel pointing at the dead file channel
	; (which wedges GETIN into returning the same byte forever), so restore
	; the default channels first.
	cli
	jsr CLRCHN
@drain:
	jsr GETIN                    ; flush leftover boot keystrokes
	bne @drain
	jsr RDTIM
	sta tmp                      ; last jiffy seen
	stz tmp2                     ; ticks elapsed
@wait:
	jsr GETIN                    ; fresh keypress skips
	bne @done
	php
	sei                          ; atomic vs the KERNAL's IRQ scan
	lda #0
	jsr JOYSTICK_GET
	plp
	sta tmpLo                    ; byte0, active low
	stx tmpHi                    ; byte1
	lda tmpLo
	and tmpHi
	eor #$FF                     ; pressed bits
	beq @tick
	tay                          ; single button only: unscanned state
	sec                          ; reads as "everything pressed" noise
	sbc #1
	sta tmp3
	tya
	and tmp3
	beq @done                    ; one clean button -> skip
@tick:
	jsr RDTIM
	cmp tmp
	beq @wait                    ; still the same jiffy
	sta tmp
	inc tmp2
	lda tmp2
	cmp #250
	bne @wait
@done:
	sei
	stz VERA_DC_VIDEO            ; blank, then wipe $00000-$07FFF (32 KB)
	VSET VRAM_MAP, VINC_1
	ldx #0
	ldy #0
@wipe:
	stz VERA_DATA0
	iny
	bne @wipe
	inx
	cpx #128
	bne @wipe
@skip:
	rts

.include "build/assets.inc"
.include "build/music.inc"
.include "build/splash.inc"
