; 02_show_sprite.asm - 01 と同じ「白いスプライトを中央に表示」を、読みやすく整理した版
;   - iNES ヘッダを ines.inc に分離
;   - I/O レジスタ定義を fc.inc に集約
;   - ファミコン共通の初期化を fc_init.asm (init_fc) に分離
;   - アプリ固有の初期化は init_app にまとめる
;   - パレット / CHR データを 02_data.asm に分離
; ビルド: asm6f 02_show_sprite.asm 02_show_sprite.nes

    .include "../lib/ines.inc"
    .include "../lib/fc.inc"

; ===== PRG-ROM (16KB, $C000-$FFFF にマップ) =====
    .base $c000

; ===== エントリポイント =====
reset:
    sei                     ; IRQ 無効
    cld                     ; デシマルモード無効
    ldx #$ff
    txs                     ; スタックポインタ = $FF（必ず jsr より前に）
    jsr init_fc             ; ファミコン共通の初期化
    jsr init_app            ; このアプリの表示用初期化

forever:
    jmp forever             ; メインは待機、描画は NMI 任せ

; ===== ファミコン共通の初期化（使い回し可能） =====
    .include "../lib/fc_init.asm"

; ===== アプリ固有の初期化 =====
init_app:
    jsr load_palette        ; パレットを PPU に転送
    jsr setup_sprite        ; スプライト 0 を配置
    jsr enable_ppu          ; NMI 有効化・描画 ON
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
    lda #%00010000          ; スプライト表示 ON
    sta PPUMASK
    rts

; ===== NMI: OAM シャドウを OAM へ DMA 転送 =====
nmi:
    lda #$00
    sta OAMADDR             ; OAM の先頭から書き込む
    lda #>OAM_BUF
    sta OAMDMA              ; OAM DMA 開始: $0200-$02FF → OAM
    rti

irq:
    rti

; ===== パレット / 割り込みベクタ / CHR-ROM =====
    .include "02_data.asm"
