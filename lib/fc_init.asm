; fc_init.asm - ファミコンの定型初期化サブルーチン群（使い回し用）
;   init_fc: 呼ぶだけでブート直後の PPU 安定状態まで持っていく
;            （内部で init_cpu → VBlank 待ち → RAM クリア → VBlank 待ち）
;
; 注意: init_cpu はスタックポインタを触らないので、呼び出し側の reset 直下で
;       sei / cld / ldx #$ff / txs を済ませてから jsr init_fc を呼ぶこと。
;       （サブルーチン内で txs するとその jsr の戻りアドレスが壊れる）

; ===== ファミコン起動時の一括初期化 =====
init_fc:
    jsr init_cpu
    bit PPUSTATUS           ; 起動時に残っている VBlank フラグを消しておく
    jsr wait_vblank         ; 1 回目の VBlank 待ち
    jsr clear_ram
    jsr wait_vblank         ; 2 回目（PPU が安定するまで）
    rts

; ===== APU / PPU レジスタの初期化（スタックには触れない） =====
init_cpu:
    ldx #$40
    stx APUFRAME            ; APU フレーム IRQ 無効
    ldx #$00
    stx PPUCTRL             ; NMI off
    stx PPUMASK             ; 描画オフ
    stx DMCFREQ             ; DMC IRQ 無効
    rts

; ===== VBlank 待ち =====
wait_vblank:
    bit PPUSTATUS           ; bit7 を N フラグへ
    bpl wait_vblank         ; bit7=0（非VBlank）ならループ
    rts

; ===== RAM ($0000-$07FF) と OAM シャドウをクリア =====
; $0100-$01FF (スタック) はクリアしない ─ ここを 0 で埋めると、
; 呼び出し元 (jsr) の戻りアドレスまで消えて、clear_ram の rts で
; $0001 に飛んでしまいクラッシュする。
clear_ram:
    ldx #$00
clrloop:
    lda #$00
    sta $0000, x            ; $0000-$00FF
    sta $0300, x            ; $0300-$03FF
    sta $0400, x            ; $0400-$04FF
    sta $0500, x            ; $0500-$05FF
    sta $0600, x            ; $0600-$06FF
    sta $0700, x            ; $0700-$07FF
    lda #$fe                ; OAM の Y 座標 = 画面外にして非表示
    sta OAM_BUF, x          ; OAM シャドウ $0200-$02FF
    inx
    bne clrloop             ; 256 バイト分ループ
    rts
