; 07_vars.inc - 07_shoot_02 固有のゼロページ変数

; 1P コントローラーの状態
pad1_raw   = $10    ; ベタ入力
pad1_prev  = $11    ; 前フレームの pad1_raw
pad1_shot  = $12    ; ワンショット（押した瞬間だけ 1）

; 自機の中心座標（8.8 固定小数）
sp0_x_lo   = $20
sp0_x_hi   = $21
sp0_y_lo   = $22
sp0_y_hi   = $23

; 自機の移動速度（8.8 固定小数）
speed_lo   = $24
speed_hi   = $25

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
