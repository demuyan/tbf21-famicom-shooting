; 06_shoot_01.asm - 縦シューティングの自機（2x2 スプライト = 16x16）を十字ボタンで動かす
;
; 固定小数 (8.8) で位置を扱い、十字ボタンで一定速度で 8 方向に移動する。
;   OAM レイアウト:
;     sprite 0 = top-left    (OAM_BUF+0..+3)
;     sprite 1 = top-right   (OAM_BUF+4..+7)
;     sprite 2 = bottom-left (OAM_BUF+8..+11)
;     sprite 3 = bottom-right(OAM_BUF+12..+15)
;   sp0_x_hi/sp0_y_hi は「機体中心」基準の座標。描画時に sync_oam が
;   左上 = center - 8、右下 = center として 4 枚のスプライトに展開する。
;   当たり判定が中心基準で書けるのでシューティング向けの計算が楽になる。
;
; 操作:
;   十字ボタン (ベタ入力) : 一定速度で 8 方向に移動
;
; ビルド: asm6f 06_shoot_01.asm 06_shoot_01.nes

    .include "../lib/ines.inc"
    .include "../lib/fc.inc"
    .include "../lib/macros.inc"

; ===== ゼロページ変数 =====
    .include "06_vars.inc"

; ===== 定数 =====
SPEED_INIT_HI = $01         ; 移動速度 = 1.0 px/frame
SPEED_INIT_LO = $00

INIT_X = 128                ; 初期位置 中心 X（画面中央）
INIT_Y = 184                ; 初期位置 中心 Y（画面下寄り）
PLAYER_X_MIN = 8             ; 自機の中心 X の範囲（16 × 16 なので左右に 8 ピクセルずつ）
PLAYER_X_MAX = 247
PLAYER_Y_MIN = 16            ; 自機の中心 Y の範囲（上下の端 8 ピクセルは避ける）
PLAYER_Y_MAX = 223

; 自機の OAM テンプレートのバイトオフセット
TMPL_TILE = 0
TMPL_DX   = 1
TMPL_DY   = 2
TMPL_ATTR = 3
TMPL_SIZE = 4               ; 1 スプライトあたり 4 バイト

; ===== PRG-ROM (16KB, $C000-$FFFF にマップ) =====
    .base $c000

; ===== エントリポイント =====
reset:
    sei
    cld
    ldx #$ff
    txs                     ; スタックポインタ = $FF（必ず jsr より前に）
    jsr init_fc
    jsr init_app

forever:
    jmp forever

; ===== ファミコン共通の初期化（使い回し可能） =====
    .include "../lib/fc_init.asm"

; ===== アプリ固有の初期化 =====
init_app:
    jsr load_palette
    jsr setup_sprite
    jsr enable_ppu
    rts

; ===== パレットを PPU ($3F00-$3F1F) に転送 =====
load_palette:
    lda #$3f
    sta PPUADDR
    lda #$00
    sta PPUADDR
    ldx #$00
@loop:
    lda palette, x
    sta PPUDATA
    inx
    cpx #$20
    bne @loop
    rts

; ===== 自機の固定小数変数を初期化（OAM は sync_oam が毎フレーム埋める）=====
setup_sprite:
    ; 位置を初期座標（機体中心）へ（小数部は 0）
    lda #INIT_X
    sta sp0_x_hi
    lda #INIT_Y
    sta sp0_y_hi
    lda #$00
    sta sp0_x_lo
    sta sp0_y_lo

    ; 速度をデフォルトに
    lda #SPEED_INIT_LO
    sta speed_lo
    lda #SPEED_INIT_HI
    sta speed_hi

    jsr sync_oam            ; 初期状態を OAM に反映
    rts

; ===== PPU 描画 ON ・ NMI 有効化 =====
enable_ppu:
    lda #PPUCTRL_NMI
    sta PPUCTRL
    lda #(PPUMASK_SHOW_SPR | PPUMASK_SHOW_SPR_LEFT)   ; 左端 8 ピクセルも表示
    sta PPUMASK
    rts

; ===== NMI =====
nmi:
    ; OAM DMA
    lda #$00
    sta OAMADDR
    lda #>OAM_BUF
    sta OAMDMA

    jsr read_pads
    jsr update_position     ; 十字ボタンで固定小数位置を更新
    jsr sync_oam            ; 整数部を OAM に反映
    rti

; ===== 十字ボタン (ベタ入力) で固定小数位置を更新 =====
; pos = pos ± speed  （ADD16/SUB16 マクロで 16bit 加減算）
update_position:
    lda pad1_raw
    and #BTN_UP
    beq @skip_up
    SUB16 sp0_y_lo, sp0_y_hi, speed_lo, speed_hi
@skip_up:
    lda pad1_raw
    and #BTN_DOWN
    beq @skip_dn
    ADD16 sp0_y_lo, sp0_y_hi, speed_lo, speed_hi
@skip_dn:
    lda pad1_raw
    and #BTN_LEFT
    beq @skip_lt
    SUB16 sp0_x_lo, sp0_x_hi, speed_lo, speed_hi
@skip_lt:
    lda pad1_raw
    and #BTN_RIGHT
    beq @skip_rt
    ADD16 sp0_x_lo, sp0_x_hi, speed_lo, speed_hi
@skip_rt:
    ; 中心座標を画面内に収める（左右・上下の反対側へ回り込まないように）
    lda sp0_x_hi
    cmp #PLAYER_X_MIN
    bcs @x_min_ok               ; X >= 最小値なら OK
    lda #PLAYER_X_MIN
    sta sp0_x_hi
@x_min_ok:
    cmp #(PLAYER_X_MAX + 1)
    bcc @x_max_ok               ; X <= 最大値なら OK
    lda #PLAYER_X_MAX
    sta sp0_x_hi
@x_max_ok:
    lda sp0_y_hi
    cmp #PLAYER_Y_MIN
    bcs @y_min_ok
    lda #PLAYER_Y_MIN
    sta sp0_y_hi
@y_min_ok:
    cmp #(PLAYER_Y_MAX + 1)
    bcc @y_max_ok
    lda #PLAYER_Y_MAX
    sta sp0_y_hi
@y_max_ok:
    rts

; ===== 自機の OAM テンプレート =====
; 1 スプライトあたり 4 バイト、並びは「タイル番号, dx, dy, 属性」。
; dx/dy は機体中心からの相対座標（符号付き 8bit）。
; OAM 側のバイト順 (Y, tile, attr, X) とは違うので、sync_oam で並び替えて書き込む。
; 形を変えたい／スプライトを増やしたい時はこのテーブルを書き換えるだけで済む。
ship_oam_template:
    .db $02, -8, -8, $00        ; sprite 0: top-left
    .db $03,  0, -8, $00        ; sprite 1: top-right
    .db $04, -8,  0, $00        ; sprite 2: bottom-left
    .db $05,  0,  0, $00        ; sprite 3: bottom-right
SHIP_SPR_COUNT = 4
SHIP_OAM_SIZE  = SHIP_SPR_COUNT * TMPL_SIZE

; ===== テンプレートを OAM に展開 =====
; X レジスタは「現在処理中のスプライト先頭バイト」の添字として、
; テンプレートと OAM_BUF の両方に使い回す（どちらも 1 スプライト 4 バイトなので同じ添字で良い）。
; テンプレート順（tile → dx → dy → attr）にそのまま処理する。
;   符号付きオフセット (dy/dx) の加算は adc の結果が 8bit に丸まる性質で自然に処理される
;   （例: $B8 + $F8 = $1B0 → A = $B0、キャリー破棄で「184 - 8 = 176」）。
sync_oam:
    ldx #0
@loop:
    ; tile: template[+TMPL_TILE] → OAM_BUF[+OAM_TILE]
    lda ship_oam_template+TMPL_TILE, x
    sta OAM_BUF+OAM_TILE, x

    ; X 座標: center_x + dx → OAM_BUF[+OAM_X]
    lda sp0_x_hi
    clc
    adc ship_oam_template+TMPL_DX, x
    sta OAM_BUF+OAM_X, x

    ; Y 座標: center_y + dy → OAM_BUF[+OAM_Y]
    lda sp0_y_hi
    clc
    adc ship_oam_template+TMPL_DY, x
    sta OAM_BUF+OAM_Y, x

    ; 属性: template[+TMPL_ATTR] → OAM_BUF[+OAM_ATTR]
    lda ship_oam_template+TMPL_ATTR, x
    sta OAM_BUF+OAM_ATTR, x

    ; 次のスプライトへ（4 バイト進める）
    txa
    clc
    adc #TMPL_SIZE
    tax
    cpx #SHIP_OAM_SIZE
    bne @loop
    rts

; ===== 1P コントローラーの読み取り =====
; ボタンビット並び: bit7=A, bit6=B, bit5=SELECT, bit4=START,
;                   bit3=UP, bit2=DOWN, bit1=LEFT, bit0=RIGHT
read_pads:
    lda pad1_raw
    sta pad1_prev

    lda #$01
    sta JOYPAD1
    lda #$00
    sta JOYPAD1

    ldx #$08
@loop:
    lda JOYPAD1
    lsr a
    rol pad1_raw
    dex
    bne @loop

    lda pad1_prev
    eor #$ff
    and pad1_raw
    sta pad1_shot
    rts

irq:
    rti

; ===== パレット / 割り込みベクタ / CHR-ROM =====
    .include "06_data.asm"
