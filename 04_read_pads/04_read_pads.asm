; 04_read_pads.asm - 1P / 2P コントローラーのベタ入力とワンショットで 2 つのスプライトを動かす（02 のスタイルで整理）
;   - iNES ヘッダを ines.inc に分離
;   - I/O レジスタ定義を fc.inc に集約
;   - ファミコン共通の初期化を fc_init.asm (init_fc) に分離
;   - アプリ固有の初期化は init_app にまとめる
;   - パレット / CHR データを 04_data.asm に分離
; ビルド: asm6f 04_read_pads.asm 04_read_pads.nes

    .include "../lib/ines.inc"
    .include "../lib/fc.inc"

; ===== ゼロページ変数 =====
    .include "../lib/pad_vars.inc"

; ===== PRG-ROM (16KB, $C000-$FFFF にマップ) =====
    .base $c000

; ===== エントリポイント =====
reset:
    sei
    cld
    ldx #$ff
    txs                     ; スタックポインタ = $FF（必ず jsr より前に）
    jsr init_fc             ; ファミコン共通の初期化
    jsr init_app            ; このアプリの表示用初期化

forever:
    jmp forever             ; メインは待機、処理は NMI 任せ

; ===== ファミコン共通の初期化（使い回し可能） =====
    .include "../lib/fc_init.asm"

; ===== アプリ固有の初期化 =====
init_app:
    jsr load_palette
    jsr setup_sprites
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

; ===== スプライト 0 (1P コントローラーで操作・白) と 1 (2P コントローラーで操作・赤) をセット =====
setup_sprites:
    ; スプライト 0: 白
    lda #$70
    sta OAM_BUF+0           ; Y = 112
    lda #$01
    sta OAM_BUF+1           ; タイル 1
    lda #$00
    sta OAM_BUF+2           ; パレット 0
    lda #$70
    sta OAM_BUF+3           ; X = 112

    ; スプライト 1: 赤
    lda #$70
    sta OAM_BUF+4
    lda #$01
    sta OAM_BUF+5
    lda #$01
    sta OAM_BUF+6           ; パレット 1
    lda #$88
    sta OAM_BUF+7           ; X = 136（少し右）
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

    jsr read_pads           ; 1P / 2P コントローラーの状態を読み取り
    jsr update_sprites      ; 入力に応じてスプライトを動かす
    rti

; ===== PAD 入力で 2 つのスプライトを更新 =====
update_sprites:
    ; --- 1P コントローラー → スプライト 0 ---
    lda pad1_raw
    and #BTN_UP
    beq skip_p1up
    dec OAM_BUF+0
skip_p1up:
    lda pad1_raw
    and #BTN_DOWN
    beq skip_p1dn
    inc OAM_BUF+0
skip_p1dn:
    lda pad1_raw
    and #BTN_LEFT
    beq skip_p1lt
    dec OAM_BUF+3
skip_p1lt:
    lda pad1_raw
    and #BTN_RIGHT
    beq skip_p1rt
    inc OAM_BUF+3
skip_p1rt:
    ; A ワンショットでスプライト 0 を中央に戻す
    lda pad1_shot
    and #BTN_A
    beq skip_p1a
    lda #$70
    sta OAM_BUF+0
    sta OAM_BUF+3
skip_p1a:

    ; --- 2P コントローラー → スプライト 1 ---
    lda pad2_raw
    and #BTN_UP
    beq skip_p2up
    dec OAM_BUF+4
skip_p2up:
    lda pad2_raw
    and #BTN_DOWN
    beq skip_p2dn
    inc OAM_BUF+4
skip_p2dn:
    lda pad2_raw
    and #BTN_LEFT
    beq skip_p2lt
    dec OAM_BUF+7
skip_p2lt:
    lda pad2_raw
    and #BTN_RIGHT
    beq skip_p2rt
    inc OAM_BUF+7
skip_p2rt:
    ; A ワンショットでスプライト 1 を初期位置に戻す
    lda pad2_shot
    and #BTN_A
    beq skip_p2a
    lda #$70
    sta OAM_BUF+4
    lda #$88
    sta OAM_BUF+7
skip_p2a:
    rts

; ===== PAD 読み取りサブルーチン =====
; 1P / 2P コントローラーのベタ入力 (pad*_raw) とワンショット (pad*_shot) を 1 バイトずつ更新する。
; ボタンビット並び: bit7=A, bit6=B, bit5=SELECT, bit4=START,
;                   bit3=UP, bit2=DOWN, bit1=LEFT, bit0=RIGHT
read_pads:
    ; 前フレームの状態を保存（ワンショット算出のため）
    lda pad1_raw
    sta pad1_prev
    lda pad2_raw
    sta pad2_prev

    ; ストローブ（$4016 に 1→0 を書くと両パッドがラッチされる）
    lda #$01
    sta JOYPAD1
    lda #$00
    sta JOYPAD1

    ; 8 ビット分を 1P / 2P コントローラーを同時にシフトイン
    ldx #$08
pad_loop:
    lda JOYPAD1             ; bit0 が今のボタン
    lsr a                   ; bit0 → キャリー
    rol pad1_raw            ; キャリーを pad1_raw に送り込む
    lda JOYPAD2
    lsr a
    rol pad2_raw
    dex
    bne pad_loop            ; 8 回ループ（A→B→SEL→START→U→D→L→R の順。
                            ;  結果として bit7=A, bit0=RIGHT の並びになる）

    ; ワンショット = 今フレーム & ～前フレーム
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
    .include "04_data.asm"
