; 01_show_sprite.asm - 画面中央に白いスプライトを1枚表示する
; ビルド: asm6f 01_show_sprite.asm 01_show_sprite.nes

; ===== iNES ヘッダ =====
    .db "NES", $1a
    .db $01          ; PRG-ROM 16KB x 1
    .db $01          ; CHR-ROM  8KB x 1
    .db $00, $00     ; mapper 0, 水平ミラーリング
    .db $00, $00, $00, $00, $00, $00, $00, $00

; ===== PRG-ROM (16KB, $C000-$FFFF にマップ) =====
    .base $c000

reset:
    sei                         ; IRQ を無効化（初期化中に割り込まれないように）
    cld                         ; デシマルモード無効（ファミコンの 6502 は非対応だが念のため）
    ldx #$40                    ; X = $40
    stx $4017                   ; APUFRAME $4017 = $40。APU フレーム IRQ を無効化
    ldx #$ff                    ; X = $FF
    txs                         ;   → スタックポインタ = $FF（スタック $01FF から下へ積む）
    inx                         ; X = 0（次で各レジスタを 0 クリアするため）
    stx $2000                   ; PPUCTRL $2000 = 0（NMI オフ）
    stx $2001                   ; PPUMASK $2001 = 0（描画オフ）
    stx $4010                   ; DMCFREQ $4010 = 0（DMC IRQ 無効）

    bit $2002                   ; 起動時に残っている VBlank フラグを消しておく

    ; 1 回目の VBlank 待ち
vblankwait1:
    bit $2002                   ; PPUSTATUS $2002 の bit7 を N フラグへ転送
    bpl vblankwait1             ; bit7=0（非VBlank）ならループ

    ; RAM クリア ($0000-$07FF)
clrmem:
    lda #$00                    ; A = 0（クリア用の値）
    sta $0000, x                ; $0000-$00FF を 0 クリア
    sta $0100, x                ; $0100-$01FF（スタック）を 0 クリア
    sta $0300, x                ; $0300-$03FF を 0 クリア
    sta $0400, x                ; $0400-$04FF を 0 クリア
    sta $0500, x                ; $0500-$05FF を 0 クリア
    sta $0600, x                ; $0600-$06FF を 0 クリア
    sta $0700, x                ; $0700-$07FF を 0 クリア
    lda #$fe                    ; A = $FE（OAM の Y 座標 = 画面外にして非表示）
    sta $0200, x                ; OAM シャドウ $0200-$02FF を埋める
    inx                         ; X++
    bne clrmem                  ; X が 0 に戻るまで（256 バイト分）ループ

    ; 2 回目の VBlank 待ち（PPU が安定するまで）
vblankwait2:
    bit $2002                   ; PPUSTATUS bit7 を N フラグへ
    bpl vblankwait2             ; VBlank になるまで待つ

    ; パレットを PPU に転送 ($3F00-$3F1F)
    lda #$3f                    ; PPU アドレス上位
    sta $2006                   ; PPUADDR $2006 へ（1 回目）
    lda #$00                    ; PPU アドレス下位
    sta $2006                   ; PPUADDR $2006 へ（2 回目。これで $3F00 を指す）
    ldx #$00                    ; X = 0（パレットテーブル内のインデックス）
palloop:
    lda palette, x              ; A = palette[X]
    sta $2007                   ; PPUDATA $2007 へ（書くたびに PPU アドレスは自動インクリメント）
    inx                         ; X++
    cpx #$20                    ; 32 バイト書いたか？
    bne palloop                 ; まだならループ

    ; スプライト 0 番を OAM シャドウ にセット
    lda #$78                    ; Y = 120
    sta $0200                   ;   → OAM[0] (Y)
    lda #$01                    ; タイル番号 1（白い四角）
    sta $0201                   ;   → OAM[1] (タイル)
    lda #$00                    ; 属性 = 0（スプライトパレット 0）
    sta $0202                   ;   → OAM[2] (属性)
    lda #$78                    ; X = 120
    sta $0203                   ;   → OAM[3] (X)

    ; NMI 有効化・スプライト表示 ON
    lda #%10000000              ; bit7=1: NMI 有効、スプライトは $0000 側の CHR を使用
    sta $2000                   ; PPUCTRL $2000
    lda #%00010000              ; bit4=1: スプライト表示 ON
    sta $2001                   ; PPUMASK $2001

forever:
    jmp forever                 ; メインは何もせず待機（描画は NMI 任せ）

; ===== NMI =====
nmi:
    lda #$00                    ; A = 0
    sta $2003                   ; OAMADDR $2003 = 0（OAM の先頭から書き込む）
    lda #$02                    ; A = $02（OAM シャドウ $0200 の上位バイト）
    sta $4014                   ; OAMDMA $4014 に書き込むと DMA 開始: $0200-$02FF → OAM
    rti                         ; 割り込みから復帰

irq:
    rti                         ; IRQ は使わないので即復帰

; ===== パレット =====
palette:
    ; BG パレット（未使用だがダミーで埋める）
    .db $0f, $00, $10, $30
    .db $0f, $00, $10, $30
    .db $0f, $00, $10, $30
    .db $0f, $00, $10, $30
    ; スプライトパレット 0 : 色 1 = $30（白）
    .db $0f, $30, $10, $00
    .db $0f, $30, $10, $00
    .db $0f, $30, $10, $00
    .db $0f, $30, $10, $00

; ===== 割り込みベクタ =====
    .pad $fffa
    .dw nmi                     ; $FFFA-$FFFB: NMI ベクタ
    .dw reset                   ; $FFFC-$FFFD: RESET ベクタ
    .dw irq                     ; $FFFE-$FFFF: IRQ/BRK ベクタ

; ===== CHR-ROM ($0000-$1FFF) =====
chr_start:
    ; タイル 0 : 透明（全ビット 0）
    .db $00, $00, $00, $00, $00, $00, $00, $00
    .db $00, $00, $00, $00, $00, $00, $00, $00
    ; タイル 1 : 8x8 べた塗り（下位プレーン=1, 上位プレーン=0 → 色 1）
    .db $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff
    .db $00, $00, $00, $00, $00, $00, $00, $00

    ; CHR 残り（8KB まで）を 0 で埋める
    .dsb $2000 - ($ - chr_start), $00
