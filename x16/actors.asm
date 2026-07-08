; ============================================================
;  actors.asm — Peter, foes (wolf/cat), followers, apples,
;  hunters, scout bird, dove; the per-frame play tick
; ============================================================

; actor slots
SL_PETER  = 0
SL_FOE1   = 1
SL_FOE2   = 2
SL_FOE3   = 3
SL_FRIEND = 4                    ; follower: bird/duck/grandpa
SL_EXTRA  = 5                    ; scout bird (L1) / idle grandpa (L4)
SL_HUNT1  = 6
SL_HUNT2  = 7
NACT      = 8

; actor types
AT_NONE   = 0
AT_PETER  = 1
AT_WOLF   = 2
AT_CAT    = 3
AT_BIRD   = 4
AT_DUCK   = 5
AT_GRANDPA= 6
AT_HUNTER = 7
AT_SCOUT  = 8

; foe states
WS_PATROL  = 0
WS_HUNT    = 1
WS_CROUCH  = 2
WS_POUNCE  = 3
WS_STUN    = 4
WS_SLINK   = 5
WS_DISTRACT= 6
WS_DAZE    = 7

; follower states
FS_IDLE   = 0
FS_FOLLOW = 1
FS_FLEE   = 2

.bss
dbgTry:    .res 1                ; DIAG stepper branch counters
dbgClamp:  .res 1
dbgBlock:  .res 1
dbgPet:    .res 1                ; DIAG: Peter right-step attempts
dbgPetT:   .res 1                ; DIAG: petTick invocations
; actor arrays (indexed by slot)
axF:       .res NACT
axL:       .res NACT
axH:       .res NACT
ayF:       .res NACT
ayL:       .res NACT
ayH:       .res NACT
atype:     .res NACT
astate:    .res NACT
atmr:      .res NACT             ; state timer (counts down)
atmr2:     .res NACT             ; secondary timer
aface:     .res NACT             ; 0=left 1=right
aanim:     .res NACT
atgXL:     .res NACT             ; per-actor waypoint
atgXH:     .res NACT
atgYL:     .res NACT
atgYH:     .res NACT
avxS:      .res NACT             ; pounce velocity, signed 8.8
avxF:      .res NACT
avxI:      .res NACT
avyS:      .res NACT
avyF:      .res NACT
avyI:      .res NACT
wsuspF:    .res NACT             ; wolf suspicion 8.8 (0..100)
wsuspI:    .res NACT
wpcd:      .res NACT             ; pounce cooldown (x2 frames)
; peter globals
petDir:    .res 1                ; 0=down 1=up 2=left 3=right
hearts:    .res 1
invuln:    .res 1
ammo:      .res 1
nextApple: .res 1
applesGot: .res 1
applesAll: .res 1                ; N this level
whistleCd: .res 2
carryRope: .res 1                ; 0 no, 1 carrying, 2 snare set
ropeRock:  .res 1                ; which rock hides the rope
ropeDropXL:.res 1                ; dropped rope position
ropeDropXH:.res 1
ropeDropYL:.res 1
ropeDropped:.res 1
snareArmed:.res 1
tiptoe:    .res 1
petMoving: .res 1
stepNoise: .res 1
; thrown apples (4)
NTHROWN = 4
thXF:      .res NTHROWN
thXL:      .res NTHROWN
thXH:      .res NTHROWN
thYF:      .res NTHROWN
thYL:      .res NTHROWN
thYH:      .res NTHROWN
thVXF:     .res NTHROWN
thVXI:     .res NTHROWN
thVXSg:    .res NTHROWN          ; 0 = right, 1 = left
thVYF:     .res NTHROWN
thVYI:     .res NTHROWN
thVYSg:    .res NTHROWN          ; 0 = down, 1 = up
thLife:    .res NTHROWN          ; 0 = free
thNum:     .res NTHROWN          ; 0 ammo, else numbered
; level frame counters
playFL:    .res 1
playFH:    .res 1
bonusL:    .res 1                ; speed bonus, binary
bonusH:    .res 1
bonus6:    .res 1                ; /6 divider
; endless
wolfSpawnL:.res 1
wolfSpawnH:.res 1
wolfCount: .res 1
; hunters event
huntEvT:   .res 2                ; countdown to crossing
huntOn:    .res 1
; dove
doveOn:    .res 1
doveXL:    .res 1
doveXH:    .res 1
doveYL:    .res 1
; scout bird phase
scoutPh:   .res 1
; win/lose latches
loseFlag:  .res 1
winFlag:   .res 1
captureFlag:.res 1

.code
; ------------------------------------------------------------
; mul16x8: mulA(16) * A(8) -> mulR(24)
; ------------------------------------------------------------
mul16x8:
	stz mulR
	stz mulR+1
	stz mulR+2
	ldy #8
@bit:
	lsr
	bcc @skip
	pha
	clc
	lda mulR+1
	adc mulA
	sta mulR+1
	lda mulR+2
	adc mulA+1
	sta mulR+2
	pla
@skip:
	asl mulA
	rol mulA+1
	dey
	bne @bit
	rts

; ------------------------------------------------------------
; actorDist: dist from slot X to slot Y -> distL/H, sgnX/sgnY,
; abs deltas in dxL/H dyL/H
; ------------------------------------------------------------
actorDist:
	sec
	lda axL,y
	sbc axL,x
	sta tmpLo
	lda axH,y
	sbc axH,x
	sta tmpHi
	jsr abs16
	sta sgnX
	lda tmpLo
	sta dxL
	lda tmpHi
	sta dxH
	sec
	lda ayL,y
	sbc ayL,x
	sta tmpLo
	lda ayH,y
	sbc ayH,x
	sta tmpHi
	jsr abs16
	sta sgnY
	lda tmpLo
	sta dyL
	lda tmpHi
	sta dyH
	jmp distApprox

; distToPoint: slot X to (tgX,tgY)
distToPoint:
	sec
	lda tgXL
	sbc axL,x
	sta tmpLo
	lda tgXH
	sbc axH,x
	sta tmpHi
	jsr abs16
	sta sgnX
	lda tmpLo
	sta dxL
	lda tmpHi
	sta dxH
	sec
	lda tgYL
	sbc ayL,x
	sta tmpLo
	lda tgYH
	sbc ayH,x
	sta tmpHi
	jsr abs16
	sta sgnY
	lda tmpLo
	sta dyL
	lda tmpHi
	sta dyH
	jmp distApprox

; ------------------------------------------------------------
; moveToward: slot X toward (tgX,tgY) at speed spdF/spdI.
; Slides along obstacles.  Sets aface from sgnX.
; ------------------------------------------------------------
moveToward:
	jsr distToPoint
	; arrived?
	lda distH
	bne @go
	lda distL
	cmp #3
	bcs @go
	rts
@go:
	; velocity fractions by slope class (x-major / diagonal / y-major)
	; class: compare dy with dx/2 and dx with dy/2
	lda dxH
	lsr
	sta tmpHi
	lda dxL
	ror
	sta tmpLo                    ; dx/2
	lda dyH
	cmp tmpHi
	bne @c1
	lda dyL
	cmp tmpLo
@c1:
	bcc @xmajor                  ; dy < dx/2
	lda dyH
	lsr
	sta tmpHi
	lda dyL
	ror
	sta tmpLo                    ; dy/2
	lda dxH
	cmp tmpHi
	bne @c2
	lda dxL
	cmp tmpLo
@c2:
	bcc @ymajor                  ; dx < dy/2
	; diagonal: 0.71 both
	lda #181
	sta tmp                      ; fx
	lda #181
	sta tmp2                     ; fy
	bra @vel
@xmajor:
	lda #250
	sta tmp
	lda #90
	sta tmp2
	; if dy tiny, go straight
	lda dyH
	bne @vel
	lda dyL
	cmp #6
	bcs @vel
	lda #0
	sta tmp2
	lda #255
	sta tmp
	bra @vel
@ymajor:
	lda #90
	sta tmp
	lda #250
	sta tmp2
	lda dxH
	bne @vel
	lda dxL
	cmp #6
	bcs @vel
	lda #0
	sta tmp
	lda #255
	sta tmp2
@vel:
	; vx = speed * tmp / 256 (8.8), apply with sign sgnX
	lda spdF
	sta mulA
	lda spdI
	sta mulA+1
	lda tmp
	jsr mul16x8                  ; mulR+1/+2 = vx 8.8
	lda mulR+1
	sta dxL                      ; reuse as vxF
	lda mulR+2
	sta dxH                      ; vxI
	lda spdF
	sta mulA
	lda spdI
	sta mulA+1
	lda tmp2
	jsr mul16x8
	lda mulR+1
	sta dyL                      ; vyF
	lda mulR+2
	sta dyH                      ; vyI
	; face
	lda sgnX
	bmi @faceL
	lda #1
	sta aface,x
	bra @applyX
@faceL:
	stz aface,x
@applyX:
	lda dxH
	ora dxL
	beq @doY
	lda sgnX
	bmi @negX
	jsr stepPosX
	bra @doY
@negX:
	jsr stepNegX
@doY:
	lda dyH
	ora dyL
	beq @done
	lda sgnY
	bmi @negY
	jmp stepPosY
@negY:
	jmp stepNegY
@done:
	rts

; axis steppers: apply (dxL/dxH = v 8.8) to slot X with collision.
; ground actors (wolf/cat/grandpa/hunter/peter) test solids; birds fly.
actorFlies:
	lda atype,x
	cmp #AT_BIRD
	beq @fly
	cmp #AT_DUCK
	beq @fly
	cmp #AT_SCOUT
	beq @fly
	clc
	rts
@fly:
	sec
	rts

; half-width per type (collision sampling)
.rodata
typeHW: .byte 0, 5, 10, 8, 4, 4, 5, 5, 4
.code

stepPosX:
	clc
	lda axF,x
	adc dxL
	sta axF,x
	lda axL,x
	adc dxH
	sta candL
	lda axH,x
	adc #0
	sta candH
	; clamp right: worldW-8
	sec
	lda candL
	sbc worldWL
	lda candH
	sbc worldWH
	bcc @inw
	rts                          ; at edge: don't move
@inw:
	jsr collideXCheck
	bcc @free
	rts
@free:
	lda candL
	sta axL,x
	lda candH
	sta axH,x
	rts

stepNegX:
	sec
	lda axF,x
	sbc dxL
	sta axF,x
	lda axL,x
	sbc dxH
	sta candL
	lda axH,x
	sbc #0
	sta candH
	bmi @stop
	; clamp left edge 8
	lda candH
	bne @ok
	lda candL
	cmp #8
	bcc @stop
@ok:
	jsr collideXCheck
	bcs @stop
	lda candL
	sta axL,x
	lda candH
	sta axH,x
@stop:
	rts

; collideXCheck: candidate X in candL/candH, current Y — C=1 blocked
collideXCheck:
	jsr actorFlies
	bcc @ground
	clc
	rts
@ground:
	phy
	ldy atype,x
	lda typeHW,y
	ply
	sta tmp3
	; sample both feet corners at y and y-6
	sec
	lda candL
	sbc tmp3
	sta sampX
	lda candH
	sbc #0
	sta sampX+1
	lda ayL,x
	sta sampY
	lda ayH,x
	sta sampY+1
	jsr solidAtPx
	bcs @hit
	clc
	lda candL
	adc tmp3
	sta sampX
	lda candH
	adc #0
	sta sampX+1
	jsr solidAtPx
	bcs @hit
	sec
	lda ayL,x
	sbc #6
	sta sampY
	lda ayH,x
	sbc #0
	sta sampY+1
	jsr solidAtPx
	bcs @hit
	sec
	lda candL
	sbc tmp3
	sta sampX
	lda candH
	sbc #0
	sta sampX+1
	jsr solidAtPx
	bcs @hit
	clc
	rts
@hit:
	sec
	rts

stepPosY:
	clc
	lda ayF,x
	adc dyL
	sta ayF,x
	lda ayL,x
	adc dyH
	sta candL
	lda ayH,x
	adc #0
	sta candH
	; clamp bottom: worldH-4
	sec
	lda candL
	sbc worldHL
	lda candH
	sbc worldHH
	bcc @inw
	rts
@inw:
	jsr collideYCheck
	bcs @blocked
	lda candL
	sta ayL,x
	lda candH
	sta ayH,x
@blocked:
	rts

stepNegY:
	sec
	lda ayF,x
	sbc dyL
	sta ayF,x
	lda ayL,x
	sbc dyH
	sta candL
	lda ayH,x
	sbc #0
	sta candH
	bmi @stop
	lda candH
	bne @ok
	lda candL
	cmp #12
	bcc @stop
@ok:
	jsr collideYCheck
	bcs @stop
	lda candL
	sta ayL,x
	lda candH
	sta ayH,x
@stop:
	rts

; collideYCheck: candidate Y in candL/candH, current X — C=1 blocked
collideYCheck:
	jsr actorFlies
	bcc @ground
	clc
	rts
@ground:
	phy
	ldy atype,x
	lda typeHW,y
	ply
	sta tmp3
	lda candL
	sta sampY
	lda candH
	sta sampY+1
	sec
	lda axL,x
	sbc tmp3
	sta sampX
	lda axH,x
	sbc #0
	sta sampX+1
	jsr solidAtPx
	bcs @hit
	clc
	lda axL,x
	adc tmp3
	sta sampX
	lda axH,x
	adc #0
	sta sampX+1
	jsr solidAtPx
	bcs @hit
	clc
	rts
@hit:
	sec
	rts

; ------------------------------------------------------------
; setActor: spawn slot X, type A at cell (tmp=cx, tmp2=cy)
; ------------------------------------------------------------
setActor:
	sta atype,x
	lda tmp
	stz tmpHi
	asl
	rol tmpHi
	asl
	rol tmpHi
	asl
	rol tmpHi
	sta axL,x
	lda tmpHi
	sta axH,x
	lda tmp2
	stz tmpHi
	asl
	rol tmpHi
	asl
	rol tmpHi
	asl
	rol tmpHi
	sta ayL,x
	lda tmpHi
	sta ayH,x
	stz axF,x
	stz ayF,x
	stz astate,x
	stz atmr,x
	stz atmr2,x
	stz aface,x
	stz aanim,x
	stz wsuspF,x
	stz wsuspI,x
	stz wpcd,x
	rts

; ------------------------------------------------------------
; startLevel: build world, place cast, reset play state
; ------------------------------------------------------------
startLevel:
	; terrain palette bank + mood
	lda #$10                     ; bank 1
	sta terrBank
	ldx level
	lda lvType,x
	cmp #LT_ESCORT
	bne :+
	lda #$60                     ; night: start dark (bank 6)
	sta terrBank
:	jsr buildWorld
	jsr applyMood

	; clear actors
	ldx #NACT-1
:	stz atype,x
	dex
	bpl :-
	jsr clearSprShadow

	; Peter
	ldx level
	lda lvPeterX,x
	sta tmp
	lda lvPeterY,x
	sta tmp2
	ldx #SL_PETER
	lda #AT_PETER
	jsr setActor

	; primary foe
	ldx level
	lda lvFoeX,x
	sta tmp
	lda lvFoeY,x
	sta tmp2
	ldx level
	lda lvType,x
	cmp #LT_BIRD
	bne @wolf
	lda #AT_CAT
	bra @foeSet
@wolf:
	lda #AT_WOLF
@foeSet:
	ldx #SL_FOE1
	jsr setActor
	lda #1
	sta wolfCount
	; relentless levels: the hunt never stops
	ldx level
	lda lvType,x
	cmp #LT_ROPE
	beq @relent
	cmp #LT_CHASE
	beq @relent
	cmp #LT_ENDLESS
	bne @calm
@relent:
	lda #WS_HUNT
	sta astate+SL_FOE1
@calm:

	; follower / extras per level type
	ldx level
	lda lvType,x
	cmp #LT_BIRD
	bne :+
	jsr spawnFollowerBird
:	cmp #LT_DUCK
	bne :+
	jsr spawnFollowerDuck
:	cmp #LT_ESCORT
	bne :+
	jsr spawnFollowerGrandpa
:	cmp #LT_ROPE
	bne :+
	jsr spawnIdleGrandpa
:	cmp #LT_APPLES
	bne :+
	jsr spawnScout
:
	; apples
	jsr spawnLevelApples

	; state
	lda #3
	sta hearts
	lda #70
	sta invuln
	stz nextApple
	inc nextApple                ; = 1
	stz applesGot
	stz whistleCd
	stz whistleCd+1
	stz carryRope
	stz ropeDropped
	stz snareArmed
	stz tiptoe
	stz playFL
	stz playFH
	lda #<1000
	sta bonusL
	lda #>1000
	sta bonusH
	stz bonus6
	stz loseFlag
	stz winFlag
	stz captureFlag
	stz curtainShown
	stz endlessSec
	stz huntOn
	lda #<600
	sta huntEvT
	lda #>600
	sta huntEvT+1
	stz doveOn
	stz scoutPh
	ldx #NTHROWN-1
:	stz thLife,x
	dex
	bpl :-
	lda #<2400
	sta wolfSpawnL
	lda #>2400
	sta wolfSpawnH

	; rope hides under a random rock (L4)
	jsr rnd
	ldx rockCnt
	beq :+
@mod:
	cmp rockCnt
	bcc :+
	sec
	sbc rockCnt
	bra @mod
:	sta ropeRock

	; snap camera to Peter
	jsr camTargetPeter
	lda camTX
	sta camX
	lda camTX+1
	sta camX+1
	lda camTY
	sta camY
	lda camTY+1
	sta camY+1

	; music: the level's theme
	ldx level
	lda lvSong,x
	jsr musicPlay
	jsr hudInit
	rts

spawnFollowerBird:
	pha
	lda #12
	sta tmp
	lda #44
	sta tmp2
	ldx #SL_FRIEND
	lda #AT_BIRD
	jsr setActor
	pla
	rts

spawnFollowerDuck:
	pha
	lda #14
	sta tmp
	lda #24
	sta tmp2
	ldx #SL_FRIEND
	lda #AT_DUCK
	jsr setActor
	pla
	rts

spawnFollowerGrandpa:
	pha
	lda #10
	sta tmp
	lda #34
	sta tmp2
	ldx #SL_FRIEND
	lda #AT_GRANDPA
	jsr setActor
	pla
	rts

spawnIdleGrandpa:
	pha
	lda #108
	sta tmp
	lda #26
	sta tmp2
	ldx #SL_EXTRA
	lda #AT_GRANDPA
	jsr setActor
	pla
	rts

spawnScout:
	pha
	ldx level
	lda lvFoeX,x
	sta tmp
	lda lvFoeY,x
	sta tmp2
	ldx #SL_EXTRA
	lda #AT_SCOUT
	jsr setActor
	pla
	rts

; ------------------------------------------------------------
; spawnLevelApples: numbered (L1) or ammo apples on open grass
; ------------------------------------------------------------
spawnLevelApples:
	ldx level
	lda lvType,x
	cmp #LT_APPLES
	bne @ammoLv
	; N = 4 + round, cap 9
	lda round
	clc
	adc #4
	cmp #10
	bcc :+
	lda #9
:	sta applesAll
	sta tmp3                     ; count
	lda #0
	sta ammo
	bra @place
@ammoLv:
	cmp #LT_CHASE
	bne :+
	lda #8
	sta tmp3
	lda #3
	sta ammo
	stz applesAll
	bra @place
:	lda #8
	sta tmp3
	lda #4
	sta ammo
	stz applesAll
@place:
	stz appleCnt
	ldx #9                       ; clear all slots (BSS is not zeroed)
:	stz appleNum,x
	dex
	bpl :-
	lda tmp3
	bne @next
	rts
@next:
	; random open cell
	jsr rnd
	and #127
	ldy mapWide
	beq :+
	jsr rnd                      ; chase: x 0..255
:	cmp #4
	bcc @next
	sta cellX
	ldy mapWide
	beq @nrY
	; wide: y 2..29
	jsr rnd
	and #31
	cmp #2
	bcc @next
	cmp #30
	bcs @next
	sta cellY
	bra @try
@nrY:
	jsr rnd
	and #63
	cmp #3
	bcc @next
	cmp #61
	bcs @next
	sta cellY
	lda cellX
	cmp #122
	bcs @next
@try:
	jsr getCell
	tay
	lda tileSolid,y
	bne @next
	; store as world px (cell*8+4)
	ldx appleCnt
	lda cellX
	stz tmpHi
	asl
	rol tmpHi
	asl
	rol tmpHi
	asl
	rol tmpHi
	clc
	adc #4
	sta appleXL,x
	lda tmpHi
	adc #0
	sta appleXH,x
	lda cellY
	asl
	asl
	asl
	clc
	adc #4
	sta appleYL,x
	; number
	ldy level
	lda lvType,y
	cmp #LT_APPLES
	bne @ammoNum
	inx
	txa                          ; 1..N
	ldx appleCnt
	sta appleNum,x
	bra @stored
@ammoNum:
	lda #$FF
	ldx appleCnt
	sta appleNum,x
@stored:
	inc appleCnt
	dec tmp3
	beq @done
	jmp @next
@done:
	rts

; ------------------------------------------------------------
; camTargetPeter: camera target = Peter centered, clamped
; ------------------------------------------------------------
camTargetPeter:
	sec
	lda axL+SL_PETER
	sbc #<160
	sta camTX
	lda axH+SL_PETER
	sbc #>160
	sta camTX+1
	bpl :+
	stz camTX
	stz camTX+1
:	sec
	lda camTX
	sbc camMaxXL
	lda camTX+1
	sbc camMaxXH
	bcc :+
	lda camMaxXL
	sta camTX
	lda camMaxXH
	sta camTX+1
:	sec
	lda ayL+SL_PETER
	sbc #<120
	sta camTY
	lda ayH+SL_PETER
	sbc #>120
	sta camTY+1
	bpl :+
	stz camTY
	stz camTY+1
:	sec
	lda camTY
	sbc camMaxYL
	lda camTY+1
	sbc camMaxYH
	bcc :+
	lda camMaxYL
	sta camTY
	lda camMaxYH
	sta camTY+1
:	rts

; ============================================================
;  tickPlay — one game frame
; ============================================================
tickPlay:
	inc playFL
	bne :+
	inc playFH
:	; speed bonus melts: -1 per 6 frames
	inc bonus6
	lda bonus6
	cmp #6
	bcc @bonusDone
	stz bonus6
	lda bonusL
	ora bonusH
	beq @bonusDone
	lda bonusL
	bne :+
	dec bonusH
:	dec bonusL
@bonusDone:
	jsr petTick
	jsr foesTick
	jsr foeContactSweep
	jsr friendTick
	jsr extraTick
	jsr huntersTick
	jsr thrownTick
	jsr ambientTick
	; shaken trees recover (x4 frames)
	lda frame
	and #3
	bne @noShake
	ldx treeCnt
	beq @noShake
	dex
:	lda treeShake,x
	beq :+
	dec treeShake,x
:	dex
	bpl :--
@noShake:
	jsr camTargetPeter
	jsr camTick
	jsr lightTick                ; night light circle / chase fade
	jsr drawActors
	jsr drawApples
	jsr hudTick
	jsr minimapTick

	; pause (never during the attract demo)
	lda attract
	bne @noPause
	lda joyBEdge
	and #JB_START
	beq :+
	jsr pauseLoop
:	lda keyChar
	cmp #'P'
	bne :+
	jsr pauseLoop
:	cmp #'M'
	bne :+
	jsr musicToggle
:
@noPause:
	; outcome
	lda loseFlag
	beq :+
	jmp enterLose
:	lda captureFlag
	beq :+
	jmp enterCapture
:	lda winFlag
	beq :+
	jmp enterWin
:	jmp stateDone

pauseLoop:
	; simple freeze until START/P again
	jsr printPaused
@wait:
	jsr RDTIM
	cmp lastJiffy
	beq @wait
	sta lastJiffy
	jsr readInput
	lda joyBEdge
	and #JB_START
	bne @done
	lda keyChar
	cmp #'P'
	bne @wait
@done:
	ldy #14
	jsr clearHudRow
	rts

; ------------------------------------------------------------
; petTick: input movement, actions
; ------------------------------------------------------------
petTick:
	lda invuln
	beq :+
	dec invuln
:	lda whistleCd
	ora whistleCd+1
	beq @cdDone
	lda whistleCd
	bne :+
	dec whistleCd+1
:	dec whistleCd
@cdDone:
	; tip-toe: SELECT (Left Shift) held
	lda joyB
	and #JB_SEL
	bne :+
	lda #1
	sta tiptoe
	bra :++
:	stz tiptoe
:
	; speed
	lda tiptoe
	beq @walkSpd
	lda #<277                    ; 1.08 px/f
	sta dxL
	lda #>277
	sta dxH
	bra @spdSet
@walkSpd:
	lda carryRope
	cmp #1
	bne @full
	lda #<410                    ; 1.6 px/f with the rope
	sta dxL
	lda #>410
	sta dxH
	bra @spdSet
@full:
	lda #<486                    ; 1.9 px/f
	sta dxL
	lda #>486
	sta dxH
@spdSet:
	; diagonal? scale 3/4
	lda joyB
	eor #$FF
	and #(JB_UP|JB_DOWN)
	beq @axes
	lda joyB
	eor #$FF
	and #(JB_LEFT|JB_RIGHT)
	beq @axes
	; *0.75
	lda dxH
	lsr
	sta tmpHi
	lda dxL
	ror
	sta tmpLo
	lsr tmpHi
	ror tmpLo
	sec
	lda dxL
	sbc tmpLo
	sta dxL
	lda dxH
	sbc tmpHi
	sta dxH
@axes:
	lda dxL
	sta dyL
	lda dxH
	sta dyH
	stz petMoving
	ldx #SL_PETER
	lda joyB
	and #JB_LEFT
	bne :+
	jsr stepNegX
	lda #2
	sta petDir
	stz aface+SL_PETER
	inc petMoving
:	lda joyB
	and #JB_RIGHT
	bne :+
	jsr stepPosX
	lda #3
	sta petDir
	lda #1
	sta aface+SL_PETER
	inc petMoving
:	lda joyB
	and #JB_UP
	bne :+
	jsr stepNegY
	lda #1
	sta petDir
	inc petMoving
:	lda joyB
	and #JB_DOWN
	bne :+
	jsr stepPosY
	stz petDir
	inc petMoving
:
	lda petMoving
	beq @still
	inc aanim+SL_PETER
	; footstep noise
	lda tiptoe
	bne @still
	lda frame
	and #15
	bne @still
	jsr sfxStep
@still:

	; ---- actions ----
	; whistle: A button or E
	lda joyXEdge
	and #JX_A
	bne @whistle
	lda keyChar
	cmp #'E'
	beq @whistle
	bra @noWhistle
@whistle:
	jsr doWhistle
@noWhistle:
	; action: B button or SPACE
	lda joyBEdge
	and #JB_B
	bne @act
	lda keyChar
	cmp #' '
	beq @act
	bra @noAct
@act:
	jsr doAction
@noAct:
	; drop rope: X button or Q
	lda carryRope
	cmp #1
	bne @noDrop
	lda joyXEdge
	and #JX_X
	bne @drop
	lda keyChar
	cmp #'Q'
	beq @drop
	bra @noDrop
@drop:
	jsr dropRope
@noDrop:

	; world apple pickup (walk over)
	jsr pickupCheck
	; rope pickup if dropped
	lda ropeDropped
	beq :+
	jsr ropePickCheck
:	; objective checks (gate exit etc.)
	jmp objectiveTick

; ------------------------------------------------------------
; doWhistle
; ------------------------------------------------------------
doWhistle:
	lda whistleCd
	ora whistleCd+1
	beq :+
	rts
:	lda #<260
	sta whistleCd
	lda #>260
	sta whistleCd+1
	jsr sfxWhistle
	; call the follower
	lda atype+SL_FRIEND
	beq @noFriend
	lda astate+SL_FRIEND
	cmp #FS_FOLLOW
	beq @noFriend
	ldx #SL_FRIEND
	ldy #SL_PETER
	jsr actorDist
	lda distH
	cmp #>258
	bne :+
	lda distL
	cmp #<258
:	bcs @noFriend
	lda #FS_FOLLOW
	sta astate+SL_FRIEND
@noFriend:
	; L1: scout bird dives, pinning the wolf
	lda atype+SL_EXTRA
	cmp #AT_SCOUT
	bne @noScout
	lda #1
	sta scoutPh                  ; dive!
@noScout:
	; alert foes within 324 px (they hear it)
	ldx #SL_FOE3
@foe:
	lda atype,x
	beq @nextFoe
	lda astate,x
	cmp #WS_STUN
	beq @nextFoe
	phx
	ldy #SL_PETER
	jsr actorDist
	plx
	lda distH
	cmp #>324
	bne :+
	lda distL
	cmp #<324
:	bcs @nextFoe
	; wolf takes note: waypoint = Peter, suspicion up
	lda axL+SL_PETER
	sta atgXL,x
	lda axH+SL_PETER
	sta atgXH,x
	lda ayL+SL_PETER
	sta atgYL,x
	lda ayH+SL_PETER
	sta atgYH,x
	clc
	lda wsuspI,x
	adc #10
	cmp #100
	bcc :+
	lda #100
:	sta wsuspI,x
@nextFoe:
	dex
	cpx #SL_FOE1
	bcs @foe
	rts

; ------------------------------------------------------------
; doAction: throw / search rock / set-spring snare / shake tree
; ------------------------------------------------------------
doAction:
	; near the snare oak?
	lda oakXL
	sta tgXL
	lda oakXH
	sta tgXH
	lda oakYL
	sta tgYL
	stz tgYH
	ldx #SL_PETER
	jsr distToPoint
	lda distH
	bne @notOak
	lda distL
	cmp #56
	bcs @notOak
	; at the oak: spring the snare if armed & wolf under it
	lda snareArmed
	beq @maybeSet
	jsr wolfUnderOak
	bcc @notOak
	inc captureFlag
	rts
@maybeSet:
	; L4: carrying rope -> set the snare
	lda carryRope
	cmp #1
	bne @notOak
	lda #2
	sta carryRope
	lda #1
	sta snareArmed
	jsr sfxDing
	lda #MSG_SNARESET
	jsr flashMsg
	rts
@notOak:
	; L4: search a rock
	ldx level
	lda lvType,x
	cmp #LT_ROPE
	bne @noSearch
	lda carryRope
	bne @noSearch
	jsr searchRockCheck
	bcs @acted
@noSearch:
	; throw an apple if we have one
	jsr throwApple
@acted:
	rts

; searchRockCheck: C=1 if a rock was searched
searchRockCheck:
	ldx rockCnt
	beq @no
	dex
@rock:
	lda rockDone,x
	bne @next
	lda rockXL,x
	sta tgXL
	lda rockXH,x
	sta tgXH
	lda rockYL,x
	sta tgYL
	stz tgYH
	phx
	ldx #SL_PETER
	jsr distToPoint
	plx
	lda distH
	bne @next
	lda distL
	cmp #28
	bcs @next
	; search it
	lda #1
	sta rockDone,x
	jsr sfxThud
	cpx ropeRock
	bne @empty
	lda #1
	sta carryRope
	lda #MSG_ROPEFOUND
	jsr flashMsg
	sec
	rts
@empty:
	lda #MSG_NOROPE
	jsr flashMsg
	sec
	rts
@next:
	dex
	bpl @rock
@no:
	clc
	rts

; wolfUnderOak: C=1 if any wolf within 45px of the oak
wolfUnderOak:
	ldx #SL_FOE3
@foe:
	lda atype,x
	cmp #AT_WOLF
	bne @next
	lda oakXL
	sta tgXL
	lda oakXH
	sta tgXH
	lda oakYL
	sta tgYL
	stz tgYH
	jsr distToPoint
	lda distH
	bne @next
	lda distL
	cmp #45
	bcs @next
	sec
	rts
@next:
	dex
	cpx #SL_FOE1
	bcs @foe
	clc
	rts

; ------------------------------------------------------------
; throwApple / shake tree fallback
; ------------------------------------------------------------
throwApple:
	; ammo levels use ammo; L1 pops the last numbered apple
	ldx level
	lda lvType,x
	cmp #LT_APPLES
	beq @l1
	lda carryRope
	cmp #1
	beq @none                    ; hands full
	lda ammo
	bne @haveAmmo
	jmp shakeTreeCheck
@haveAmmo:
	dec ammo
	lda #0                       ; plain apple
	jmp launchApple
@l1:
	lda nextApple
	cmp #2
	bcs @pop
@none:
	rts
@pop:
	dec nextApple
	dec applesGot
	stz snareArmed               ; un-arms the oak snare
	jsr gateRecheck
	lda nextApple                ; the popped number
	jmp launchApple

; launchApple: A = number (0 plain). Auto-aims at nearest foe.
launchApple:
	sta tmp3
	; find a free thrown slot
	ldx #NTHROWN-1
@find:
	lda thLife,x
	beq @got
	dex
	bpl @find
	rts
@got:
	phx
	; aim: nearest live foe (falls back to facing direction)
	jsr nearestFoe               ; Y = slot (0 = none)
	cpy #0
	bne @aim
	; no foe: throw straight ahead
	plx
	lda tmp3
	sta thNum,x
	lda #80
	sta thLife,x
	lda axL+SL_PETER
	sta thXL,x
	lda axH+SL_PETER
	sta thXH,x
	stz thXF,x
	sec
	lda ayL+SL_PETER
	sbc #14
	sta thYL,x
	lda ayH+SL_PETER
	sbc #0
	sta thYH,x
	stz thYF,x
	lda #<1075
	sta thVXF,x
	lda #>1075
	sta thVXI,x
	stz thVYF,x
	stz thVYI,x
	stz thVYSg,x
	lda aface+SL_PETER
	eor #1
	sta thVXSg,x
	jsr sfxThrow
	rts
@aim:
	sty tmp2
	ldx #SL_PETER
	lda axL,y
	sta tgXL
	lda axH,y
	sta tgXH
	lda ayL,y
	sta tgYL
	lda ayH,y
	sta tgYH
	jsr distToPoint
	; velocity 4.5 px/f split by the same slope classes
	; reuse moveToward's classification via fractions:
	; (simplified: dominant axis 4.2, minor 1.8, diagonal 3.2/3.2)
	plx
	lda tmp3
	sta thNum,x
	lda #80
	sta thLife,x
	; start at Peter
	lda axL+SL_PETER
	sta thXL,x
	lda axH+SL_PETER
	sta thXH,x
	stz thXF,x
	sec
	lda ayL+SL_PETER
	sbc #14
	sta thYL,x
	lda ayH+SL_PETER
	sbc #0
	sta thYH,x
	stz thYF,x
	; slope class
	lda dxH
	lsr
	sta tmpHi
	lda dxL
	ror
	sta tmpLo
	lda dyH
	cmp tmpHi
	bne :+
	lda dyL
	cmp tmpLo
:	bcc @xmaj
	lda dyH
	lsr
	sta tmpHi
	lda dyL
	ror
	sta tmpLo
	lda dxH
	cmp tmpHi
	bne :+
	lda dxL
	cmp tmpLo
:	bcc @ymaj
	lda #<819                    ; 3.2
	sta thVXF,x
	lda #>819
	sta thVXI,x
	lda #<819
	sta thVYF,x
	lda #>819
	sta thVYI,x
	bra @sign
@xmaj:
	lda #<1075                   ; 4.2
	sta thVXF,x
	lda #>1075
	sta thVXI,x
	lda #<460                    ; 1.8
	sta thVYF,x
	lda #>460
	sta thVYI,x
	bra @sign
@ymaj:
	lda #<460
	sta thVXF,x
	lda #>460
	sta thVXI,x
	lda #<1075
	sta thVYF,x
	lda #>1075
	sta thVYI,x
@sign:
	lda sgnX
	bmi :+
	stz thVXSg,x
	bra :++
:	lda #1
	sta thVXSg,x
:	lda sgnY
	bmi :+
	stz thVYSg,x
	bra :++
:	lda #1
	sta thVYSg,x
:	jsr sfxThrow
	rts

; nearestFoe: Y = closest live foe slot to Peter, 0 if none
nearestFoe:
	lda #$FF
	sta tmpLo                    ; best dist
	sta tmpHi
	stz tmp2                     ; best slot
	ldx #SL_FOE1
@foe:
	lda atype,x
	beq @next
	lda astate,x
	cmp #WS_STUN
	beq @next
	phx
	txa
	tay
	ldx #SL_PETER
	jsr actorDist
	plx
	lda distH
	cmp tmpHi
	bne :+
	lda distL
	cmp tmpLo
:	bcs @next
	lda distL
	sta tmpLo
	lda distH
	sta tmpHi
	stx tmp2
@next:
	inx
	cpx #SL_FOE3+1
	bne @foe
	ldy tmp2
	rts

; ------------------------------------------------------------
; shakeTreeCheck: near a tree with no ammo -> drop 1-2 apples
; ------------------------------------------------------------
shakeTreeCheck:
	ldx treeCnt
	beq @no
	dex
@tree:
	lda treeShake,x
	bne @next
	lda treeXL,x
	sta tgXL
	lda treeXH,x
	sta tgXH
	lda treeYL,x
	sta tgYL
	stz tgYH
	phx
	ldx #SL_PETER
	jsr distToPoint
	plx
	lda distH
	bne @next
	lda distL
	cmp #24
	bcs @next
	; shake!
	lda #225                     ; ~900 frames (x4 tick)
	sta treeShake,x
	jsr sfxThud
	; drop an apple next to the trunk
	ldy appleCnt
	cpy #10
	bcs @noApple
	lda treeXL,x
	sta appleXL,y
	lda treeXH,x
	sta appleXH,y
	lda treeYL,x
	clc
	adc #10
	sta appleYL,y
	lda #$FF
	sta appleNum,y
	inc appleCnt
@noApple:
	; the noise draws the hunters' quarry
	jsr alertFoesToPeter
	sec
	rts
@next:
	dex
	bpl @tree
@no:
	clc
	rts

alertFoesToPeter:
	ldx #SL_FOE1
@foe:
	lda atype,x
	beq @next
	lda axL+SL_PETER
	sta atgXL,x
	lda axH+SL_PETER
	sta atgXH,x
	lda ayL+SL_PETER
	sta atgYL,x
	lda ayH+SL_PETER
	sta atgYH,x
	clc
	lda wsuspI,x
	adc #14
	cmp #100
	bcc :+
	lda #100
:	sta wsuspI,x
@next:
	inx
	cpx #SL_FOE3+1
	bne @foe
	rts

; ------------------------------------------------------------
; dropRope / pickup
; ------------------------------------------------------------
dropRope:
	stz carryRope
	lda #1
	sta ropeDropped
	lda axL+SL_PETER
	sta ropeDropXL
	lda axH+SL_PETER
	sta ropeDropXH
	lda ayL+SL_PETER
	sta ropeDropYL
	rts

ropePickCheck:
	lda ropeDropXL
	sta tgXL
	lda ropeDropXH
	sta tgXH
	lda ropeDropYL
	sta tgYL
	stz tgYH
	ldx #SL_PETER
	jsr distToPoint
	lda distH
	bne @no
	lda distL
	cmp #12
	bcs @no
	stz ropeDropped
	lda #1
	sta carryRope
@no:
	rts

; ------------------------------------------------------------
; pickupCheck: Peter over a world apple
; ------------------------------------------------------------
pickupCheck:
	ldx appleCnt
	beq @done
	dex
@apple:
	lda appleNum,x
	beq @next
	lda appleXL,x
	sta tgXL
	lda appleXH,x
	sta tgXH
	lda appleYL,x
	sta tgYL
	stz tgYH
	phx
	ldx #SL_PETER
	jsr distToPoint
	plx
	lda distH
	bne @next
	lda distL
	cmp #12
	bcs @next
	; the right apple?
	lda appleNum,x
	cmp #$FF
	beq @ammoPick
	cmp nextApple
	beq @numPick
	; wrong apple: buzz hint
	lda frame
	and #31
	bne @next
	jsr sfxBuzz
	bra @next
@ammoPick:
	lda ammo
	cmp #9
	bcs @next
	stz appleNum,x
	inc ammo
	jsr sfxPickup
	jsr score50
	bra @next
@numPick:
	stz appleNum,x
	inc nextApple
	inc applesGot
	jsr sfxPickup
	jsr score50
	jsr gateRecheck
@next:
	dex
	bpl @apple
@done:
	rts

; gateRecheck: L1 gate + snare arm when all apples held
gateRecheck:
	ldx level
	lda lvType,x
	cmp #LT_APPLES
	bne @done
	lda applesGot
	cmp applesAll
	bcc @notAll
	jsr openGate
	lda #1
	sta snareArmed
	lda #MSG_GATEOPEN
	jsr flashMsg
	rts
@notAll:
	stz snareArmed
@done:
	rts

; ------------------------------------------------------------
; objectiveTick: level-specific win checks around Peter
; ------------------------------------------------------------
objectiveTick:
	ldx level
	lda lvType,x
	cmp #LT_APPLES
	beq @gateExit
	cmp #LT_ESCORT
	beq @escort
	cmp #LT_CHASE
	beq @chase
	rts
@chase:
	; the pre-armed snare springs itself when the wolf blunders in
	jsr wolfUnderOak
	bcc @no
	inc captureFlag
	rts
@gateExit:
	lda gateOpenF
	beq @no
	; Peter at right edge inside the gate rows?
	lda axH+SL_PETER
	cmp #>1000
	bne :+
	lda axL+SL_PETER
	cmp #<1000
:	bcc @no
	inc winFlag
@no:
	rts
@escort:
	; win when Grandpa reaches the gate zone
	lda atype+SL_FRIEND
	beq @no
	lda axH+SL_FRIEND
	cmp #>984
	bne :+
	lda axL+SL_FRIEND
	cmp #<984
:	bcc @no
	inc winFlag
	rts

; ------------------------------------------------------------
; damagePeter: called on foe contact (X = foe slot)
; ------------------------------------------------------------
damagePeter:
	lda invuln
	beq :+
	rts
:	dec hearts
	phx                          ; sfxPlay rotates channels in X
	jsr sfxHurt
	plx
	lda #140
	sta invuln
	; daze the foe & knock it back
	lda #WS_DAZE
	sta astate,x
	lda #70
	sta atmr,x
	; knockback: move foe away from Peter by setting its waypoint behind it
	lda axL,x
	sta atgXL,x
	lda axH,x
	sta atgXH,x
	lda ayL,x
	sta atgYL,x
	lda ayH,x
	sta atgYH,x
	lda hearts
	bne @alive
	inc loseFlag
@alive:
	rts

; ------------------------------------------------------------
; foesTick: wolf/cat AI for slots 1..3
; ------------------------------------------------------------
foesTick:
	ldx #SL_FOE1
@loop:
	phx
	lda atype,x
	beq @skip
	jsr foeAI
@skip:
	plx
	inx
	cpx #SL_FOE3+1
	bne @loop

	; endless: spawn extra wolves over time
	ldx level
	lda lvType,x
	cmp #LT_ENDLESS
	bne @done
	lda wolfSpawnL
	ora wolfSpawnH
	beq @spawn
	lda wolfSpawnL
	bne :+
	dec wolfSpawnH
:	dec wolfSpawnL
	bra @done
@spawn:
	lda wolfCount
	cmp #3
	bcs @done
	; next free foe slot
	ldx #SL_FOE2
	lda atype,x
	beq @free
	ldx #SL_FOE3
	lda atype,x
	bne @done
@free:
	lda #4
	sta tmp
	jsr rnd
	and #63
	sta tmp2
	lda #AT_WOLF
	jsr setActor
	lda #WS_HUNT
	sta astate,x
	inc wolfCount
	lda #<2400
	sta wolfSpawnL
	lda #>2400
	sta wolfSpawnH
	jsr sfxGrowl
@done:
	rts

; foeAI: X = slot (preserved by caller)
foeAI:
	; timers
	lda wpcd,x
	beq :+
	dec wpcd,x
:	lda atmr,x
	beq @noTimer
	dec atmr,x
@noTimer:

	lda astate,x
	cmp #WS_STUN
	bne :+
	jmp foeStun
:	cmp #WS_DAZE
	bne :+
	jmp foeDaze
:	cmp #WS_CROUCH
	bne :+
	jmp foeCrouch
:	cmp #WS_POUNCE
	bne :+
	jmp foePounce
:	cmp #WS_SLINK
	bne :+
	jmp foeSlink
:	cmp #WS_DISTRACT
	bne :+
	jmp foeDistract
:
	; hunters nearby? -> slink (wolves only)
	lda atype,x
	cmp #AT_WOLF
	bne @noFear
	lda huntOn
	beq @noFear
	phx
	ldy #SL_HUNT1
	jsr actorDist
	plx
	lda distH
	bne @noFear
	lda distL
	cmp #204
	bcs @noFear
	lda #WS_SLINK
	sta astate,x
	lda #120
	sta atmr,x
	rts
@noFear:

	lda astate,x
	cmp #WS_HUNT
	beq @hunt
	jmp foePatrol
@hunt:
	jmp foeHunt

; ---- patrol: wander to random waypoints, watch for prey ----
foePatrol:
	; arrive / re-pick waypoint
	lda atmr2,x
	beq @pick
	dec atmr2,x
	; move toward waypoint at 0.75 speed
	lda atgXL,x
	sta tgXL
	lda atgXH,x
	sta tgXH
	lda atgYL,x
	sta tgYL
	lda atgYH,x
	sta tgYH
	jsr foeSpeed
	; * 0.75
	lda spdI
	lsr
	sta tmpHi
	lda spdF
	ror
	sta tmpLo
	lsr tmpHi
	ror tmpLo
	sec
	lda spdF
	sbc tmpLo
	sta spdF
	lda spdI
	sbc tmpHi
	sta spdI
	jsr moveToward
	lda frame
	and #1
	bne :+
	inc aanim,x
:	bra @sense
@pick:
	jsr rnd
	and #127
	bne :+
	lda #40
:	sta tmpLo
	ldy mapWide
	beq @nw
	jsr rnd
	sta tmpLo
	jsr rnd
	and #31
	bra @wy
@nw:
	jsr rnd
	and #63
@wy:
	sta tmpHi
	; waypoint px = cell*8
	stz atgXH,x
	lda tmpLo
	asl
	rol atgXH,x
	asl
	rol atgXH,x
	asl
	rol atgXH,x
	sta atgXL,x
	lda tmpHi
	asl
	asl
	asl
	sta atgYL,x
	stz atgYH,x
	jsr rnd
	and #127
	clc
	adc #100
	sta atmr2,x
@sense:
	; suspicion / vision -> hunt
	jmp foeSense

; foeSpeed: spdF/spdI = level foe speed (+tier bumps, +alert bump)
foeSpeed:
	phx
	ldx level
	lda lvFoeSpdL,x
	sta spdF
	lda lvFoeSpdH,x
	sta spdI
	lda tier
	beq @noTier
	; +0.15 per tier
	clc
	lda spdF
	adc #38
	sta spdF
	bcc :+
	inc spdI
:	lda tier
	cmp #2
	bne @noTier
	clc
	lda spdF
	adc #38
	sta spdF
	bcc @noTier
	inc spdI
@noTier:
	plx
	; full suspicion: +0.15
	lda wsuspI,x
	cmp #100
	bcc @done
	clc
	lda spdF
	adc #38
	sta spdF
	bcc @done
	inc spdI
@done:
	rts

; foeSense: see/hear the prey -> suspicion -> hunt
; (actorDist preserves X, so no juggling is needed)
foeSense:
	jsr preySlot                 ; Y = prey slot
	sty tmp3
	jsr actorDist                ; foe X -> prey Y
	; within vision? compare dist/2 with lvVisH
	phx
	ldx level
	lda lvVisH,x
	plx
	sta tmpLo
	lda distH
	lsr
	sta tmpHi
	lda distL
	ror
	; Peter hidden in a bush only counts when very close
	ldy tmp3
	cpy #SL_PETER
	bne @notHidden
	pha
	jsr peterHidden
	bcc @nh2
	pla
	cmp #14
	bcc @see
	bra @noSee
@nh2:
	pla
@notHidden:
	ldy tmpHi
	bne @noSee
	cmp tmpLo
	bcc @see
	; hearing: prey Peter, moving loudly within 90px
	ldy tmp3
	cpy #SL_PETER
	bne @noSee
	lda tiptoe
	bne @noSee
	lda petMoving
	beq @noSee
	lda distH
	bne @noSee
	lda distL
	cmp #90
	bcs @noSee
	; heard: smaller bump
	lda frame
	and #1
	bne @check
	clc
	lda wsuspI,x
	adc #2
	bra @clampS
@see:
	clc
	lda wsuspI,x
	adc #3
@clampS:
	cmp #100
	bcc :+
	lda #100
:	sta wsuspI,x
	bra @check
@noSee:
	lda wsuspI,x
	beq @check
	lda frame
	and #1
	bne @check
	dec wsuspI,x
@check:
	lda wsuspI,x
	cmp #55
	bcc @stay
	lda #WS_HUNT
	sta astate,x
	jsr sfxGrowl
@stay:
	rts

; preySlot: Y = slot this foe hunts (X preserved)
preySlot:
	phx
	ldx level
	lda lvType,x
	plx
	cmp #LT_BIRD
	beq @friend
	cmp #LT_DUCK
	beq @friend
	cmp #LT_ESCORT
	beq @nearer
@peter:
	ldy #SL_PETER
	rts
@friend:
	lda atype+SL_FRIEND
	beq @peter
	lda astate+SL_FRIEND
	cmp #FS_FOLLOW               ; once following Peter, hunt Peter
	beq @peter
	ldy #SL_FRIEND
	rts
@nearer:
	lda atype+SL_FRIEND
	beq @peter
	ldy #SL_PETER
	jsr actorDist
	lda distL
	sta tgXL                     ; scratch (set later by movement)
	lda distH
	sta tgXH
	ldy #SL_FRIEND
	jsr actorDist
	lda distH
	cmp tgXH
	bne :+
	lda distL
	cmp tgXL
:	bcc @useFriend
	ldy #SL_PETER
	rts
@useFriend:
	ldy #SL_FRIEND
	rts

; peterHidden: C=1 when Peter overlaps a bush
peterHidden:
	phx
	ldx bushCnt
	beq @no
	dex
@bush:
	lda bushXL,x
	sta tgXL
	lda bushXH,x
	sta tgXH
	lda bushYL,x
	sta tgYL
	stz tgYH
	phx
	ldx #SL_PETER
	jsr distToPoint
	plx
	lda distH
	bne @next
	lda distL
	cmp #16
	bcs @next
	plx
	sec
	rts
@next:
	dex
	bpl @bush
@no:
	plx
	clc
	rts

; ---- hunt: chase prey, pounce when close ----
foeHunt:
	jsr preySlot
	sty tmp3
	jsr actorDist
	; relentless levels never lose the trail
	phx
	ldx level
	lda lvType,x
	plx
	cmp #LT_ROPE
	beq @keep
	cmp #LT_CHASE
	beq @keep
	cmp #LT_ENDLESS
	beq @keep
	; lose the trail? (vision levels: dist > ~1.7 * vision)
	phx
	ldx level
	lda lvVisH,x
	plx
	sta tmpLo                    ; vision/2
	lda distH
	lsr
	sta tmpHi
	lda distL
	ror                          ; dist/2
	; dist/2 > vision/2 * 1.7  ~=  dist/2 > vision/2 + vision/4 + v/8
	pha
	lda tmpLo
	lsr
	sta tmp2
	lsr
	clc
	adc tmp2
	adc tmpLo
	sta tmp2                     ; ~1.87*vision/2
	pla
	ldy tmpHi
	bne @lost
	cmp tmp2
	bcc @keep
@lost:
	stz wsuspI,x
	lda #WS_PATROL
	sta astate,x
	stz atmr2,x
	rts
@keep:
	; contact?
	lda distH
	bne @noTouch
	lda distL
	cmp #16
	bcs @noTouch
	ldy tmp3
	cpy #SL_PETER
	bne @friendCaught
	jsr damagePeter
	rts
@friendCaught:
	inc loseFlag                 ; a protected friend was caught
	rts
@noTouch:
	; pounce when close & off cooldown
	lda distH
	bne @chase
	lda distL
	cmp #90
	bcs @chase
	lda wpcd,x
	bne @chase
	lda #WS_CROUCH
	sta astate,x
	lda #32
	sta atmr,x
	jsr sfxGrowl
	rts
@chase:
	ldy tmp3
	lda axL,y
	sta tgXL
	lda axH,y
	sta tgXH
	lda ayL,y
	sta tgYL
	lda ayH,y
	sta tgYH
	jsr foeSpeed
	jsr moveToward
	inc aanim,x
	rts

; ---- crouch: telegraph, then leap ----
foeCrouch:
	lda atmr,x
	beq :+
	rts
:
	; leap toward prey at 4.56 px/f (slope-class split)
	jsr preySlot
	jsr actorDist
	lda #WS_POUNCE
	sta astate,x
	lda #20
	sta atmr,x
	lda #190
	sta wpcd,x
	; class
	lda dxH
	lsr
	sta tmpHi
	lda dxL
	ror
	sta tmpLo
	lda dyH
	cmp tmpHi
	bne :+
	lda dyL
	cmp tmpLo
:	bcc @xmaj
	lda dyH
	lsr
	sta tmpHi
	lda dyL
	ror
	sta tmpLo
	lda dxH
	cmp tmpHi
	bne :+
	lda dxL
	cmp tmpLo
:	bcc @ymaj
	lda #<829                    ; 3.24 diagonal
	sta avxF,x
	lda #>829
	sta avxI,x
	lda #<829
	sta avyF,x
	lda #>829
	sta avyI,x
	bra @signs
@xmaj:
	lda #<1126                   ; 4.4
	sta avxF,x
	lda #>1126
	sta avxI,x
	lda #<410
	sta avyF,x
	lda #>410
	sta avyI,x
	bra @signs
@ymaj:
	lda #<410
	sta avxF,x
	lda #>410
	sta avxI,x
	lda #<1126
	sta avyF,x
	lda #>1126
	sta avyI,x
@signs:
	lda sgnX
	bmi :+
	stz avxS,x
	bra :++
:	lda #1
	sta avxS,x
:	lda sgnY
	bmi :+
	stz avyS,x
	bra :++
:	lda #1
	sta avyS,x
:	jsr sfxYelp
	rts
@wait:
	rts

; ---- pounce: fly along stored velocity, decaying ----
foePounce:
	lda atmr,x
	bne @fly
	lda #WS_HUNT
	sta astate,x
	rts
@fly:
	; decay: v -= 16/256 px/f each frame
	sec
	lda avxF,x
	sbc #16
	sta avxF,x
	bcs :+
	lda avxI,x
	beq :+
	dec avxI,x
:	sec
	lda avyF,x
	sbc #16
	sta avyF,x
	bcs :+
	lda avyI,x
	beq :+
	dec avyI,x
:	; apply
	lda avxF,x
	sta dxL
	lda avxI,x
	sta dxH
	lda avxS,x
	bne @negX
	jsr stepPosX
	bra @y
@negX:
	jsr stepNegX
@y:
	lda avyF,x
	sta dyL
	lda avyI,x
	sta dyH
	lda avyS,x
	bne @negY
	jsr stepPosY
	bra @touch
@negY:
	jsr stepNegY
@touch:
	; hit the prey mid-leap?
	jsr preySlot
	sty tmp3
	jsr actorDist
	lda distH
	bne @done
	lda distL
	cmp #17
	bcs @done
	ldy tmp3
	cpy #SL_PETER
	bne @friendCaught
	jsr damagePeter
	lda #WS_HUNT
	sta astate,x
	rts
@friendCaught:
	inc loseFlag
@done:
	rts

; ---- stun / daze / slink / distract ----
foeStun:
	lda atmr,x
	bne @zz
	lda #WS_PATROL
	sta astate,x
	lda #30
	sta wsuspI,x
	stz atmr2,x
@zz:
	rts

foeDaze:
	lda atmr,x
	bne @done
	lda #WS_PATROL
	sta astate,x
	stz atmr2,x
@done:
	rts

foeSlink:
	lda atmr,x
	bne @flee
	lda #WS_PATROL
	sta astate,x
	stz atmr2,x
	stz wsuspI,x
	rts
@flee:
	; run away from hunter 1: target = own pos + (own - hunter) capped
	sec
	lda axL,x
	sbc axL+SL_HUNT1
	sta tmpLo
	lda axH,x
	sbc axH+SL_HUNT1
	sta tmpHi
	jsr abs16                    ; A = sign
	bmi @left
	clc
	lda axL,x
	adc #48
	sta tgXL
	lda axH,x
	adc #0
	sta tgXH
	bra @yflee
@left:
	sec
	lda axL,x
	sbc #48
	sta tgXL
	lda axH,x
	sbc #0
	sta tgXH
@yflee:
	sec
	lda ayL,x
	sbc ayL+SL_HUNT1
	sta tmpLo
	lda ayH,x
	sbc ayH+SL_HUNT1
	sta tmpHi
	jsr abs16
	bmi @up
	clc
	lda ayL,x
	adc #32
	sta tgYL
	lda ayH,x
	adc #0
	sta tgYH
	bra @go
@up:
	sec
	lda ayL,x
	sbc #32
	sta tgYL
	lda ayH,x
	sbc #0
	sta tgYH
@go:
	jsr foeSpeed
	jsr moveToward
	inc aanim,x
	rts

foeDistract:
	lda atmr,x
	bne @done
	lda #WS_HUNT
	sta astate,x
@done:
	rts

; stunFoe: X = slot; an apple found its mark
stunFoe:
	lda #WS_STUN
	sta astate,x
	lda #150
	sta atmr,x
	jsr sfxYelp
	rts

