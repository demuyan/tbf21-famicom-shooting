; 05_fixed_speed.asm - 8.8 固定小数で位置と速度を管理し、移動スピードを細かく調整できる
;
; 固定小数 (8.8) の考え方:
;   16bit を 上位8bit=整数部、下位8bit=小数部 として扱う。
;   例えば $0180 は 1.5 を表す（$01 + $80/256 = 1 + 0.5 = 1.5）。
;   2 バイトぶんの足し算・引き算は「下位 → キャリー付きで上位」の順で行う。
;   画面に出すときは上位バイト（整数部）だけを OAM の座標に書き込む。
;
; 操作:
;   十字ボタン (ベタ入力) : 現在の速度で 8 方向に移動
;   A (ワンショット) : 速度を +1/4 px/frame
;   B (ワンショット) : 速度を -1/4 px/frame（0 未満にはならない）
;   SELECT           : 速度をデフォルト (1.0 px/frame) に戻す
;   START            : 位置を画面中央に戻す
;
; ビルド: asm6f 05_fixed_speed.asm 05_fixed_speed.nes

    .include "../lib/ines.inc"
    .include "../lib/fc.inc"

; ===== ゼロページ変数 =====
    .include "../lib/pad_vars.inc"
    .include "05_vars.inc"

; ===== 定数 =====
SPEED_INIT_HI = $01         ; 初期速度 = 1.0 px/frame
SPEED_INIT_LO = $00
SPEED_DELTA   = $40         ; A/B 1 押しごとの増減 = 1/4 px (= 64/256)

SP0_INIT_X_HI = $80         ; 初期位置 X = 128
SP0_INIT_Y_HI = $70         ; 初期位置 Y = 112

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
palloop:
    lda palette, x
    sta PPUDATA
    inx
    cpx #$20
    bne palloop
    rts

; ===== スプライト 0 と固定小数変数を初期化 =====
setup_sprite:
    ; 位置を画面中央へ（小数部は 0）
    lda #SP0_INIT_X_HI
    sta sp0_x_hi
    lda #SP0_INIT_Y_HI
    sta sp0_y_hi
    lda #$00
    sta sp0_x_lo
    sta sp0_y_lo

    ; 速度をデフォルトに
    lda #SPEED_INIT_LO
    sta speed_lo
    lda #SPEED_INIT_HI
    sta speed_hi

    ; OAM の初期値
    lda sp0_y_hi
    sta OAM_BUF+0           ; Y
    lda #$01
    sta OAM_BUF+1           ; タイル
    lda #$00
    sta OAM_BUF+2           ; 属性（パレット 0）
    lda sp0_x_hi
    sta OAM_BUF+3           ; X
    rts

; ===== PPU 描画 ON ・ NMI 有効化 =====
enable_ppu:
    lda #%10000000
    sta PPUCTRL
    lda #%00010100          ; スプライト表示 ON（左端 8 ピクセルも表示）
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
    jsr adjust_speed        ; A/B/SELECT/START で速度と位置を調整
    jsr update_position     ; 十字ボタンで固定小数位置を更新
    jsr sync_oam            ; 整数部を OAM に反映
    rti

; ===== A/B/SELECT/START で速度・位置を調整 =====
adjust_speed:
    ; --- A ワンショット → 速度 += SPEED_DELTA ---
    lda pad1_shot
    and #BTN_A
    beq skip_a
    clc
    lda speed_lo
    adc #SPEED_DELTA
    sta speed_lo
    lda speed_hi
    adc #$00                ; 下位からの桁上げを拾う
    sta speed_hi
skip_a:

    ; --- B ワンショット → 速度 -= SPEED_DELTA（0 未満にしない） ---
    lda pad1_shot
    and #BTN_B
    beq skip_b
    sec
    lda speed_lo
    sbc #SPEED_DELTA
    sta tmp_lo
    lda speed_hi
    sbc #$00
    bmi skip_b              ; 結果が負なら反映しない
    sta speed_hi
    lda tmp_lo
    sta speed_lo
skip_b:

    ; --- SELECT ワンショット → 速度リセット ---
    lda pad1_shot
    and #BTN_SEL
    beq skip_sel
    lda #SPEED_INIT_LO
    sta speed_lo
    lda #SPEED_INIT_HI
    sta speed_hi
skip_sel:

    ; --- START ワンショット → 位置リセット ---
    lda pad1_shot
    and #BTN_START
    beq skip_start
    lda #SP0_INIT_X_HI
    sta sp0_x_hi
    lda #SP0_INIT_Y_HI
    sta sp0_y_hi
    lda #$00
    sta sp0_x_lo
    sta sp0_y_lo
skip_start:
    rts

; ===== 十字ボタン (ベタ入力) で固定小数位置を更新 =====
; pos = pos ± speed  （16bit の加減算）
update_position:
    ; UP: Y -= speed
    lda pad1_raw
    and #BTN_UP
    beq skip_up
    sec
    lda sp0_y_lo
    sbc speed_lo
    sta sp0_y_lo
    lda sp0_y_hi
    sbc speed_hi
    sta sp0_y_hi
skip_up:

    ; DOWN: Y += speed
    lda pad1_raw
    and #BTN_DOWN
    beq skip_dn
    clc
    lda sp0_y_lo
    adc speed_lo
    sta sp0_y_lo
    lda sp0_y_hi
    adc speed_hi
    sta sp0_y_hi
skip_dn:

    ; LEFT: X -= speed
    lda pad1_raw
    and #BTN_LEFT
    beq skip_lt
    sec
    lda sp0_x_lo
    sbc speed_lo
    sta sp0_x_lo
    lda sp0_x_hi
    sbc speed_hi
    sta sp0_x_hi
skip_lt:

    ; RIGHT: X += speed
    lda pad1_raw
    and #BTN_RIGHT
    beq skip_rt
    clc
    lda sp0_x_lo
    adc speed_lo
    sta sp0_x_lo
    lda sp0_x_hi
    adc speed_hi
    sta sp0_x_hi
skip_rt:
    rts

; ===== 固定小数の整数部だけを OAM に反映 =====
sync_oam:
    lda sp0_y_hi
    sta OAM_BUF+0
    lda sp0_x_hi
    sta OAM_BUF+3
    rts

; ===== PAD 読み取り（04 と同じ） =====
; ボタンビット並び: bit7=A, bit6=B, bit5=SELECT, bit4=START,
;                   bit3=UP, bit2=DOWN, bit1=LEFT, bit0=RIGHT
read_pads:
    lda pad1_raw
    sta pad1_prev
    lda pad2_raw
    sta pad2_prev

    lda #$01
    sta JOYPAD1
    lda #$00
    sta JOYPAD1

    ldx #$08
pad_loop:
    lda JOYPAD1
    lsr a
    rol pad1_raw
    lda JOYPAD2
    lsr a
    rol pad2_raw
    dex
    bne pad_loop

    lda pad1_prev
    eor #$ff
    and pad1_raw
    sta pad1_shot

    lda pad2_prev
    eor #$ff
    and pad2_raw
    sta pad2_shot
    rts

irq:
    rti

; ===== パレット / 割り込みベクタ / CHR-ROM =====
    .include "05_data.asm"
