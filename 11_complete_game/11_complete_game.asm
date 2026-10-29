; 11_complete_game.asm - 10 にステートマシンと残機を追加して「ゲームとして完成」させる
;
;   操作:
;     TITLE      : START でゲーム開始
;     PLAY       : 十字ボタンで自機移動 / A で発射
;     GAME_OVER  : START でタイトルへ戻る
;
;   ゲームの状態 (game_state):
;     0 = TITLE    : 「SHOOTING」と「PRESS START」を表示。START で PLAY へ
;     1 = PLAY     : 10 章までのゲームロジック。撃墜のたびに lives -1
;                    残機があれば RESPAWN_DELAY フレーム後にリスポーン、
;                    残機 0 なら GAME_OVER へ
;     2 = GAME_OVER: 「GAME OVER」「PRESS START」を表示。START で TITLE へ
;
;   ステートマシンの実装:
;     - NMI 内で game_state を見て title_update / play_update / game_over_update に分岐
;     - 状態遷移時は state_changed の bit 7 を立てる
;       → 次の NMI 冒頭 (VBlank 中) に redraw_bg_for_state で BG を書き換える
;
;   残機システム:
;     - lives = LIVES_INIT (=3) でスタート
;     - 撃墜時 (check_player_vs_enemy のヒット内) で dec lives + respawn_timer = 60
;     - PLAY 中、player_active = 0 のあいだは respawn_timer をデクリメント
;       タイマー満了で lives > 0 なら setup_sprite で復活、lives = 0 なら GAME_OVER
;
; ビルド: asm6f 11_complete_game.asm 11_complete_game.nes
;
; 読むときの注意（本文では詳しく触れていない点）
;   - #$10 は「値 $10」、$10 は「$10 番地の中身」。# を付け忘れてもエラーにならず、
;     別の値を読んで動いてしまうので、挙動がおかしいときはまずここを疑う。
;   - @loop のような @ 付きのラベルは、次の普通のラベル（@ の無いラベル）までの
;     範囲でだけ有効。そのため @loop / @done などをルーチンごとに使い回している。

    ; .include は、指定したファイルの中身をこの位置に貼り付ける（Python の import
    ; と違い、テキストをそのまま展開する）。ines.inc は .nes ファイル先頭の 16 バイトの
    ; ヘッダ、fc.inc はハードウェアのレジスタ番地の定数、macros.inc は 16 bit 演算のマクロ。
    .include "../lib/ines.inc"
    .include "../lib/fc.inc"
    .include "../lib/macros.inc"

; ===== ゼロページ変数 =====
;   変数の置き場所（番地）は、11_vars.inc で 1 つずつ手で決めている。
    .include "11_vars.inc"

; ===== 定数 =====
;   数値に名前を付けておくと、コードの意味が読めるうえ、調整するときに 1 か所を
;   直せば済む。どれもアセンブル時に数値へ置き換わり、メモリは使わない。
SPEED_INIT_HI = $01         ; 自機の移動速度 = 1.0 px/frame
SPEED_INIT_LO = $00         ;   (8.8 固定小数: HI が整数部、LO が 1/256 単位の小数部)

INIT_X = 128                ; 自機の初期中心 X
INIT_Y = 184                ; 自機の初期中心 Y
PLAYER_X_MIN = 8             ; 自機の中心 X の範囲（16 × 16 なので左右に 8 ピクセルずつ）
PLAYER_X_MAX = 247
PLAYER_Y_MIN = 16            ; 自機の中心 Y の範囲（上下の端 8 ピクセルは避ける）
PLAYER_Y_MAX = 223
PPUMASK_DRAW_ON = PPUMASK_SHOW_BG | PPUMASK_SHOW_SPR | PPUMASK_SHOW_BG_LEFT | PPUMASK_SHOW_SPR_LEFT
                             ; 描画 ON の値（BG とスプライト、左端 8 ピクセルも表示）

BULLET_SPEED  = 4           ; 弾の速度（px/frame、整数）
BULLET_TILE   = $06         ; 弾のタイル番号
BULLET_ATTR   = $01         ; 弾の属性（パレット 1 を使う）
BULLET_OFF_TOP = 8          ; この Y 未満になったら画面外と判定して消す

; OAM テンプレートのバイトオフセット
;   テンプレートは 1 スプライト 4 バイト（タイル, dx, dy, 属性）の並び。
;   構造体のフィールド名の代わりに、先頭から何バイト目かに名前を付けている。
TMPL_TILE = 0
TMPL_DX   = 1
TMPL_DY   = 2
TMPL_ATTR = 3
TMPL_SIZE = 4

; OAM_BUF 上の自機・弾・敵のオフセット
;   OAM_BUF（$0200〜$02FF）は 4 バイト × 64 スプライト分の表示データ。
;   どのスプライト番号を誰が使うかを、先頭から 自機 4 → 弾 8 → 敵（4 × ENEMY_COUNT）の順に固定で
;   割り当てる。動的に確保する仕組みは無いので、置き場所は最初に決め打ちする。
SHIP_SPR_COUNT  = 4
SHIP_OAM_SIZE   = SHIP_SPR_COUNT * TMPL_SIZE             ; = 16
BULLET_OAM_BASE = OAM_BUF + SHIP_OAM_SIZE                ; 弾用 OAM 先頭
BULLET_OAM_SIZE = BULLET_MAX * TMPL_SIZE                 ; = 32
ENEMY_OAM_BASE  = BULLET_OAM_BASE + BULLET_OAM_SIZE      ; 敵用 OAM 先頭

; ===== 敵関連 =====
;   敵の数 ENEMY_COUNT は 11_vars.inc で決める（配列の大きさにも使うため）。
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

; ENEMY_COUNT を増やしすぎたときに、アセンブルの時点で気づけるようにする。
;   .if の条件が成り立つと .error のメッセージを出してアセンブルが止まる。
;   OAM_BUF は 64 スプライト分しかないので、自機・弾の残りが敵に使える上限
;   （(64 - 4 - 8) / 4 = 13 体）。
OAM_SPR_TOTAL     = 64
ENEMY_COUNT_MAX   = (OAM_SPR_TOTAL - SHIP_SPR_COUNT - BULLET_MAX) / ENEMY_SPR_PER
    .if ENEMY_COUNT > ENEMY_COUNT_MAX
    .error "ENEMY_COUNT is too large: not enough OAM sprites"
    .endif
    .if ENEMY_VARS_END > $100
    .error "enemy arrays do not fit in zero page"
    .endif

; ===== BG スコア表示関連 =====
;   BG（背景）は「どのタイルを置くか」を番号で並べて描く。文字もタイルの 1 つなので、
;   文字を表示するには、その文字のタイル番号を書き込む。
TILE_DIGIT_BASE   = $10                     ; '0' のタイル番号。'0'+n でタイル取得
TILE_LETTER_S     = $1A
TILE_LETTER_C     = $1B
TILE_LETTER_O     = $1C
TILE_LETTER_R     = $1D
TILE_LETTER_E     = $1E
; --- 11 章で追加 ---
TILE_LETTER_H     = $1F
TILE_LETTER_T     = $20
TILE_LETTER_I     = $21
TILE_LETTER_N     = $22
TILE_LETTER_G     = $23
TILE_LETTER_P     = $24
TILE_LETTER_A     = $25
TILE_LETTER_V     = $26
TILE_LETTER_M     = $27
TILE_LETTER_L     = $28
TILE_LETTER_F     = $29
TILE_LETTER_X     = $2A
TILE_LETTER_D     = $2B
TILE_SPACE        = $0B                     ; 空白（中身が空のタイル）

; nametable 上の書き込み先（$2000 + row*32 + col）
;   画面は横 32 × 縦 30 タイル。その並びが PPU 側のメモリ $2000 から 1 行 32 バイトずつ
;   続いている。番地は 16 bit だが CPU は 8 bit ずつしか扱えないので、上位 (HI) と
;   下位 (LO) に分けて定義しておく。
SCORE_LABEL_ADDR_HI = $20
SCORE_LABEL_ADDR_LO = $22                   ; row 1, col 2 → "SCORE"
SCORE_VALUE_ADDR_HI = $20
SCORE_VALUE_ADDR_LO = $28                   ; row 1, col 8 → 6 桁分

; --- 11 章で追加: タイトル / GAME OVER / LIFE 表示位置 ---
LIVES_LABEL_ADDR_HI = $20
LIVES_LABEL_ADDR_LO = $39                   ; row 1, col 25 → "LIFEx"
LIVES_VALUE_ADDR_HI = $20
LIVES_VALUE_ADDR_LO = $3E                   ; row 1, col 30 → 残機 1 桁

TITLE_ADDR_HI       = $21
TITLE_ADDR_LO       = $cc                   ; row 14, col 12 → "SHOOTING"
PRESS_ADDR_HI       = $22
PRESS_ADDR_LO       = $4a                   ; row 18, col 10 → "PRESS START"
GAME_OVER_ADDR_HI   = $21
GAME_OVER_ADDR_LO   = $cb                   ; row 14, col 11 → "GAME OVER"

; 撃破 1 体あたりのスコア加算桁位置（10 点 → 十の位 = index 1）
SCORE_HIT_DIGIT   = 1

; ===== ステート定数 (11 章) =====
;   状態を 0, 1, 2 の数値で表す（Python の Enum の代わり）。
STATE_TITLE       = 0
STATE_PLAY        = 1
STATE_GAME_OVER   = 2

LIVES_INIT        = 3                       ; 初期残機
RESPAWN_DELAY     = 60                      ; 撃墜後の復活待ち (1 秒 = 60 フレーム)

; ===== PRG-ROM =====
;   .base は「ここから先のコードは CPU から見て $C000 番地に置かれる」とアセンブラに
;   伝える。ラベルのアドレスはこれを基準に計算される。16KB の PRG-ROM は
;   $C000〜$FFFF に見える。
    .base $c000

; ===== エントリポイント =====
;   電源を入れるかリセットすると、CPU は $FFFC に書かれた番地（= reset）から実行を始める。
;   （その番地を書いているのは 11_data.asm の末尾の割り込みベクタ）
reset:
    sei                         ; IRQ 割り込みを禁止。初期化の途中で割り込まれないように
    cld                         ; 10 進演算モードを解除（ファミコンでは使わないが作法として）
    ldx #$ff
    txs                         ; スタックポインタ = $FF。スタックは $0100〜$01FF を上から使う
    jsr init_fc                 ; PPU が安定するまで待ち、RAM を 0 クリア（lib/fc_init.asm）
    jsr init_app

    ; ここで永久ループに入り、以後は何もしない。
    ; ゲームの処理はすべて NMI（毎フレーム 1 回起きる割り込み、下の nmi ラベル）で行う。
    ; そうすると「1 フレームに 1 回だけ処理する」ことが自然に保証され、
    ; 処理のタイミングを画面の描き換えに合わせられる。
forever:
    jmp forever

    ; 共通の初期化ルーチン（init_fc など）をここに展開する
    .include "../lib/fc_init.asm"

; ===== アプリ固有の初期化 =====
;   PPU を有効化したあとにタイトル状態に遷移する。
;   各種スプライトは状態遷移時に setup_* で初期化されるので、ここでは呼ばない。
;   順番に意味がある: パレットと BG は描画 OFF のうちに書く（描画中の PPU には
;   書き込めない時間が長いため）。描画と NMI を ON にするのは最後。
init_app:
    jsr load_palette
    jsr clear_nametable         ; BG nametable を 0 で埋める
    lda #$A5                    ; LFSR の初期シード (非ゼロなら何でも可)
    sta rand_seed
    jsr enable_ppu              ; PPU 描画 ON、NMI ON
    jsr enter_title_state       ; 起動時はタイトルへ
    rts

; ===== パレット転送 =====
;   11_data.asm の palette（32 バイト）を PPU 内のパレット領域 $3F00〜$3F1F にコピーする。
;   PPU のメモリは CPU から直接読み書きできない。PPUADDR に番地を 2 回（上位→下位）
;   書いてから PPUDATA に書くと、PPU 側のその番地に届く。PPUDATA に書くたびに
;   番地は自動で +1 されるので、続けて書くだけで連続した領域を埋められる。
load_palette:
    lda #$3f
    sta PPUADDR                 ; 番地の上位バイト
    lda #$00
    sta PPUADDR                 ; 番地の下位バイト → 書き込み先 = $3F00
    ldx #$00
@loop:                          ; for x in range(32): PPUDATA = palette[x]
    lda palette, x
    sta PPUDATA
    inx
    cpx #$20                    ; x == 32 になったら終わり
    bne @loop
    rts

; ===== 自機の初期化 =====
;   座標と速度を初期値に戻し、生存フラグを立てる。ゲーム開始時と復活時に呼ぶ。
setup_sprite:
    lda #INIT_X
    sta sp0_x_hi                ; 座標は 8.8 固定小数。HI = 整数部 (px)
    lda #INIT_Y
    sta sp0_y_hi
    lda #$00
    sta sp0_x_lo                ; LO（小数部）は 0。A に 0 が入ったまま 2 回書いて使い回す
    sta sp0_y_lo

    lda #SPEED_INIT_LO
    sta speed_lo
    lda #SPEED_INIT_HI
    sta speed_hi

    lda #$80                    ; フラグは $80（bit 7 = 1）で「真」を表す（11_vars.inc 参照）
    sta player_active           ; 生存

    jsr sync_oam                ; 座標を OAM_BUF に反映して、すぐ表示できる状態にする
    rts

; ===== 弾プールの初期化 =====
;   active を全部 0、OAM 上の Y を画面外 ($FE) にして非表示にしておく
;   弾は 8 発ぶんの枠（プール）を最初から用意しておき、使っていない枠を探して再利用する。
;   実行中にメモリを確保・解放する仕組みが無いため、上限を決めて枠を固定で持つ。
setup_bullets:
    ldx #0
@loop:
    lda #$fe                            ; 非表示（OAM Y）
    sta BULLET_OAM_BASE+OAM_Y, x        ; bullet i の OAM_Y のみ初期化
    ; X に 4 を足す。X に直接足す命令は無いので、A に移して足し、X に戻す。
    ; adc は「A + 値 + キャリー」を計算するので、直前に clc でキャリーを 0 にしておく。
    txa
    clc
    adc #TMPL_SIZE                       ; 1 スプライト = 4 バイト進める
    tax
    cpx #(BULLET_MAX * TMPL_SIZE)
    bne @loop

    ; タイル番号・属性と active フラグは、弾 1 発ずつ進むこのループで書く
    ;   毎フレーム書き直す必要があるのは、動く Y と X だけ（sync_bullets_oam）。
    ldx #0                      ; X = OAM 上のバイト位置（4 ずつ進む）
    ldy #0                      ; Y = 何発目か（1 ずつ進む）。終了判定に使う
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
;   PPUCTRL の bit 7 を立てると、VBlank が始まるたびに NMI が起きるようになる。
;   PPUMASK で BG とスプライトの描画を ON にする。定数は lib/fc.inc で定義。
enable_ppu:
    lda #PPUCTRL_NMI
    sta PPUCTRL
    lda #PPUMASK_DRAW_ON   ; | はビット OR。アセンブル時に計算される
    sta PPUMASK
    rts

; ===== NMI =====
;   VBlank 中の処理順序:
;     1. OAM DMA
;     2. 状態遷移直後なら BG を再描画 (state_changed が立っていれば)
;     3. PLAY 中ならスコア / 残機表示を更新
;     4. PPUSCROLL を 0,0 に戻す
;   その後 game_state によって title / play / game_over に分岐。
;
;   NMI（Non-Maskable Interrupt）は、画面を 1 枚描き終えて次を描き始めるまでの
;   すき間（VBlank）に、PPU が CPU に割り込みをかける仕組み。1 秒に 60 回起きる。
;   PPU（画面担当のチップ）のメモリは、画面を描いている最中は書き換えられない
;   （書くと表示が乱れる）。安全に書けるのは VBlank の短い時間だけなので、
;   PPU を触る処理を NMI の先頭にまとめ、ゲームロジックはその後に回している。
;   メインループ（forever）は何もしていないので、ここで A・X・Y を退避する必要はない。
nmi:
    ; --- VBlank 中の PPU 操作 ---
    ; OAM DMA: OAM_BUF（CPU 側の RAM $0200〜$02FF）の 256 バイトを、スプライト表示用の
    ;   PPU 内メモリ (OAM) へ一括コピーする。1 バイトずつ書くより圧倒的に速いので、
    ;   ゲームロジックはふだん OAM_BUF だけを書き換え、ここで毎フレーム丸ごと転送する。
    lda #$00
    sta OAMADDR
    lda #>OAM_BUF                   ; > は「上位バイトを取り出す」演算子。$0200 → $02
    sta OAMDMA                      ; OAM DMA: $0200-$02FF → OAM

    ; 状態遷移直後なら BG を全書き換え:
    ;   nametable 1024 byte の書き換えは VBlank ≒ 2,273 サイクルに収まらない。
    ;   描画を OFF にして書き、このフレームは OFF のまま抜ける。書き終わるのは
    ;   画面の描画が始まった後なので、ここで ON にすると表示がずれる。
    ;   描画 ON は、次の NMI（次の VBlank 中）でスクロールを戻してから行う。
    lda state_changed               ; lda で N フラグ = bit 7 になる
    bpl @no_redraw                  ; bit 7 = 0（再描画不要）なら飛ばす
    lda #$00
    sta PPUMASK                     ; 描画 OFF (BG/SPR 両方)
    jsr redraw_bg_for_state
    lda #$00
    sta state_changed
    lda #$80
    sta ppu_on_pending              ; 次の NMI で描画を ON にする
    jmp @after_ppu_ops              ; スコアの数字は次のフレームで書く
@no_redraw:

    ; PLAY 中だけスコアと残機を更新
    lda game_state
    cmp #STATE_PLAY                 ; cmp は引き算の結果でフラグだけを変える（A は変わらない）
    bne @no_score                   ; game_state != STATE_PLAY なら飛ばす
    jsr update_score_display
    jsr update_lives_display
@no_score:

    ; PPUSCROLL リセット
    ;   PPUADDR を使うとスクロール位置の設定が上書きされる（PPU 内部で同じレジスタを
    ;   共有しているため）。描画位置がずれないよう、毎回スクロールを 0,0 に戻す。
    lda #$00
    sta PPUSCROLL
    sta PPUSCROLL

    ; 前のフレームで BG を書き直していたら、ここ（VBlank 中）で描画を ON に戻す
    lda ppu_on_pending
    bpl @after_ppu_ops              ; bit 7 = 0 なら何もしない
    lda #$00
    sta ppu_on_pending
    lda #PPUMASK_DRAW_ON
    sta PPUMASK                     ; 描画 ON
@after_ppu_ops:

    ; --- ここから先はゲームロジック（PPU には触らない） ---
    jsr read_pads

    ; ステート別ディスパッチ（Python なら if/elif で関数を呼ぶところ）
    ;   jsr ではなく分岐命令で飛ぶので、飛んだ先は呼び出しではなく「続き」になる。
    ;   そのため各 *_update は rts ではなく rti で終わり、そこで NMI 全体から戻る。
    lda game_state
    cmp #STATE_TITLE
    beq title_update
    cmp #STATE_PLAY
    beq play_update
    cmp #STATE_GAME_OVER
    beq game_over_update
    rti                             ; 割り込みから戻る（中断していた forever に戻る）

; ===== TITLE 状態の更新 =====
;   START を押されたら PLAY に遷移するだけ。
;   pad1_shot は「このフレームで押された瞬間のボタン」。and #BTN_START で START の
;   ビットだけを取り出し、0 なら（押されていなければ）何もせず rti で NMI を終える。
title_update:
    lda pad1_shot
    and #BTN_START
    beq @done
    jsr enter_play_state
@done:
    rti

; ===== PLAY 状態の更新 =====
;   撃墜中 (player_active = 0) は敵・弾の更新を止め、respawn_timer をデクリメント。
;   タイマー満了で lives > 0 なら自機・敵・弾を全部リセットして復活。
;   lives = 0 なら GAME_OVER へ。
;   敵が「自機の復活と同時に登場し直す」のはここで setup_enemies を呼ぶおかげ。
play_update:
    lda player_active
    bne @alive                      ; 0 以外（$80）なら生存中の処理へ

    ; 撃墜中：タイマーがあれば 1 減らして待機。敵・弾の更新は止める。
    lda respawn_timer
    beq @check_lives                ; タイマーが 0 になったら復活判定へ
    dec respawn_timer               ; dec はメモリの値を直接 1 減らす（A を通さない）
    jsr sync_oam
    jsr sync_bullets_oam
    jsr sync_enemies_oam
    rti

@check_lives:
    ; タイマー満了：残機があれば復活、無ければ GAME_OVER
    lda lives
    beq @go_game_over
    ; 自機・敵・弾を一斉にリセット → 自機復活と同時に新しい敵ウェーブが始まる
    jsr setup_sprite
    jsr setup_bullets
    jsr setup_enemies
    jsr sync_oam
    jsr sync_bullets_oam
    jsr sync_enemies_oam
    rti

@go_game_over:
    jsr enter_game_over_state
    rti

@alive:
    ; 1 フレーム分のゲーム進行。動かす → 当たり判定 → OAM_BUF に反映 の順。
    ; OAM_BUF に書いた内容が画面に出るのは、次の NMI の OAM DMA のとき。
    jsr update_position
    jsr try_spawn_bullet
    jsr update_bullets
    jsr update_enemies
    jsr check_collisions            ; 弾↔敵、自機↔敵
    jsr sync_oam
    jsr sync_bullets_oam
    jsr sync_enemies_oam
    rti

; ===== GAME_OVER 状態の更新 =====
;   START を押されたら TITLE に戻るだけ。
;   スプライトは enter_game_over_state で全部画面外に隠してある。
;   title_update と同じ形。押された瞬間だけを見るので、押しっぱなしで
;   TITLE → PLAY まで一気に進んでしまうことはない。
game_over_update:
    lda pad1_shot
    and #BTN_START
    beq @done
    jsr enter_title_state
@done:
    rti

; ===== 状態遷移サブルーチン =====
;   各状態に入るときの初期化。state_changed を立てると次フレームで BG が再描画される。
;   ここで直接 BG を書かないのは、NMI のゲームロジック部分（VBlank の外）から
;   呼ばれるため。PPU に書いてよいのは次の NMI の先頭なので、「書いてほしい」という
;   印だけを立てて、実際の書き換えはそちらに任せる。

enter_title_state:
    lda #STATE_TITLE
    sta game_state
    lda #$80
    sta state_changed               ; bit 7 = 1: 次の NMI で BG を描き直す
    ; スコアと残機をリセット
    ldx #(SCORE_DIGITS_COUNT - 1)   ; X = 5, 4, ..., 0 と逆順に回す
    lda #0
@score_clr:
    sta score_digits, x
    dex
    bpl @score_clr                  ; dex で X が $FF（-1）になると bit 7 が立ち、ループを抜ける
    lda #LIVES_INIT
    sta lives
    ; 全スプライトを画面外に追いやる
    jsr hide_all_sprites
    rts

enter_play_state:
    lda #STATE_PLAY
    sta game_state
    lda #$80
    sta state_changed
    lda #LIVES_INIT
    sta lives
    lda #0
    sta respawn_timer
    jsr setup_sprite
    jsr setup_bullets
    jsr setup_enemies
    rts

enter_game_over_state:
    lda #STATE_GAME_OVER
    sta game_state
    lda #$80
    sta state_changed
    jsr hide_all_sprites
    rts

; ===== 全スプライトを画面外に =====
;   OAM_BUF (256 byte) の各 4 byte の先頭 (= Y) に $FE を書くだけ。
;   Y = $FE で画面外、タイル / 属性 / X はそのままでよい。
;   スプライトを「消す」命令は無い。画面の縦は 240 ラインなので、それより下の
;   Y に置けば見えなくなる。これが 6502 + PPU での定番の消し方。
hide_all_sprites:
    ldx #0
@loop:
    lda #$fe
    sta OAM_BUF, x          ; Y バイト
    txa
    clc
    adc #4
    tax
    bne @loop               ; X が $00 (= 256 byte 一周) になったら終了
    ; ↑ X は 8 bit なので 252 + 4 = 256 は 0 に折り返す。この折り返しを終了条件に使うと、
    ;   cpx を書かずに 256 バイトちょうどを回れる。
    rts

; ===== 全敵を不在化 =====
;   enemy_active を 0 にすると sync_enemies_oam が hide パスを通って
;   その敵の 4 スプライトを Y=$FE で画面外に追いやる。
;   X を ENEMY_COUNT-1 から 0 まで数え下ろす。dex で X が 0 → $FF になると
;   N フラグが立つので、bpl だけで「X >= 0 の間くり返す」が書ける。
clear_all_enemies:
    lda #0
    ldx #(ENEMY_COUNT - 1)
@loop:
    sta enemy_active, x
    dex
    bpl @loop
    rts

; ===== 全弾を不在化 =====
;   bullet_active を 0 にすると sync_bullets_oam が Y=$FE で隠す。
clear_all_bullets:
    lda #0
    ldx #0
@loop:
    sta bullet_active, x
    inx
    cpx #BULLET_MAX
    bne @loop
    rts

; ===== 状態に応じた BG 描画 =====
;   state_changed が立った直後の VBlank で 1 回だけ呼ばれる。
;   nametable をクリアしてから状態固有の文字列を書く。
;   beq は ±127 byte しか飛べないので、bne + jmp で長距離分岐を組む。
;   jsr ではなく jmp で draw_* に飛ぶのは、draw_* の最後の rts で、このルーチンを
;   呼んだ nmi へ直接戻れるから（呼んで戻ってきてすぐ rts するのを省いている）。
redraw_bg_for_state:
    jsr clear_nametable
    lda game_state
    cmp #STATE_TITLE
    bne @not_title
    jmp draw_title_bg
@not_title:
    cmp #STATE_PLAY
    bne @not_play
    jmp draw_play_bg
@not_play:
    cmp #STATE_GAME_OVER
    bne @not_go
    jmp draw_game_over_bg
@not_go:
    rts

; ===== nametable を 0 で埋める =====
;   $2000-$23FF (1024 byte) を 0 で埋める。
;   描画 ON のまま VBlank で呼ぶには間に合うかどうかが問題だが、
;   このサンプルでは状態遷移は人間の入力が起点なので問題は出にくい。
;   （実際の呼び出し元の init_app と nmi は、どちらも描画 OFF の間に呼んでいる）
;   1024 = 256 × 4。X と Y は 255 までしか数えられないので、
;   Y で 256 回（0 → 0 に一周）回すループを X で 4 回繰り返す二重ループにしている。
clear_nametable:
    lda PPUSTATUS                   ; ラッチをリセット
    ; ↑ PPUADDR は 2 回の書き込みで上位・下位を受け取る。いまが何回目かを PPU が
    ;   覚えている（ラッチ）ので、PPUSTATUS を読んで「次は上位」の状態に戻してから書く。
    lda #$20
    sta PPUADDR
    lda #$00
    sta PPUADDR
    ldx #4
    ldy #0
    lda #$00
@loop:
    sta PPUDATA
    iny
    bne @loop                       ; Y が 0 に一周するまで（256 回）
    dex
    bne @loop                       ; それを 4 回
    rts

; ===== TITLE 用の BG 描画 =====
;   文字列（0 で終わるタイル番号の並び）を PPUDATA に順に書く。
;   C 言語の文字列と同じく、値 0 を見つけたら終わり。
draw_title_bg:
    ; "SHOOTING" を中央に
    lda PPUSTATUS
    lda #TITLE_ADDR_HI
    sta PPUADDR
    lda #TITLE_ADDR_LO
    sta PPUADDR
    ldx #0
@title_loop:
    lda title_str, x
    beq @title_end                  ; 0（終端）なら終わり。lda の時点で Z フラグが決まる
    sta PPUDATA
    inx
    bne @title_loop                 ; X は 0 に戻らないので常に飛ぶ（jmp の代わり。1 バイト短い）
@title_end:

    ; "PRESS START"
    lda #PRESS_ADDR_HI
    sta PPUADDR
    lda #PRESS_ADDR_LO
    sta PPUADDR
    ldx #0
@press_loop:
    lda press_start_str, x
    beq @press_end
    sta PPUDATA
    inx
    bne @press_loop
@press_end:
    rts

; ===== PLAY 用の BG 描画 =====
;   "SCORE" ラベルと "LIFEx" ラベルを書く。
;   数字部分（スコア / 残機）は毎フレームの update_*_display で書く。
;   draw_title_bg と同じ形（文字列を 0 終端まで書く）。
draw_play_bg:
    lda PPUSTATUS

    ; "SCORE"
    lda #SCORE_LABEL_ADDR_HI
    sta PPUADDR
    lda #SCORE_LABEL_ADDR_LO
    sta PPUADDR
    ldx #0
@score_loop:
    lda score_label_str, x
    beq @score_end
    sta PPUDATA                     ; 書くたびに書き込み先が 1 つ右へ進む
    inx
    bne @score_loop
@score_end:

    ; "LIFEx" (LIFE と「x」記号、数字は update_lives_display で書く)
    lda #LIVES_LABEL_ADDR_HI
    sta PPUADDR
    lda #LIVES_LABEL_ADDR_LO
    sta PPUADDR
    ldx #0
@lives_loop:
    lda lives_label_str, x
    beq @lives_end
    sta PPUDATA
    inx
    bne @lives_loop
@lives_end:
    rts

; ===== GAME_OVER 用の BG 描画 =====
;   draw_title_bg と同じ形（文字列を 0 終端まで書く）。
;   clear_nametable で SCORE / LIFE の欄も消えるので、PLAY 用の表示を書き直して
;   最終スコアが見えるようにしてから、"GAME OVER" と "PRESS START" を書く。
draw_game_over_bg:
    jsr draw_play_bg                ; "SCORE" と "LIFEx" のラベル
    jsr update_score_display        ; 最終スコアの数字
    jsr update_lives_display        ; 残機（0）

    ; "GAME OVER"
    lda PPUSTATUS
    lda #GAME_OVER_ADDR_HI
    sta PPUADDR
    lda #GAME_OVER_ADDR_LO
    sta PPUADDR
    ldx #0
@go_loop:
    lda game_over_str, x
    beq @go_end
    sta PPUDATA
    inx
    bne @go_loop
@go_end:

    ; "PRESS START"
    lda #PRESS_ADDR_HI
    sta PPUADDR
    lda #PRESS_ADDR_LO
    sta PPUADDR
    ldx #0
@press_loop:
    lda press_start_str, x
    beq @press_end
    sta PPUDATA
    inx
    bne @press_loop
@press_end:
    rts

; ===== 表示用文字列 =====
;   タイル番号を 0 終端で並べる。タイル 0 = 透明 (空白) として使う。
;   ASCII コードではなくタイル番号を並べるのは、PPU が受け取るのが「どのタイルを
;   置くか」の番号だから。ここは実行される命令ではなくデータなので、どこからも
;   jmp / 分岐で飛び込まない位置（rts の後）に置いている。
title_str:
    .db TILE_LETTER_S, TILE_LETTER_H, TILE_LETTER_O, TILE_LETTER_O
    .db TILE_LETTER_T, TILE_LETTER_I, TILE_LETTER_N, TILE_LETTER_G, $00

press_start_str:
    ; 空白はタイル 0 でも表せるが、0 は終端の印にも使っている。
    ; 途中に 0 を入れると書き込みが止まるので、
    ; 中身が空の別のタイル（TILE_SPACE）を使う。
    .db TILE_LETTER_P, TILE_LETTER_R, TILE_LETTER_E, TILE_LETTER_S
    .db TILE_LETTER_S, TILE_SPACE, TILE_LETTER_S, TILE_LETTER_T
    .db TILE_LETTER_A, TILE_LETTER_R, TILE_LETTER_T, $00

game_over_str:
    .db TILE_LETTER_G, TILE_LETTER_A, TILE_LETTER_M, TILE_LETTER_E, TILE_SPACE
    .db TILE_LETTER_O, TILE_LETTER_V, TILE_LETTER_E, TILE_LETTER_R, $00

score_label_str:
    .db TILE_LETTER_S, TILE_LETTER_C, TILE_LETTER_O, TILE_LETTER_R, TILE_LETTER_E, $00

lives_label_str:
    .db TILE_LETTER_L, TILE_LETTER_I, TILE_LETTER_F, TILE_LETTER_E, TILE_LETTER_X, $00

; ===== 残機表示 =====
;   PLAY 中の毎フレーム呼ばれ、nametable の残機表示位置に lives を 1 桁書き込む。
;   数字のタイルは '0' から '9' の順に並んでいるので、lives に '0' のタイル番号
;   (TILE_DIGIT_BASE) を足せば、その数字のタイル番号になる。
;   Python の chr(ord('0') + n) と同じ考え方。
update_lives_display:
    lda PPUSTATUS
    lda #LIVES_VALUE_ADDR_HI
    sta PPUADDR
    lda #LIVES_VALUE_ADDR_LO
    sta PPUADDR
    lda lives
    clc
    adc #TILE_DIGIT_BASE
    sta PPUDATA
    rts

; ===== 十字ボタンで自機の位置更新 =====
;   押されている方向ごとに、座標へ速度を足す（または引く）。
;   座標と速度は 16 bit（8.8 固定小数）なので、8 bit の CPU では 1 命令で足せない。
;   下位 → 上位の順に 2 回に分けて足すマクロ ADD16 / SUB16（lib/macros.inc）を使う。
;   小数を使う理由: 1 フレームに 1.5 px のような「整数でない速度」を表すため。
;   ファミコンの CPU には小数（浮動小数点）の命令が無いので、下位バイトを
;   1/256 px 単位の小数部として扱う。
update_position:
    lda pad1_raw
    and #BTN_UP                 ; 上ボタンのビットだけ残す。押されていなければ 0
    beq @skip_up
    SUB16 sp0_y_lo, sp0_y_hi, speed_lo, speed_hi    ; 画面の Y は下向きが正。上へは引く
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
;   pad1_raw（押しっぱなし）ではなく pad1_shot（押した瞬間）を見るので、
;   A を押しっぱなしにしても連射にならず、1 回押すごとに 1 発になる。
try_spawn_bullet:
    lda pad1_shot
    and #BTN_A
    beq @done                   ; A が今フレーム押されてなければ何もしない

    ldx #0
@find:                          ; for x in range(BULLET_MAX): if not bullet_active[x]: break
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
;   弾の情報は「弾の配列」ではなく、bullet_active[] / bullet_x_hi[] / bullet_y_hi[] の
;   3 本の配列に分けて持つ（並列配列）。同じ添字 X で 3 本を読めば 1 発分になる。
;   lda 配列, x の形で読めるので、構造体の配列より添字の計算が要らず速い。
update_bullets:
    ldx #0
@loop:
    lda bullet_active, x
    beq @next                   ; 未使用はスキップ

    ; y -= BULLET_SPEED
    ;   sbc は「A - 値 - (1 - キャリー)」を計算する。キャリーを 1 にしておかないと
    ;   余分に 1 引かれてしまうので、引き算の前には必ず sec を置く（足し算の clc と対）。
    lda bullet_y_hi, x
    sec
    sbc #BULLET_SPEED
    sta bullet_y_hi, x

    ; 画面外なら消す
    cmp #BULLET_OFF_TOP
    bcs @next                   ; y >= BULLET_OFF_TOP なら継続
    ; ここまで来ると画面外
    ;   1 フレームに 4 px しか動かないので、0 を下回って 255 側に折り返す前に
    ;   必ず 4〜7 の範囲を通り、ここで消える。
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
;   弾の番号（1 ずつ）と OAM_BUF 上の位置（4 バイトずつ）は進み方が違うので、
;   X と Y の 2 つのレジスタを別々の添字として使う。
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

; ===== 当たり判定 =====
;   中心座標どうしの距離が「半径の和」未満なら衝突。
;   絶対値判定は「(a - b) + (limit - 1) を unsigned で比較する」定番テク:
;     |a - b| < limit
;       ⇔ (a - b) ∈ [-(limit-1), limit-1]
;       ⇔ ((a - b) + (limit - 1)) ∈ [0, 2*(limit-1)]
;       ⇔ unsigned で 2*limit - 1 未満
;   弾(8x8) vs 敵(16x16): 半径の和 = 4 + 8 = 12 → cmp #23, bcs no_hit
;   自機(16x16) vs 敵(16x16): 半径の和 = 8 + 8 = 16 → cmp #31, bcs no_hit
;   なぜこうするか: 6502 には abs() も符号付きの比較命令も無い。a - b が負になると
;   8 bit では 255 側に折り返した値になる（-1 は 255）。そこで limit - 1 を足して
;   「判定したい範囲」を 0 から始まる範囲にずらすと、符号を気にせず cmp 1 回で済む。
;   当たり判定は四角形どうし（X と Y を別々に判定）で、円ではない。
HIT_RADIUS_BVE = 12         ; bullet vs enemy
HIT_RADIUS_PVE = 16         ; player vs enemy

check_collisions:
    jsr check_bullet_vs_enemy
    jsr check_player_vs_enemy
    rts

; --- 弾 vs 敵 ---
;   X = 弾添字, Y = 敵添字 をそれぞれループに使う（外側 X、内側 Y）
;   for x in 弾: for y in 敵: の二重ループ。X と Y が両方ループで埋まるので、
;   このルーチンの中では他の添字を使う処理を呼ばないようにしている。
check_bullet_vs_enemy:
    ldx #0
@bloop:
    lda bullet_active, x
    beq @bnext
    ldy #0
@eloop:
    lda enemy_active, y
    beq @enext

    ; |bullet_x - enemy_x| < 12 ?
    lda bullet_x_hi, x
    sec
    sbc enemy_x_cache, y
    clc
    adc #(HIT_RADIUS_BVE - 1)
    cmp #(2 * HIT_RADIUS_BVE - 1)
    bcs @enext                  ; 範囲外（X 方向で離れている）→ 次の敵へ

    ; |bullet_y - enemy_y| < 12 ?
    lda bullet_y_hi, x
    sec
    sbc enemy_y_hi, y
    clc
    adc #(HIT_RADIUS_BVE - 1)
    cmp #(2 * HIT_RADIUS_BVE - 1)
    bcs @enext

    ; ヒット → 弾と敵を両方消す + スコア +10
    lda #0
    sta bullet_active, x
    sta enemy_active, y
    jsr add_score_10
    jmp @bnext                  ; この弾は消えたので次の弾へ
@enext:
    iny
    cpy #ENEMY_COUNT
    bne @eloop
@bnext:
    inx
    cpx #BULLET_MAX
    bne @bloop
    rts

; --- 自機 vs 敵 ---
;   自機は 1 機なので、ループは敵（X）だけの一重ループ。
check_player_vs_enemy:
    lda player_active
    beq @done                   ; 既に撃墜済

    ldx #0
@loop:
    lda enemy_active, x
    beq @next

    ; |sp0_x_hi - enemy_x| < 16 ?
    lda sp0_x_hi
    sec
    sbc enemy_x_cache, x
    clc
    adc #(HIT_RADIUS_PVE - 1)
    cmp #(2 * HIT_RADIUS_PVE - 1)
    bcs @next

    ; |sp0_y_hi - enemy_y| < 16 ?
    lda sp0_y_hi
    sec
    sbc enemy_y_hi, x
    clc
    adc #(HIT_RADIUS_PVE - 1)
    cmp #(2 * HIT_RADIUS_PVE - 1)
    bcs @next

    ; ヒット → 自機撃墜
    lda #0
    sta player_active
    ; 残機を 1 減らす + 復活タイマーをセット
    dec lives
    lda #RESPAWN_DELAY
    sta respawn_timer
    ; 敵・弾も画面から消す。このあと同じフレームの sync_bullets_oam / sync_enemies_oam で
    ; 全スプライトが Y=$FE に追いやられ、次の OAM DMA で非表示になる。
    ; 自機が復活するときに setup_enemies / setup_bullets で新しいウェーブが始まる。
    jsr clear_all_enemies
    jsr clear_all_bullets
    rts
@next:
    inx
    cpx #ENEMY_COUNT
    bne @loop
@done:
    rts

; ===== スコアを nametable に反映 =====
;   score_digits[0]=ones .. [5]=hundred-thousands を、左 (高位) から並べて書く。
;   画面には左から書いていくので、配列は上の桁（添字 5）から逆順に読む。
update_score_display:
    lda PPUSTATUS               ; ラッチをリセット
    lda #SCORE_VALUE_ADDR_HI
    sta PPUADDR
    lda #SCORE_VALUE_ADDR_LO
    sta PPUADDR

    ldx #(SCORE_DIGITS_COUNT - 1)
@loop:
    lda score_digits, x
    clc
    adc #TILE_DIGIT_BASE        ; 数字 n → タイル番号
    sta PPUDATA
    dex
    bpl @loop                    ; X が $FF (=-1) になったら終了
    rts

; ===== スコアに 10 加算 =====
;   score_digits[1] (十の位) を +1 し、9 を超えたら 0 に戻して
;   1 つ上の桁に繰り上げる。最上位が桁あふれしたら最大値で止める（抑制）。
;   スコアを 1 つの整数ではなく 1 桁 1 バイトで持つ理由: 6502 には割り算の命令が
;   無く、整数を 10 進の各桁に分ける（÷10 を繰り返す）と処理が重い。桁ごとに
;   持っておけば、表示のたびに割り算をしなくて済む。手で筆算するのと同じ繰り上げ処理。
;   中で X を使うが、呼び出し元（弾のループ）の X はスタックに退避して戻す。
add_score_10:
    txa                         ; 呼び出し元の X（弾の添字）を退避
    pha
    ldx #SCORE_HIT_DIGIT
@carry:
    inc score_digits, x
    lda score_digits, x
    cmp #10
    bcc @done                   ; 10 未満なら繰り上げ不要で終わり
    lda #0
    sta score_digits, x
    inx                         ; 1 つ上の桁へ
    cpx #SCORE_DIGITS_COUNT
    bne @carry
    ; 桁あふれ：全桁を 9 に貼り付けて表示は最大値で固定
    ldx #(SCORE_DIGITS_COUNT - 1)
    lda #9
@cap:
    sta score_digits, x
    dex
    bpl @cap
@done:
    pla                         ; 退避しておいた X を戻す
    tax
    rts

; ===== 敵の OAM テンプレート =====
;   1 体 = 16x16 = 4 スプライト。バイト並びは「タイル, dx, dy, 属性」。
;   ハードウェアのスプライトは 8x8 なので、16x16 のキャラは 4 枚を並べて作る。
;   dx, dy は中心からのずれ。-8 は 8 bit では $F8（2 の補数）として格納され、
;   中心 X に足すと 8 bit の折り返しで「8 を引いた」のと同じ結果になる。
;   この性質のおかげで、足し算だけで左にも右にもずらせる。
enemy_oam_template:
    .db ENEMY_TILE_TL, -8, -8, ENEMY_ATTR
    .db ENEMY_TILE_TR,  0, -8, ENEMY_ATTR
    .db ENEMY_TILE_BL, -8,  0, ENEMY_ATTR
    .db ENEMY_TILE_BR,  0,  0, ENEMY_ATTR

; ===== 敵の初期化 =====
;   全 ENEMY_COUNT 体を同じ初期座標・同じ phase で生成し、enemy_delay で
;   ENEMY_SPAWN_GAP フレームずつ登場をずらす（先頭が描いた軌跡を後続が追う縦列）。
;   active は delay==0 の個体だけ生存中にする（先頭のみ）。
setup_enemies:
    ldx #0                          ; X = 敵の添字
    ldy #0                          ; Y = この敵の待機フレーム数（X * ENEMY_SPAWN_GAP）
@init_loop:
    lda #ENEMY_INIT_Y
    sta enemy_y_hi, x
    lda #0
    sta enemy_phase, x
    sta enemy_active, x             ; いったん全員を待機中（不在扱い）にする
    sty enemy_delay, x              ; sty にも「番地 + X」の形がある

    ; 各敵のサイン波の中心 X を乱数で決める (64..191 の範囲 = 画面の中央寄り)
    ;   random_byte で 1..255 を作り、bit 7 を落として 0..127 → +$40 で 64..191
    ;   and #$7F は「128 で割った余り」と同じ。2 のべき乗での剰余はビットの AND で書ける。
    jsr random_byte                 ; A に乱数が返る（random_byte は X / Y を壊さない）
    and #$7F
    clc
    adc #$40
    sta enemy_center_x, x

    ; 次の敵の待機フレーム数 = Y + ENEMY_SPAWN_GAP
    tya
    clc
    adc #ENEMY_SPAWN_GAP
    tay

    inx
    cpx #ENEMY_COUNT
    bne @init_loop

    ; 生存フラグ: delay==0 の先頭だけ生存
    lda #$80
    sta enemy_active+0              ; enemy_active+0 は Python の enemy_active[0]

    ; 先頭の x_cache を初期 phase で計算しておく（描画開始フレーム用）
    ldx #0                          ; get_sine_x への引数: X = 敵の添字
    jsr get_sine_x
    sta enemy_x_cache+0             ; 戻り値は A に入っている
    rts

; ===== 敵の更新 =====
;   delay > 0 : 待機中。delay を 1 減らし、0 になったら active=$80 に切り替える。
;               （活性化したフレームでは移動しない → ENEMY_SPAWN_GAP フレーム差を保つ）
;   active=$80: y += ENEMY_SPEED, phase += 1, 画面下に出たら active=0 にする
;   active=0  : 撃墜済 or 画面外。何もしない。
;   active な間は毎フレーム enemy_x_cache を更新しておく（当たり判定と sync で共用）。
;   全員 active=0 かつ delay=0 になったら setup_enemies で再登場。
;   X 座標をキャッシュする理由: サイン波の計算は当たり判定と表示の両方で必要。
;   1 フレームに 1 回だけ計算して保存しておけば、同じ計算を繰り返さずに済む。
update_enemies:
    ldx #0
@loop:
    lda enemy_delay, x
    beq @check_active
    dec enemy_delay, x          ; dec の結果でも Z フラグが変わるので、すぐ分岐できる
    bne @next                   ; まだ待機中
    ; delay が 0 になった瞬間 → activate（移動はしない）
    lda #$80
    sta enemy_active, x
    jsr get_sine_x              ; 描画開始用に X cache を埋める
    sta enemy_x_cache, x
    jmp @next
@check_active:
    lda enemy_active, x
    beq @next                   ; 撃墜済 or 画面外
    ; --- 移動 ---
    lda enemy_y_hi, x
    clc
    adc #ENEMY_SPEED
    sta enemy_y_hi, x
    inc enemy_phase, x          ; 127 の次は 128 → 255 の次は 0 と折り返すが、
                                ; get_sine_x で and #$7F するので問題ない
    jsr get_sine_x
    sta enemy_x_cache, x
    ; 画面下に消えたか
    lda enemy_y_hi, x
    cmp #ENEMY_OFF_BOTTOM
    bcc @next                   ; y < 240 ならまだ画面内
    lda #0
    sta enemy_active, x
@next:
    inx
    cpx #ENEMY_COUNT
    bne @loop

    ; 全員 active=0 AND delay=0 なら再登場
    ;   ora（ビット OR）で active と delay をまとめる。どちらかが 0 でなければ結果も 0 でない。
    ;   1 体でも残っていれば、その時点で再登場をやめる（Python の any() に当たる）。
    ldx #(ENEMY_COUNT - 1)
@any_loop:
    lda enemy_active, x
    ora enemy_delay, x
    bne @done
    dex
    bpl @any_loop                   ; clear_all_enemies と同じ数え下ろし
    jsr setup_enemies
@done:
    rts

; ===== 8 bit LFSR (Galois 型) =====
;   in : なし (rand_seed を読む)
;   out: A = 新しい乱数 (1..255)、rand_seed が更新される
;   周期 255 で同じ値の列を繰り返す擬似乱数。0 にすると周期から外れるので
;   rand_seed は常に非ゼロを保つ (init_app で $A5 に初期化済み)。
;   詳しい仕組みは巻末付録 C「乱数生成」を参照。
;   ファミコンには乱数を出す装置が無いので、ビット演算で「乱数っぽい」列を作る。
;   シフトと XOR だけで済み、掛け算・割り算の命令が無い 6502 でも数命令で書ける。
random_byte:
    lda rand_seed
    asl a                   ; bit 7 をキャリーへ押し出す
    bcc @no_xor             ; 押し出されたビットが 0 なら XOR 不要
    eor #$1D                ; taps: $1D = %00011101 (周期 255 の最大長 LFSR)
@no_xor:
    sta rand_seed
    rts

; ===== サイン波で X 座標を計算 =====
;   in : X = 敵添字 (0..ENEMY_COUNT-1)
;   out: A = 中心 X = enemy_center_x[X] ± sin_half[phase mod 64]
;        Y は壊れる（テーブルの添字に使うため）
;   敵ごとに enemy_center_x が違うので、1 体ずつ別々の X 軸でサイン波を描く。
;   sin() の命令は無いので、あらかじめ計算した値の表（11_data.asm の sin_half）を引く。
;   表は波の山の半分（0..63）だけを持ち、phase が 64..127 のときは引き算して谷側を作る。
;   表を半分にすると、ROM の使用量も半分で済む。
get_sine_x:
    lda enemy_phase, x
    and #$7F                ; 周期 128
    cmp #$40
    bcc @pos_half           ; phase < 64 なら山の側
    sec
    sbc #$40                ; phase 64..127 → 0..63
    tay                     ; 表の添字は Y で渡す（X は敵の添字で使用中）
    lda enemy_center_x, x
    sec
    sbc sin_half, y         ; 負の半波: center - table
    rts
@pos_half:
    tay
    lda enemy_center_x, x
    clc
    adc sin_half, y         ; 正の半波: center + table
    rts

; ===== 敵 OAM の展開 =====
;   外側ループ: ENEMY_COUNT 体の敵を巡回（X レジスタ）
;   内側ループ: 1 体あたり 4 スプライトをテンプレートから書き出す（Y レジスタ）
;   X と Y は両方使うので、一時保存に enemy_idx_tmp / oam_idx_tmp を利用する。
;   本当は「敵の添字」「テンプレートの位置」「OAM_BUF の位置」の 3 つの添字が要るが、
;   添字に使えるレジスタは X と Y の 2 つだけ。そこで X を敵の添字と OAM_BUF の位置で
;   使い回し、使っていない方の値をゼロページの変数に退避しておく。
sync_enemies_oam:
    lda #(ENEMY_OAM_BASE - OAM_BUF)
    sta oam_idx_tmp                 ; OAM_BUF 内のバイト添字を持つ
    ldx #0
@enemy:
    stx enemy_idx_tmp               ; 敵の添字を退避（X をこの後 OAM の位置に使うため）

    lda enemy_active, x
    beq @hide                       ; 不在（待機中／撃墜済／画面外）→ 4 スプライト隠す

    ; --- 通常表示（X は update_enemies が埋めた cache を使う） ---
    lda enemy_x_cache, x
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
    ;   iny を 4 回並べる方が、tya / clc / adc / tay より 1 バイト短い
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
    dey                             ; Y を 4 → 0 と数え下ろす。0 になれば Z が立つので
    bne @hide_loop                  ;   cpy を書かずに終了判定できる
    stx oam_idx_tmp

@next_enemy:
    ldx enemy_idx_tmp               ; 退避しておいた敵の添字を X に戻す
    inx
    cpx #ENEMY_COUNT
    bne @enemy
    rts

; ===== 自機の OAM テンプレート =====
;   敵と同じ形（タイル, dx, dy, 属性）。属性 $00 = パレット 0、反転なし。
ship_oam_template:
    .db $02, -8, -8, $00        ; sprite 0: top-left
    .db $03,  0, -8, $00        ; sprite 1: top-right
    .db $04, -8,  0, $00        ; sprite 2: bottom-left
    .db $05,  0,  0, $00        ; sprite 3: bottom-right

; ===== 自機 OAM の展開 =====
;   player_active=0 なら全 4 スプライトを画面外に隠す
;   自機は OAM_BUF の先頭（0 バイト目）から 16 バイトを使う。テンプレートも
;   1 スプライト 4 バイトで並びが同じなので、1 つの X をテンプレートと OAM_BUF の
;   両方の添字に使える（敵のように X を退避する必要が無い）。
;   座標は 8.8 固定小数の整数部（_hi）だけを使う。画面上の位置は 1 px 単位だから。
sync_oam:
    lda player_active
    beq @hide

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

@hide:
    ldx #0
@hide_loop:
    lda #$fe
    sta OAM_BUF+OAM_Y, x
    txa
    clc
    adc #TMPL_SIZE
    tax
    cpx #SHIP_OAM_SIZE
    bne @hide_loop
    rts

; ===== 1P コントローラーの読み取り =====
;   コントローラーは、8 個のボタンの状態を 1 ビットずつ順番に送ってくる。
;   JOYPAD1 ($4016) に 1 → 0 を書くと、その瞬間のボタン状態が記録（ラッチ）され、
;   その後 JOYPAD1 を 8 回読むと A, B, SELECT, START, 上, 下, 左, 右 の順に
;   bit 0 に 1 つずつ出てくる。
;   lsr a で bit 0 をキャリーに移し、rol pad1_raw でキャリーを pad1_raw の右端に
;   押し込む。8 回繰り返すと、最初に読んだ A ボタンが bit 7 に来る
;   （lib/fc.inc の BTN_A = %10000000 と同じ並び）。
read_pads:
    lda pad1_raw
    sta pad1_prev               ; 前フレームの状態を残す（押した瞬間の判定に使う）

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

    ; pad1_shot = (not prev) and raw
    ;   「前のフレームでは押されていなくて、今は押されている」ボタンだけが 1 になる。
    ;   eor #$ff は全ビットの反転（Python の ~x & 0xFF）。
    lda pad1_prev
    eor #$ff
    and pad1_raw
    sta pad1_shot
    rts

; ===== IRQ =====
;   このプログラムは IRQ を使わない（reset で sei 済み）。万一起きてもすぐ戻る。
irq:
    rti

; ===== パレット / 割り込みベクタ / CHR-ROM =====
    .include "11_data.asm"
