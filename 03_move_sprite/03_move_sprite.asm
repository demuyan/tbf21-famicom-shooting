; 03_move_sprite.asm - 1P コントローラーの十字ボタンでスプライトを動かす（02 のスタイルで整理）
;   - iNES ヘッダを ines.inc に分離
;   - I/O レジスタ定義を fc.inc に集約
;   - ファミコン共通の初期化を fc_init.asm (init_fc) に分離
;   - アプリ固有の初期化は init_app にまとめる
;   - パレット / CHR データを 03_data.asm に分離
; ビルド: asm6f 03_move_sprite.asm 03_move_sprite.nes

    .include "../lib/ines.inc"
    .include "../lib/fc.inc"

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
    jsr setup_sprite
    jsr enable_ppu
    rts

; ===== パレットを PPU ($3F00-$3F1F) に転送 =====
load_palette:
    lda #$3f
    sta PPUADDR             ; PPU アドレス上位
    lda #$00
    sta PPUADDR             ; PPU アドレス下位（ $3F00 指定完了）
    ldx #$00
palloop:
    lda palette, x
    sta PPUDATA             ; PPU アドレスは自動インクリメント
    inx
    cpx #$20
    bne palloop
    rts

; ===== スプライト 0 番を OAM シャドウにセット =====
setup_sprite:
    lda #$78
    sta OAM_BUF+0           ; Y = 120
    lda #$01
    sta OAM_BUF+1           ; タイル番号 1（白い四角）
    lda #$00
    sta OAM_BUF+2           ; 属性 = スプライトパレット 0
    lda #$78
    sta OAM_BUF+3           ; X = 120
    rts

; ===== PPU 描画 ON ・ NMI 有効化 =====
enable_ppu:
    lda #%10000000          ; NMI 有効、スプライトは $0000 側の CHR を使用
    sta PPUCTRL
    lda #%00010100          ; スプライト表示 ON（左端 8 ピクセルも表示）
    sta PPUMASK
    rts

; ===== NMI =====
nmi:
    ; OAM DMA: OAM シャドウ ($0200-$02FF) を OAM へ一括転送
    lda #$00
    sta OAMADDR
    lda #>OAM_BUF
    sta OAMDMA

    jsr move_sprite_by_pad1
    rti

; ===== 1P コントローラーの十字ボタン入力でスプライトを移動 =====
; $4016 から 1 回読むごとに 1 ボタン分 (bit0) が取れる。
; 順番は A, B, SELECT, START, UP, DOWN, LEFT, RIGHT
move_sprite_by_pad1:
    ; ストローブ
    lda #$01
    sta JOYPAD1             ; ラッチ開始
    lda #$00
    sta JOYPAD1             ; ラッチ完了、シフトレジスタ読み出し可

    ; A, B, SELECT, START は使わないので読み飛ばし
    lda JOYPAD1
    lda JOYPAD1
    lda JOYPAD1
    lda JOYPAD1

    ; UP
    lda JOYPAD1
    and #$01                ; bit0 だけ残す
    beq not_up
    dec OAM_BUF+0           ; Y -= 1（上）
not_up:
    ; DOWN
    lda JOYPAD1
    and #$01
    beq not_down
    inc OAM_BUF+0           ; Y += 1（下）
not_down:
    ; LEFT
    lda JOYPAD1
    and #$01
    beq not_left
    dec OAM_BUF+3           ; X -= 1（左）
not_left:
    ; RIGHT
    lda JOYPAD1
    and #$01
    beq not_right
    inc OAM_BUF+3           ; X += 1（右）
not_right:
    rts

irq:
    rti

; ===== パレット / 割り込みベクタ / CHR-ROM =====
    .include "03_data.asm"
