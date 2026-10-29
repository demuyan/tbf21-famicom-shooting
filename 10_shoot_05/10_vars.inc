; 10_vars.inc - 10_shoot_05 固有のゼロページ変数

; 1P コントローラーの状態
pad1_raw   = $10    ; ベタ入力
pad1_prev  = $11    ; 前フレームの pad1_raw
pad1_shot  = $12    ; ワンショット（押した瞬間だけ 1）

; 自機の中心座標（8.8 固定小数）
sp0_x_lo      = $20
sp0_x_hi      = $21
sp0_y_lo      = $22
sp0_y_hi      = $23

; 自機の移動速度（8.8 固定小数）
speed_lo      = $24
speed_hi      = $25

; 自機の生存フラグ（$80 = 生存、$00 = 撃墜）
player_active = $26

; 弾プール（BULLET_MAX 個分の並列配列）
;   bullet_active[i]  = 0 なら未使用、$80 なら使用中
;   bullet_x_hi[i]    = 整数 X 座標（中心）
;   bullet_y_hi[i]    = 整数 Y 座標（中心）
;     ※ 弾は速度を整数 px/frame に固定し、小数部は持たない
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
enemy_y_hi    = $50         ; $50..$53
enemy_phase   = $54         ; $54..$57
enemy_delay   = $58         ; $58..$5B
enemy_active  = $5C         ; $5C..$5F
enemy_x_cache = $64         ; $64..$67

; sync_enemies_oam の一時領域
enemy_idx_tmp = $60
cx_tmp        = $61         ; 計算済みの中心 X
cy_tmp        = $62         ; 計算済みの中心 Y
oam_idx_tmp   = $63         ; OAM_BUF の書き込み位置（バイト添字）

; スコア（6 桁の 10 進数を 1 桁ずつ別バイトに保持）
;   score_digits[0] = 一の位、[5] = 十万の位
;   clear_ram で 0 クリアされるので明示的な初期化は不要
SCORE_DIGITS_COUNT = 6
score_digits  = $70         ; $70..$75
