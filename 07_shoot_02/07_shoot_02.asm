; 07_shoot_02.asm - 06 をベースに、A ボタンで自機弾を発射する
;
;   操作:
;     十字ボタン : 自機を移動
;     A 連打: 弾を発射（押した瞬間に 1 発、上方向へ飛ぶ）
;
;   弾の管理: BULLET_MAX 個の固定配列（並列配列スタイル）
;     bullet_active[i] : $00=未使用 / $80=使用中
;     bullet_x_hi[i]   : 中心 X
;     bullet_y_hi[i]   : 中心 Y
;     A 押下時に未使用スロットを 1 個だけ確保し、自機中心位置から発射する。
;     毎フレーム y -= BULLET_SPEED で上昇させ、画面外に出たら未使用に戻す。
;
;   OAM レイアウト:
;     OAM_BUF + 0..15  : 自機 (4 スプライト)
;     OAM_BUF + 16..   : 弾 (1 スプライト × BULLET_MAX)
;
; ビルド: asm6f 07_shoot_02.asm 07_shoot_02.nes

    .include "../lib/ines.inc"
    .include "../lib/fc.inc"
    .include "../lib/macros.inc"

; ===== ゼロページ変数 =====
    .include "07_vars.inc"

; ===== 定数 =====
SPEED_INIT_HI = $01         ; 自機の移動速度 = 1.0 px/frame
SPEED_INIT_LO = $00

INIT_X = 128                ; 自機の初期中心 X
INIT_Y = 184                ; 自機の初期中心 Y
PLAYER_X_MIN = 8             ; 自機の中心 X の範囲（16 × 16 なので左右に 8 ピクセルずつ）
PLAYER_X_MAX = 247
PLAYER_Y_MIN = 16            ; 自機の中心 Y の範囲（上下の端 8 ピクセルは避ける）
PLAYER_Y_MAX = 223

BULLET_SPEED  = 4           ; 弾の速度（px/frame、整数）
BULLET_TILE   = $06         ; 弾のタイル番号
BULLET_ATTR   = $01         ; 弾の属性（パレット 1 を使う）
BULLET_OFF_TOP = 8          ; この Y 未満になったら画面外と判定して消す

; OAM テンプレートのバイトオフセット
TMPL_TILE = 0
TMPL_DX   = 1
TMPL_DY   = 2
TMPL_ATTR = 3
TMPL_SIZE = 4

; OAM_BUF 上の自機・弾のオフセット
SHIP_SPR_COUNT = 4
SHIP_OAM_SIZE  = SHIP_SPR_COUNT * TMPL_SIZE
BULLET_OAM_BASE = OAM_BUF + SHIP_OAM_SIZE       ; 弾用 OAM 領域の先頭

; ===== PRG-ROM =====
    .base $c000

; ===== エントリポイント =====
reset:
    sei
    cld
    ldx #$ff
    txs
    jsr init_fc
    jsr init_app

forever:
    jmp forever

    .include "../lib/fc_init.asm"

; ===== アプリ固有の初期化 =====
init_app:
    jsr load_palette
    jsr setup_sprite
    jsr setup_bullets
    jsr enable_ppu
    rts

; ===== パレット転送 =====
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

; ===== 自機の初期化 =====
setup_sprite:
    lda #INIT_X
    sta sp0_x_hi
    lda #INIT_Y
    sta sp0_y_hi
    lda #$00
    sta sp0_x_lo
    sta sp0_y_lo

    lda #SPEED_INIT_LO
    sta speed_lo
    lda #SPEED_INIT_HI
    sta speed_hi

    jsr sync_oam
    rts

; ===== 弾プールの初期化 =====
;   active を全部 0、OAM 上の Y を画面外 ($FE) にして非表示にしておく
setup_bullets:
    ldx #0
@loop:
    lda #$fe                            ; 非表示（OAM Y）
    sta BULLET_OAM_BASE+OAM_Y, x        ; bullet i の OAM_Y のみ初期化
    txa
    clc
    adc #TMPL_SIZE                       ; 1 スプライト = 4 バイト進める
    tax
    cpx #(BULLET_MAX * TMPL_SIZE)
    bne @loop

    ; タイル番号・属性と active フラグは、弾 1 発ずつ進むこのループで書く
    ldx #0
    ldy #0
@init_tile:
    lda #$00
    sta bullet_active, y                ; active = 0（弾ごとに 1 バイト）
    lda #BULLET_TILE
    sta BULLET_OAM_BASE+OAM_TILE, x
    lda #BULLET_ATTR
    sta BULLET_OAM_BASE+OAM_ATTR, x
    txa
    clc
    adc #TMPL_SIZE
    tax
    iny
    cpy #BULLET_MAX
    bne @init_tile
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
    jsr update_position     ; 十字ボタンで自機を動かす
    jsr try_spawn_bullet    ; A 押下で弾を発射
    jsr update_bullets      ; 弾の移動・消滅処理
    jsr sync_oam            ; 自機 OAM を更新
    jsr sync_bullets_oam    ; 弾 OAM を更新
    rti

; ===== 十字ボタンで自機の位置更新 =====
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

; ===== A ワンショットで弾を 1 発発射 =====
;   未使用の弾スロットを線形探索。見つかれば自機中心の座標で生成する。
try_spawn_bullet:
    lda pad1_shot
    and #BTN_A
    beq @done                   ; A が今フレーム押されてなければ何もしない

    ldx #0
@find:
    lda bullet_active, x
    beq @spawn                  ; 0 = 未使用 → ここに割り当てる
    inx
    cpx #BULLET_MAX
    bne @find
    rts                         ; 全部使用中：諦める

@spawn:
    lda #$80                    ; 使用中フラグ
    sta bullet_active, x
    lda sp0_x_hi
    sta bullet_x_hi, x
    lda sp0_y_hi
    sta bullet_y_hi, x          ; 自機中心から発射
@done:
    rts

; ===== 弾の移動と消滅 =====
;   active な弾を上に動かし、画面外に出たら deactivate する。
update_bullets:
    ldx #0
@loop:
    lda bullet_active, x
    beq @next                   ; 未使用はスキップ

    ; y -= BULLET_SPEED
    lda bullet_y_hi, x
    sec
    sbc #BULLET_SPEED
    sta bullet_y_hi, x

    ; 画面外なら消す
    cmp #BULLET_OFF_TOP
    bcs @next                   ; y >= BULLET_OFF_TOP なら継続
    ; ここまで来ると画面外
    lda #$00
    sta bullet_active, x
@next:
    inx
    cpx #BULLET_MAX
    bne @loop
    rts

; ===== 弾の OAM 反映 =====
;   各スロットの状態を OAM_BUF の弾エリアに書き込む。
;   bullet_*_hi は弾の「中心」座標。8x8 スプライトの OAM は左上基準なので、
;   描画時に -4 して中心ぞろえに変換する。
;   非アクティブな弾は Y=$FE で画面外に追いやる。
BULLET_HALF = 4                  ; 8x8 弾の半径
sync_bullets_oam:
    ldx #0                      ; 弾配列のインデックス
    ldy #0                      ; OAM_BUF 上の弾エリアのバイトオフセット
@loop:
    lda bullet_active, x
    bne @alive
    ; 非アクティブ：Y を画面外に
    lda #$fe
    sta BULLET_OAM_BASE+OAM_Y, y
    jmp @advance
@alive:
    ; OAM Y = center_y - 4
    lda bullet_y_hi, x
    sec
    sbc #BULLET_HALF
    sta BULLET_OAM_BASE+OAM_Y, y
    ; OAM X = center_x - 4
    lda bullet_x_hi, x
    sec
    sbc #BULLET_HALF
    sta BULLET_OAM_BASE+OAM_X, y
@advance:
    inx
    tya
    clc
    adc #TMPL_SIZE
    tay
    cpx #BULLET_MAX
    bne @loop
    rts

; ===== 自機の OAM テンプレート =====
ship_oam_template:
    .db $02, -8, -8, $00        ; sprite 0: top-left
    .db $03,  0, -8, $00        ; sprite 1: top-right
    .db $04, -8,  0, $00        ; sprite 2: bottom-left
    .db $05,  0,  0, $00        ; sprite 3: bottom-right

; ===== 自機 OAM の展開 =====
sync_oam:
    ldx #0
@loop:
    lda ship_oam_template+TMPL_TILE, x
    sta OAM_BUF+OAM_TILE, x
    lda sp0_x_hi
    clc
    adc ship_oam_template+TMPL_DX, x
    sta OAM_BUF+OAM_X, x
    lda sp0_y_hi
    clc
    adc ship_oam_template+TMPL_DY, x
    sta OAM_BUF+OAM_Y, x
    lda ship_oam_template+TMPL_ATTR, x
    sta OAM_BUF+OAM_ATTR, x
    txa
    clc
    adc #TMPL_SIZE
    tax
    cpx #SHIP_OAM_SIZE
    bne @loop
    rts

; ===== 1P コントローラーの読み取り =====
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
    .include "07_data.asm"
