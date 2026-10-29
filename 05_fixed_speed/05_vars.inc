; 05_vars.inc - 05_fixed_speed 固有のゼロページ変数

; スプライト 0 の位置（8.8 固定小数）
sp0_x_lo   = $20    ; X 小数部
sp0_x_hi   = $21    ; X 整数部（OAM に書くのはこちら）
sp0_y_lo   = $22
sp0_y_hi   = $23

; 速度（8.8 固定小数・非負）
speed_lo   = $24
speed_hi   = $25

; 計算一時領域
tmp_lo     = $26
tmp_hi     = $27
