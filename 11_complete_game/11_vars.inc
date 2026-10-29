; 11_vars.inc - 11_complete_game 固有のゼロページ変数 (10_vars + ステート変数)
;
;   アセンブラには「変数を宣言すると置き場所を自動で決めてくれる」仕組みが無い
;   （asm6f にも近い機能はあるが、本書では使わない）。そこで、RAM のどの番地を
;   何に使うかを、名前 = 番地 の形で 1 つずつ手で決めている。
;   たとえば pad1_raw = $10 と書くと、以後 pad1_raw と書いた所は番地 $10 になる。
;   変数どうしの番地が重ならないように管理するのはプログラマの仕事。
;
;   ここで使っている $00〜$FF の 256 バイトを「ゼロページ」と呼ぶ。番地が 1 バイトで
;   表せるので、それ以外の RAM より命令が 1 バイト短く、実行も速い。
;   よく読み書きする変数は、できるだけゼロページに置く。
;
;   名前の _lo / _hi は、16 bit の値を 2 バイトに分けたときの下位 / 上位バイト。

; 1P コントローラーの状態
;   各ボタンが 1 ビットずつ並ぶ（bit 7 = A ... bit 0 = 右。lib/fc.inc の BTN_*）。
pad1_raw   = $10    ; ベタ入力
pad1_prev  = $11    ; 前フレームの pad1_raw
pad1_shot  = $12    ; ワンショット（押した瞬間だけ 1）

; 自機の中心座標（8.8 固定小数）
;   _hi が整数部（画面上の px）、_lo が小数部（1/256 px 単位）。
;   CPU に小数の命令が無いので、2 バイトを組にして「256 倍した整数」として扱う。
sp0_x_lo      = $20
sp0_x_hi      = $21
sp0_y_lo      = $22
sp0_y_hi      = $23

; 自機の移動速度（8.8 固定小数）
speed_lo      = $24
speed_hi      = $25

; 自機の生存フラグ（$80 = 生存、$00 = 撃墜）
;   真を 1 ではなく $80 で表すのは、bit 7 が N フラグに直結するから。
;   lda しただけで bmi / bpl で分岐でき、0 かどうかは beq / bne でも判定できる。
player_active = $26

; 弾プール（BULLET_MAX 個分の並列配列）
;   bullet_active[i]  = 0 なら未使用、$80 なら使用中
;   bullet_x_hi[i]    = 整数 X 座標（中心）
;   bullet_y_hi[i]    = 整数 Y 座標（中心）
;     ※ 弾は速度を整数 px/frame に固定し、小数部は持たない
;   Python なら bullets = [{"active":..., "x":..., "y":...}, ...] と書くところを、
;   項目ごとの配列 3 本に分けている。lda bullet_x_hi, x のように、同じ添字 X で
;   どの項目も直接読めるため（構造体の配列だと、添字 × 構造体の大きさの計算が要る）。
;   配列の大きさは、先頭の番地を BULLET_MAX ずつずらして確保する。
BULLET_MAX = 8
bullet_active = $30                              ; $30 から BULLET_MAX 個
bullet_x_hi   = bullet_active + BULLET_MAX       ; 前の配列のすぐ後ろに置く
bullet_y_hi   = bullet_x_hi + BULLET_MAX
BULLET_VARS_END = bullet_y_hi + BULLET_MAX       ; 弾の配列の次の番地
    .if BULLET_VARS_END > $48                    ; 次の変数（$48〜）と重なったら止める
    .error "bullet arrays overlap the next variables; move them"
    .endif

; 一時領域
tmp        = $48

; 敵 (ENEMY_COUNT 体分の並列配列)
;   enemy_y_hi[i]    : 中心 Y 座標 (整数 px)
;   enemy_phase[i]   : サイン波の位相 (0..127、毎フレーム +1)
;   enemy_delay[i]   : 登場までの待機フレーム数（>0 の間は非表示・更新停止）
;   enemy_active[i]  : $80 = 生存（画面内）、$00 = 不在（待機中 or 撃墜済 or 画面下に消えた）
;   enemy_x_cache[i] : update_enemies で計算した中心 X。当たり判定と sync で使い回す
;   enemy_center_x[i]: サイン波の中心 X。setup_enemies で乱数で決め直す
;   各配列の先頭は「1 つ前の配列の先頭 + ENEMY_COUNT」で決める。こうしておけば、
;   ENEMY_COUNT を書き換えるだけで、番地がアセンブル時に計算し直される。
;   ほかの変数と重ならないよう、空いている $90 以降にまとめて置く
;   （6 本 × ENEMY_COUNT バイト。最大の 13 体でも $90..$DD に収まる）。
ENEMY_COUNT    = 4
enemy_y_hi     = $90
enemy_phase    = enemy_y_hi    + ENEMY_COUNT
enemy_delay    = enemy_phase   + ENEMY_COUNT
enemy_active   = enemy_delay   + ENEMY_COUNT
enemy_x_cache  = enemy_active  + ENEMY_COUNT
enemy_center_x = enemy_x_cache + ENEMY_COUNT
ENEMY_VARS_END = enemy_center_x + ENEMY_COUNT    ; 敵の配列の次の番地

; sync_enemies_oam の一時領域
;   X・Y レジスタだけでは添字が足りないので、値の退避先として使う。
enemy_idx_tmp = $60
cx_tmp        = $61         ; 計算済みの中心 X
cy_tmp        = $62         ; 計算済みの中心 Y
oam_idx_tmp   = $63         ; OAM_BUF の書き込み位置（バイト添字）

; スコア（6 桁の 10 進数を 1 桁ずつ別バイトに保持）
;   score_digits[0] = 一の位、[5] = 十万の位
;   clear_ram で 0 クリアされるので明示的な初期化は不要
;   1 バイトでは 255 までしか数えられず、10 進で表示するには割り算も要る。
;   桁ごとに持てば、どちらの問題も避けられる（add_score_10 参照）。
SCORE_DIGITS_COUNT = 6
score_digits  = $70         ; $70..$75

; ===== ゲームステート (11 章で追加) =====
;   game_state    : 0 = TITLE, 1 = PLAY, 2 = GAME_OVER
;   state_changed : bit 7 = 1 のとき「次フレームで BG を再描画」
;   lives         : 残機（初期値 LIVES_INIT、撃墜のたびに -1）
;   respawn_timer : 撃墜後の復活待ちフレーム数
game_state    = $80
state_changed = $81
lives         = $82
respawn_timer = $83

; ===== 乱数（LFSR、付録 C）=====
;   rand_seed: 8 bit LFSR の状態。0 にすると周期から外れるので非ゼロで初期化。
rand_seed     = $84

; ===== 描画 ON の予約 =====
;   ppu_on_pending: BG を書き直したフレームの次の NMI で描画を ON にする印（$80 = 予約あり）
ppu_on_pending = $85
