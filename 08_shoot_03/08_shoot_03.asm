; 08_shoot_03.asm - 07 + 敵キャラ (16x16 × 4 体) をサイン波移動で表示
;
;   操作:
;     十字ボタン : 自機を移動
;     A 連打: 弾を発射
;
;   敵: 4 体が画面上から下へ降りてくる。X 座標は sin 波で左右に揺れて画面一杯に動く。
;       4 体の位相 (phase) はすべて 0 から始め、登場の待ち時間 (enemy_delay) をずらして隊列にする。
;       全 4 体が画面下に消えたら、再度上から降ってくる。
;
;   OAM レイアウト:
;     OAM_BUF +  0..+15  : 自機 (4 スプライト)
;     OAM_BUF + 16..+47  : 弾   (8 スプライト × 4 バイト)
;     OAM_BUF + 48..+111 : 敵   (4 体 × 4 スプライト × 4 バイト)
;
; ビルド: asm6f 08_shoot_03.asm 08_shoot_03.nes

    .include "../lib/ines.inc"
    .include "../lib/fc.inc"
    .include "../lib/macros.inc"

; ===== ゼロページ変数 =====
    .include "08_vars.inc"

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

; OAM_BUF 上の自機・弾・敵のオフセット
SHIP_SPR_COUNT  = 4
SHIP_OAM_SIZE   = SHIP_SPR_COUNT * TMPL_SIZE             ; = 16
BULLET_OAM_BASE = OAM_BUF + SHIP_OAM_SIZE                ; 弾用 OAM 先頭
BULLET_OAM_SIZE = BULLET_MAX * TMPL_SIZE                 ; = 32
ENEMY_OAM_BASE  = BULLET_OAM_BASE + BULLET_OAM_SIZE      ; 敵用 OAM 先頭

; ===== 敵関連 =====
ENEMY_COUNT       = 4
ENEMY_SPR_PER     = 4                       ; 1 体あたり 4 スプライト (16x16)
ENEMY_BYTES_PER   = ENEMY_SPR_PER * TMPL_SIZE
ENEMY_INIT_Y      = 8                       ; 中心 Y。-8 すると OAM Y = 0 で画面最上端から登場
ENEMY_OFF_BOTTOM  = 240                     ; 中心 Y がこの値以上で「画面外」
ENEMY_SPEED       = 1                       ; 下方向に進む速度 (px/frame)
ENEMY_CENTER_X    = 128                     ; サイン波の中心 X
ENEMY_TILE_TL     = $07
ENEMY_TILE_TR     = $08
ENEMY_TILE_BL     = $09
ENEMY_TILE_BR     = $0A
ENEMY_ATTR        = $02                     ; パレット 2 (赤／金／灰)
ENEMY_SPAWN_GAP   = 8                       ; 敵同士の登場フレーム差（8 ピクセル間隔。1 走査線 8 枚を超えないように）

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
    jsr setup_enemies
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
    jsr update_enemies      ; 敵の移動／復活処理
    jsr sync_oam            ; 自機 OAM を更新
    jsr sync_bullets_oam    ; 弾 OAM を更新
    jsr sync_enemies_oam    ; 敵 OAM を更新
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

; ===== 敵の OAM テンプレート =====
;   1 体 = 16x16 = 4 スプライト。バイト並びは「タイル, dx, dy, 属性」。
enemy_oam_template:
    .db ENEMY_TILE_TL, -8, -8, ENEMY_ATTR
    .db ENEMY_TILE_TR,  0, -8, ENEMY_ATTR
    .db ENEMY_TILE_BL, -8,  0, ENEMY_ATTR
    .db ENEMY_TILE_BR,  0,  0, ENEMY_ATTR

; ===== 敵の初期化 =====
;   全 4 体は同じ初期座標・同じ phase で生成し、enemy_delay で
;   ENEMY_SPAWN_GAP フレームずつ登場をずらす。phase も同じなので、
;   先頭が描いた軌跡を 8/16/24 フレーム遅れて 2 番目以降がなぞる「縦列」になる。
setup_enemies:
    lda #ENEMY_INIT_Y
    sta enemy_y_hi+0
    sta enemy_y_hi+1
    sta enemy_y_hi+2
    sta enemy_y_hi+3

    lda #0
    sta enemy_phase+0
    sta enemy_phase+1
    sta enemy_phase+2
    sta enemy_phase+3

    sta enemy_delay+0           ; A = 0、先頭はすぐ動き出す
    lda #(1 * ENEMY_SPAWN_GAP)
    sta enemy_delay+1
    lda #(2 * ENEMY_SPAWN_GAP)
    sta enemy_delay+2
    lda #(3 * ENEMY_SPAWN_GAP)
    sta enemy_delay+3
    rts

; ===== 敵の更新 =====
;   delay > 0 の敵は登場待ち。delay を 1 ずつ減らすだけ。
;   delay が 0 になった敵だけ y += ENEMY_SPEED と phase += 1 を行う。
;   全員が画面下に消えたら setup_enemies で再配置。
update_enemies:
    ldx #0
@loop:
    lda enemy_delay, x
    beq @move
    dec enemy_delay, x          ; まだ待機中
    jmp @next
@move:
    lda enemy_y_hi, x
    cmp #ENEMY_OFF_BOTTOM
    bcs @next                   ; 画面下に出た敵はそこで止め、全員がそろうのを待つ
    clc
    adc #ENEMY_SPEED
    sta enemy_y_hi, x
    inc enemy_phase, x
@next:
    inx
    cpx #ENEMY_COUNT
    bne @loop

    ; 全員 y >= ENEMY_OFF_BOTTOM か？ 1 体でも画面内なら何もしない
    lda enemy_y_hi+0
    cmp #ENEMY_OFF_BOTTOM
    bcc @done
    lda enemy_y_hi+1
    cmp #ENEMY_OFF_BOTTOM
    bcc @done
    lda enemy_y_hi+2
    cmp #ENEMY_OFF_BOTTOM
    bcc @done
    lda enemy_y_hi+3
    cmp #ENEMY_OFF_BOTTOM
    bcc @done
    jsr setup_enemies       ; 全員画面外 → 再登場
@done:
    rts

; ===== phase から正弦波の X 座標を計算 =====
;   入力 : X = enemy 添字
;   出力 : A = 中心 X (16..240)、Y は破壊
;   sin_half は半波 (0..63 → 0..112) の片側テーブル。phase の bit6 で正負を選ぶ。
get_sine_x:
    lda enemy_phase, x
    and #$7F                ; 周期 128
    cmp #$40
    bcc @pos_half
    sec
    sbc #$40                ; phase 64..127 → 0..63
    tay
    lda #ENEMY_CENTER_X
    sec
    sbc sin_half, y         ; 負の半波: 128 - table
    rts
@pos_half:
    tay
    lda #ENEMY_CENTER_X
    clc
    adc sin_half, y         ; 正の半波: 128 + table
    rts

; ===== 敵 OAM の展開 =====
;   外側ループ: 4 体の敵を巡回（X レジスタ）
;   内側ループ: 1 体あたり 4 スプライトをテンプレートから書き出す（Y レジスタ）
;   X と Y は両方使うので、一時保存に enemy_idx_tmp / oam_idx_tmp を利用する。
sync_enemies_oam:
    lda #(ENEMY_OAM_BASE - OAM_BUF)
    sta oam_idx_tmp                 ; OAM_BUF 内のバイト添字を持つ
    ldx #0
@enemy:
    stx enemy_idx_tmp

    lda enemy_delay, x
    bne @hide                       ; 登場待ち → 4 スプライトを画面外に
    lda enemy_y_hi, x
    cmp #ENEMY_OFF_BOTTOM
    bcs @hide                       ; 画面下に出た敵 → 同じく画面外に

    ; --- 通常表示 ---
    jsr get_sine_x                  ; A = 中心 X
    sta cx_tmp
    lda enemy_y_hi, x
    sta cy_tmp                      ; 中心 Y

    ldy #0                          ; テンプレートのバイト添字
@sprite:
    ldx oam_idx_tmp                 ; OAM_BUF の書き込み位置を X に持ち替え

    ; OAM_Y = cy + dy
    lda cy_tmp
    clc
    adc enemy_oam_template+TMPL_DY, y
    sta OAM_BUF+OAM_Y, x

    ; OAM_TILE
    lda enemy_oam_template+TMPL_TILE, y
    sta OAM_BUF+OAM_TILE, x

    ; OAM_ATTR
    lda enemy_oam_template+TMPL_ATTR, y
    sta OAM_BUF+OAM_ATTR, x

    ; OAM_X = cx + dx
    lda cx_tmp
    clc
    adc enemy_oam_template+TMPL_DX, y
    sta OAM_BUF+OAM_X, x

    ; OAM 添字を 4 進める
    txa
    clc
    adc #TMPL_SIZE
    sta oam_idx_tmp

    ; テンプレート添字を 4 進める
    iny
    iny
    iny
    iny
    cpy #(ENEMY_SPR_PER * TMPL_SIZE)
    bne @sprite
    jmp @next_enemy

@hide:
    ; 4 スプライトの Y を $FE にして画面外に追いやる
    ldx oam_idx_tmp
    ldy #ENEMY_SPR_PER
@hide_loop:
    lda #$fe
    sta OAM_BUF+OAM_Y, x
    txa
    clc
    adc #TMPL_SIZE
    tax
    dey
    bne @hide_loop
    stx oam_idx_tmp

@next_enemy:
    ldx enemy_idx_tmp
    inx
    cpx #ENEMY_COUNT
    bne @enemy
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
    .include "08_data.asm"
