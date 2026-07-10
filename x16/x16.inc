; ============================================================
;  x16.inc — Commander X16 hardware + KERNAL definitions
; ============================================================

; ---------------- VERA registers ----------------
VERA_ADDR_L     = $9F20
VERA_ADDR_M     = $9F21
VERA_ADDR_H     = $9F22          ; bit4 incr low / bits 7:4 = increment sel, bit0 = addr bit16
VERA_DATA0      = $9F23
VERA_DATA1      = $9F24
VERA_CTRL       = $9F25          ; bit0 ADDRSEL, bit1 DCSEL
VERA_IEN        = $9F26          ; bit0 VSYNC, bit1 LINE
VERA_ISR        = $9F27
VERA_IRQLINE_L  = $9F28

; DCSEL = 0
VERA_DC_VIDEO   = $9F29          ; %0111_0001 = spr+L1+L0 on, VGA
VERA_DC_HSCALE  = $9F2A
VERA_DC_VSCALE  = $9F2B
VERA_DC_BORDER  = $9F2C

VERA_L0_CONFIG  = $9F2D
VERA_L0_MAPBASE = $9F2E
VERA_L0_TILEBASE= $9F2F
VERA_L0_HSCROLL_L = $9F30
VERA_L0_HSCROLL_H = $9F31
VERA_L0_VSCROLL_L = $9F32
VERA_L0_VSCROLL_H = $9F33

VERA_L1_CONFIG  = $9F34
VERA_L1_MAPBASE = $9F35
VERA_L1_TILEBASE= $9F36
VERA_L1_HSCROLL_L = $9F37
VERA_L1_HSCROLL_H = $9F38
VERA_L1_VSCROLL_L = $9F39
VERA_L1_VSCROLL_H = $9F3A

; ---------------- YM2151 ----------------
YM_ADDR         = $9F40
YM_DATA         = $9F41

; ---------------- VRAM layout (ours) ----------------
; $00000-$03FFF  layer0 world tile map (16 KB: 128x64 or 256x32 entries)
; $04000-$05FFF  layer0 tileset, 4bpp 8x8, up to 256 tiles (8 KB)
; $06000-$067FF  layer1 charset, 1bpp 8x8 (2 KB)
; $07000-$07FFF  layer1 HUD text map 64x32 (4 KB)
; $08000-.....   sprite frames, 4bpp
; $1F9C0         PSG registers (16 voices x 4 bytes)
; $1FA00         palette (256 entries x 2 bytes)
; $1FC00         sprite attributes (128 x 8 bytes)
VRAM_MAP        = $00000
VRAM_TILES      = $04000
VRAM_HUDMAP     = $07000
VRAM_SPRITES    = $08000
VRAM_CHARSET    = $1F000         ; KERNAL's charset, uploaded at reset
VRAM_PSG        = $1F9C0
VRAM_PALETTE    = $1FA00
VRAM_SPRATTR    = $1FC00

; ---------------- KERNAL ----------------
GETIN           = $FFE4
CHROUT          = $FFD2
CLRCHN          = $FFCC
JOYSTICK_GET    = $FF56
RDTIM           = $FFDE
CINV            = $0314          ; IRQ vector (RAM)

; ---------------- helpers ----------------
; set VERA data port 0 address (+increment step in `inc1`: use VINC_*)
VINC_0   = $00
VINC_1   = $10
VINC_2   = $20
VINC_4   = $30
VINC_8   = $40
VINC_16  = $50
VINC_32  = $60
VINC_64  = $70
VINC_128 = $80
VINC_256 = $90

.macro VSET addr, inc
	stz VERA_CTRL
	lda #<(addr)
	sta VERA_ADDR_L
	lda #>(addr)
	sta VERA_ADDR_M
	lda #(((addr) >> 16) | inc)
	sta VERA_ADDR_H
.endmacro
