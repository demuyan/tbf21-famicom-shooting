; pad_vars.inc - 1P / 2P コントローラー用ゼロページ変数（共通）
;   read_pads サブルーチン（各サンプルに存在）が更新する

pad1_raw  = $10     ; 1P コントローラーのベタ入力（押している間ずっと 1）
pad1_prev = $11     ; 前フレームの pad1_raw
pad1_shot = $12     ; 1P コントローラーのワンショット（押した瞬間だけ 1）
pad2_raw  = $13
pad2_prev = $14
pad2_shot = $15
