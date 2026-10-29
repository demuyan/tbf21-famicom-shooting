; fc.inc - ファミコンのハードウェアレジスタ定義（共通）

; ===== PPU レジスタ =====
PPUCTRL   = $2000
PPUMASK   = $2001
PPUSTATUS = $2002
OAMADDR   = $2003
PPUSCROLL = $2005
PPUADDR   = $2006
PPUDATA   = $2007

; ===== APU / DMA レジスタ =====
DMCFREQ   = $4010
OAMDMA    = $4014
APUFRAME  = $4017

; ===== I/O レジスタ =====
JOYPAD1   = $4016
JOYPAD2   = $4017   ; 読み出し時。書き込み時は APUFRAME と同アドレス

; ===== ボタンビット（read_pads 後の pad*_raw / pad*_shot の並び） =====
BTN_A     = %10000000
BTN_B     = %01000000
BTN_SEL   = %00100000
BTN_START = %00010000
BTN_UP    = %00001000
BTN_DOWN  = %00000100
BTN_LEFT  = %00000010
BTN_RIGHT = %00000001

; ===== PPUCTRL ($2000) のビット =====
PPUCTRL_NMI       = %10000000   ; bit7: VBlank で NMI を発生
PPUCTRL_SPR_8X16  = %00100000   ; bit5: スプライトを 8x16 モード
PPUCTRL_BG_PT1    = %00010000   ; bit4: BG パターンテーブルを $1000 側に
PPUCTRL_SPR_PT1   = %00001000   ; bit3: スプライトパターンテーブルを $1000 側に

; ===== PPUMASK ($2001) のビット =====
PPUMASK_SHOW_BG   = %00001000   ; bit3: BG 描画 ON
PPUMASK_SHOW_SPR  = %00010000   ; bit4: スプライト描画 ON
PPUMASK_SHOW_BG_LEFT  = %00000010   ; bit1: 画面左端 8 ピクセルにも BG を描く
PPUMASK_SHOW_SPR_LEFT = %00000100   ; bit2: 画面左端 8 ピクセルにもスプライトを描く

; ===== OAM 1 スプライトのバイトオフセット =====
OAM_Y     = 0
OAM_TILE  = 1
OAM_ATTR  = 2
OAM_X     = 3

; ===== RAM =====
OAM_BUF   = $0200
