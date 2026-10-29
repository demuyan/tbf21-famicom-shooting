; macros.inc - 共通マクロ
;   asm6f のマクロ構文: 「MACRO 名前 引数1, 引数2, ...」 ... 「ENDM」

; ADD16 dst_lo, dst_hi, src_lo, src_hi
;   (dst_hi:dst_lo) += (src_hi:src_lo)
;   16bit の符号付き／符号無し共用の加算。A レジスタを破壊する。
MACRO ADD16 dst_lo, dst_hi, src_lo, src_hi
    clc
    lda dst_lo
    adc src_lo
    sta dst_lo
    lda dst_hi
    adc src_hi
    sta dst_hi
ENDM

; SUB16 dst_lo, dst_hi, src_lo, src_hi
;   (dst_hi:dst_lo) -= (src_hi:src_lo)
;   16bit の符号付き／符号無し共用の減算。A レジスタを破壊する。
MACRO SUB16 dst_lo, dst_hi, src_lo, src_hi
    sec
    lda dst_lo
    sbc src_lo
    sta dst_lo
    lda dst_hi
    sbc src_hi
    sta dst_hi
ENDM
