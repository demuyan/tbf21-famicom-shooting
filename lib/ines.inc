; ines.inc - iNES ヘッダ (mapper 0 / PRG 16KB / CHR 8KB / 水平ミラーリング)

    .db "NES", $1a
    .db $01          ; PRG-ROM 16KB x 1
    .db $01          ; CHR-ROM  8KB x 1
    .db $00, $00     ; mapper 0, 水平ミラーリング
    .db $00, $00, $00, $00, $00, $00, $00, $00
