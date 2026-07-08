; ============================================================
;  actors2.asm — followers, extras, hunters, thrown apples
; ============================================================

; ------------------------------------------------------------
; friendTick: the follower (bird L2 / duck L3 / grandpa L5)
; ------------------------------------------------------------
friendTick:
	ldx #SL_FRIEND
	lda atype,x
	bne :+
	rts
:	lda astate,x
	cmp #FS_FOLLOW
	bne :+
	jmp @follow
:	; idle: does Peter come close? (32 px)
	ldy #SL_PETER
	jsr actorDist
	lda distH
	bne @flee
	lda distL
	cmp #32
	bcs @flee
	lda #FS_FOLLOW
	sta astate,x
	jsr sfxChirp
	rts
@flee:
	; unfollowing: run from a close foe
	ldy #SL_FOE1
	jsr actorDist
	lda distH
	bne @toIdle
	lda distL
	cmp #100
	bcc @fleeGo
@toIdle:
	jmp @idle
@fleeGo:
	; flee directly away
	sec
	lda axL,x
	sbc axL+SL_FOE1
	sta tmpLo
	lda axH,x
	sbc axH+SL_FOE1
	sta tmpHi
	jsr abs16
	bmi @fL
	clc
	lda axL,x
	adc #40
	sta tgXL
	lda axH,x
	adc #0
	sta tgXH
	bra @fY
@fL:
	sec
	lda axL,x
	sbc #40
	sta tgXL
	lda axH,x
	sbc #0
	sta tgXH
@fY:
	sec
	lda ayL,x
	sbc ayL+SL_FOE1
	sta tmpLo
	lda ayH,x
	sbc ayH+SL_FOE1
	sta tmpHi
	jsr abs16
	bmi @fU
	clc
	lda ayL,x
	adc #30
	sta tgYL
	lda ayH,x
	adc #0
	sta tgYH
	bra @fGo
@fU:
	sec
	lda ayL,x
	sbc #30
	sta tgYL
	lda ayH,x
	sbc #0
	sta tgYH
@fGo:
	lda #<369                    ; 1.44 px/f
	sta spdF
	lda #>369
	sta spdI
	jsr moveToward
	inc aanim,x
@idle:
	inc aanim,x
	jmp friendGoal
@follow:
	; target: just behind Peter
	lda aface+SL_PETER
	bne @behindL
	clc
	lda axL+SL_PETER
	adc #12
	sta tgXL
	lda axH+SL_PETER
	adc #0
	sta tgXH
	bra @ty
@behindL:
	sec
	lda axL+SL_PETER
	sbc #12
	sta tgXL
	lda axH+SL_PETER
	sbc #0
	sta tgXH
@ty:
	clc
	lda ayL+SL_PETER
	adc #4
	sta tgYL
	lda ayH+SL_PETER
	adc #0
	sta tgYH
	; stop when near
	jsr distToPoint
	lda distH
	bne @walk
	lda distL
	cmp #10
	bcc @stand
@walk:
	; grandpa is slower
	lda atype,x
	cmp #AT_GRANDPA
	beq @slow
	lda #<415                    ; 1.62
	sta spdF
	lda #>415
	sta spdI
	bra @mv
@slow:
	lda #<300                    ; 1.17
	sta spdF
	lda #>300
	sta spdI
@mv:
	jsr moveToward
	inc aanim,x
@stand:
	jmp friendGoal

; friendGoal: win detection for bird->oak, duck->pond
friendGoal:
	ldx level
	lda lvType,x
	cmp #LT_BIRD
	beq @oak
	cmp #LT_DUCK
	beq @pond
	rts
@oak:
	lda oakXL
	sta tgXL
	lda oakXH
	sta tgXH
	lda oakYL
	sta tgYL
	stz tgYH
	ldx #SL_FRIEND
	jsr distToPoint
	lda distH
	bne @no
	lda distL
	cmp #34
	bcs @no
	inc winFlag
@no:
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
	ldx #SL_FRIEND
	jsr distToPoint
	lda distH
	bne @no2
	lda distL
	cmp #34
	bcs @no2
	inc winFlag
@no2:
	rts

; ------------------------------------------------------------
; extraTick: scout bird (L1) or idle grandpa (L4)
; ------------------------------------------------------------
extraTick:
	ldx #SL_EXTRA
	lda atype,x
	bne :+
	rts
:	cmp #AT_SCOUT
	beq @scout
	; idle grandpa: potter near the oak
	lda atmr2,x
	beq @pickpotter
	dec atmr2,x
	lda atgXL,x
	sta tgXL
	lda atgXH,x
	sta tgXH
	lda atgYL,x
	sta tgYL
	stz tgYH
	lda #<108                    ; 0.42 px/f
	sta spdF
	lda #>108
	sta spdI
	jsr moveToward
	lda frame
	and #3
	bne :+
	inc aanim,x
:	rts
@pickpotter:
	; new potter spot near the oak
	jsr rnd
	and #63
	sec
	sbc #32
	clc
	adc oakXL
	sta atgXL,x
	lda oakXH
	adc #0
	bpl :+
	lda #0
:	sta atgXH,x
	jsr rnd
	and #31
	clc
	adc oakYL
	sta atgYL,x
	stz atgYH,x
	jsr rnd
	and #127
	clc
	adc #140
	sta atmr2,x
	rts
@scout:
	; scout bird circles the wolf; dives on whistle
	lda scoutPh
	beq @circle
	; dive toward the wolf, pin it on contact
	lda axL+SL_FOE1
	sta tgXL
	lda axH+SL_FOE1
	sta tgXH
	lda ayL+SL_FOE1
	sta tgYL
	lda ayH+SL_FOE1
	sta tgYH
	lda #<640                    ; 2.5 px/f dive
	sta spdF
	lda #>640
	sta spdI
	jsr moveToward
	inc aanim,x
	jsr distToPoint
	lda distH
	bne @diving
	lda distL
	cmp #10
	bcs @diving
	stz scoutPh
	lda atype+SL_FOE1
	beq @diving
	phx
	ldx #SL_FOE1
	lda #WS_DISTRACT
	sta astate,x
	lda #110
	sta atmr,x
	plx
	jsr sfxChirp
@diving:
	rts
@circle:
	; pos = wolf + circle(frame)
	lda frame
	lsr
	lsr
	and #15
	tay
	lda sinTab,y
	bpl @px
	eor #$FF
	inc a
	sta tmp
	sec
	lda axL+SL_FOE1
	sbc tmp
	sta axL,x
	lda axH+SL_FOE1
	sbc #0
	sta axH,x
	bra @py
@px:
	clc
	adc axL+SL_FOE1
	sta axL,x
	lda axH+SL_FOE1
	adc #0
	sta axH,x
@py:
	lda frame
	lsr
	lsr
	clc
	adc #4                       ; quarter phase for cos
	and #15
	tay
	lda sinTab,y
	bpl @posY
	eor #$FF
	inc a
	sta tmp
	sec
	lda ayL+SL_FOE1
	sbc tmp
	sta tmp
	bra @setY
@posY:
	clc
	adc ayL+SL_FOE1
	sta tmp
@setY:
	sec
	lda tmp
	sbc #28                      ; hover above
	sta ayL,x
	lda ayH+SL_FOE1
	sbc #0
	bpl :+
	lda #0
:	sta ayH,x
	inc aanim,x
	rts

.rodata
sinTab: .byte 0,8,15,19,20,19,15,8,0
        .byte 256-8,256-15,256-19,256-20,256-19,256-15,256-8
.code

; ------------------------------------------------------------
; huntersTick: rare patrol crossing the world
; ------------------------------------------------------------
huntersTick:
	; only on wolf levels
	lda atype+SL_FOE1
	cmp #AT_WOLF
	beq :+
	rts
:	lda huntOn
	bne @cross
	lda huntEvT
	ora huntEvT+1
	beq @start
	lda huntEvT
	bne :+
	dec huntEvT+1
:	dec huntEvT
	rts
@start:
	lda #1
	sta huntOn
	jsr sfxHorn
	lda #MSG_HUNTERS
	jsr flashMsg
	ldx #SL_HUNT1
	lda #AT_HUNTER
	sta atype,x
	lda #8
	sta axL,x
	stz axH,x
	stz axF,x
	lda ayL+SL_PETER
	sta ayL,x
	lda ayH+SL_PETER
	sta ayH,x
	lda #1
	sta aface,x
	ldx #SL_HUNT2
	lda #AT_HUNTER
	sta atype,x
	lda #8
	sta axL,x
	stz axH,x
	stz axF,x
	sec
	lda ayL+SL_PETER
	sbc #20
	sta ayL,x
	lda ayH+SL_PETER
	sbc #0
	bpl :+
	lda #0
:	sta ayH,x
	lda #1
	sta aface,x
	rts
@cross:
	ldx #SL_HUNT1
	jsr huntStep
	ldx #SL_HUNT2
	jsr huntStep
	; off the far edge?
	sec
	lda worldWL
	sbc #16
	sta tmpLo
	lda worldWH
	sbc #0
	sta tmpHi
	sec
	lda axL+SL_HUNT1
	sbc tmpLo
	lda axH+SL_HUNT1
	sbc tmpHi
	bcc @not
	stz huntOn
	stz atype+SL_HUNT1
	stz atype+SL_HUNT2
	jsr rnd
	sta huntEvT
	lda #7
	sta huntEvT+1
@not:
	rts

huntStep:
	lda #<230                    ; 0.9 px/f
	sta dxL
	lda #>230
	sta dxH
	jsr stepPosX
	inc aanim,x
	rts

; ------------------------------------------------------------
; thrownTick: apples in flight
; ------------------------------------------------------------
thrownTick:
	ldx #NTHROWN-1
@loop:
	lda thLife,x
	beq @next
	jsr thrownOne
@next:
	dex
	bpl @loop
	rts

thrownOne:
	dec thLife,x
	bne @fly
	jmp landApple
@fly:
	; x += vx
	lda thVXSg,x
	bne @xneg
	clc
	lda thXF,x
	adc thVXF,x
	sta thXF,x
	lda thXL,x
	adc thVXI,x
	sta thXL,x
	lda thXH,x
	adc #0
	sta thXH,x
	bra @doY
@xneg:
	sec
	lda thXF,x
	sbc thVXF,x
	sta thXF,x
	lda thXL,x
	sbc thVXI,x
	sta thXL,x
	lda thXH,x
	sbc #0
	sta thXH,x
@doY:
	lda thVYSg,x
	bne @yneg
	clc
	lda thYF,x
	adc thVYF,x
	sta thYF,x
	lda thYL,x
	adc thVYI,x
	sta thYL,x
	lda thYH,x
	adc #0
	sta thYH,x
	bra @grav
@yneg:
	sec
	lda thYF,x
	sbc thVYF,x
	sta thYF,x
	lda thYL,x
	sbc thVYI,x
	sta thYL,x
	lda thYH,x
	sbc #0
	sta thYH,x
@grav:
	; vy += 8/256 downward
	lda thVYSg,x
	bne @gUp
	clc
	lda thVYF,x
	adc #8
	sta thVYF,x
	bcc @edge
	inc thVYI,x
	bra @edge
@gUp:
	sec
	lda thVYF,x
	sbc #8
	sta thVYF,x
	bcs @edge
	lda thVYI,x
	bne :+
	stz thVYSg,x
	stz thVYF,x
	bra @edge
:	dec thVYI,x
@edge:
	; out of the world?
	lda thXH,x
	bmi @kill
	sec
	lda thXL,x
	sbc worldWL
	lda thXH,x
	sbc worldWH
	bcs @kill
	lda thYH,x
	bmi @kill
	sec
	lda thYL,x
	sbc worldHL
	lda thYH,x
	sbc worldHH
	bcs @kill
	; hit a foe?
	jsr thrownHitFoe
	bcs @bounced
	; hit a solid tile?
	lda thXL,x
	sta sampX
	lda thXH,x
	sta sampX+1
	lda thYL,x
	sta sampY
	lda thYH,x
	sta sampY+1
	jsr solidAtPx
	bcs @bounced
	rts
@bounced:
	lda thNum,x
	beq @kill
	jmp bounceApple
@kill:
	lda thNum,x
	beq @free
	jmp landApple
@free:
	stz thLife,x
	rts

; thrownHitFoe: C=1 if apple X hit a foe (stuns it)
thrownHitFoe:
	stx tmp3                     ; apple index
	ldy tmp3
	ldx #SL_FOE1
@foe:
	lda atype,x
	beq @nf
	lda astate,x
	cmp #WS_STUN
	beq @nf
	sec
	lda axL,x
	sbc thXL,y
	sta tmpLo
	lda axH,x
	sbc thXH,y
	sta tmpHi
	jsr abs16
	lda tmpHi
	bne @nf
	lda tmpLo
	cmp #20
	bcs @nf
	sec
	lda ayL,x
	sbc thYL,y
	sta tmpLo
	lda ayH,x
	sbc thYH,y
	sta tmpHi
	jsr abs16
	lda tmpHi
	bne @nf
	lda tmpLo
	cmp #16
	bcs @nf
	jsr stunFoe
	jsr score50
	ldx tmp3
	sec
	rts
@nf:
	inx
	cpx #SL_FOE3+1
	bne @foe
	ldx tmp3
	clc
	rts

; bounceApple: reverse + halve velocity of apple X
bounceApple:
	lda thVXSg,x
	eor #1
	sta thVXSg,x
	lda thVXI,x
	lsr
	sta thVXI,x
	lda thVXF,x
	ror
	sta thVXF,x
	lda thVYSg,x
	eor #1
	sta thVYSg,x
	lda thVYI,x
	lsr
	sta thVYI,x
	lda thVYF,x
	ror
	sta thVYF,x
	; nearly stopped? land it
	lda thVXI,x
	ora thVYI,x
	bne @ok
	lda thVXF,x
	cmp #90
	bcs @ok
	lda thVYF,x
	cmp #90
	bcs @ok
	jmp landApple
@ok:
	jmp sfxThud

; landApple: numbered apples return to the meadow as pickups
landApple:
	stz thLife,x
	lda thNum,x
	beq @done
	; find a dead world-apple slot (or extend)
	ldy #9
@scan:
	lda appleNum,y
	beq @haveY
	dey
	bpl @scan
	rts
@haveY:
	cpy appleCnt
	bcc :+
	iny
	sty appleCnt
	dey
:	lda thXL,x
	sta appleXL,y
	lda thXH,x
	sta appleXH,y
	lda thYL,x
	sta appleYL,y
	lda thYH,x
	sta appleYH,y
	lda thNum,x
	sta appleNum,y
@done:
	rts

; ------------------------------------------------------------
; contact damage sweep: foe body against Peter
; ------------------------------------------------------------
foeContactSweep:
	ldx #SL_FOE1
@foe:
	lda atype,x
	beq @next
	lda astate,x
	cmp #WS_STUN
	beq @next
	cmp #WS_DAZE
	beq @next
	phx
	ldy #SL_PETER
	jsr actorDist
	plx
	lda distH
	bne @next
	lda distL
	cmp #15
	bcs @next
	jsr damagePeter
@next:
	inx
	cpx #SL_FOE3+1
	bne @foe
	rts
