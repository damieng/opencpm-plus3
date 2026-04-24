; SETDEF.COM — Configure system defaults
;
; Usage:
;   SETDEF                   show current settings
;   SETDEF [PAGE]            enable console page-mode
;   SETDEF [NOPAGE]          disable
;   SETDEF [DISPLAY]         enable SUBmit-line echo
;   SETDEF [NO DISPLAY]      disable
;   SETDEF [TEMPORARY=d:]    set temporary drive (d: = A:..P:, or 0: for default)
;
; Drive-list search path and [ORDER=(...)] are parsed but not yet
; consumed — SETDEF reports "not supported" for those.
;
; Build: sjasmplus --raw=build/setdef.com src/tools/setdef.asm

    ORG 0x0100

BDOS       equ 0x0005
F_COUT     equ 2
F_PRINT    equ 9
F_GETSCB   equ 49
F_CONMODE  equ 109

SCB_TEMPDRV equ 0x34

CON_MODE_PAGE    equ 0x01
CON_MODE_DISPLAY equ 0x02


start:
    ld a, (0x0080)
    ld b, a                    ; B = remaining chars
    ld hl, 0x0081              ; HL = current pos in tail
.skip_ws:
    ld a, b
    or a
    jp z, show_settings
    ld a, (hl)
    cp ' '
    jr nz, got_arg
    inc hl
    dec b
    jr .skip_ws

got_arg:
    cp '['
    jp nz, err_syntax
    inc hl
    dec b
    call parse_bracket
    jp done

done:
    rst 0


; parse_bracket — Copy uppercased bracket content to bracket_buf, match
;   against known directives and apply.
;   In: HL = first char after '[', B = remaining tail chars
parse_bracket:
    ld de, bracket_buf
    ld c, 0                    ; C = length
.copy:
    ld a, b
    or a
    jp z, err_syntax           ; no closing ']'
    ld a, (hl)
    cp ']'
    jr z, .terminated
    call upper
    ld (de), a
    inc de
    inc hl
    inc c
    dec b
    ld a, c
    cp BRACKET_BUF_MAX
    jp nc, err_syntax
    jr .copy
.terminated:
    xor a
    ld (de), a                 ; null-terminate

    ld de, str_page
    call match_exact
    jr nz, .n1
    ld a, CON_MODE_PAGE
    jp conmode_set
.n1:
    ld de, str_nopage
    call match_exact
    jr z, .do_nopage
    ld de, str_no_page
    call match_exact
    jr nz, .n2
.do_nopage:
    ld a, CON_MODE_PAGE
    jp conmode_clear
.n2:
    ld de, str_display
    call match_exact
    jr nz, .n3
    ld a, CON_MODE_DISPLAY
    jp conmode_set
.n3:
    ld de, str_nodisplay
    call match_exact
    jr z, .do_nodisplay
    ld de, str_no_display
    call match_exact
    jr nz, .n4
.do_nodisplay:
    ld a, CON_MODE_DISPLAY
    jp conmode_clear
.n4:
    ld de, str_temporary
    call match_prefix
    jr nz, .n5
    jp set_temporary           ; HL points past "TEMPORARY=" in bracket_buf
.n5:
    ld de, str_order
    call match_prefix
    jp z, err_not_supported
    jp err_syntax


; match_exact — Compare bracket_buf vs DE-terminated string (0 terminator).
;   Out: Z set if strings are equal, NZ otherwise.
match_exact:
    ld hl, bracket_buf
.loop:
    ld a, (de)
    cp (hl)
    ret nz
    or a
    ret z
    inc de
    inc hl
    jr .loop


; match_prefix — Check if DE-string is a prefix of bracket_buf.
;   Out: Z set if yes, HL points just past the matched prefix.
;        NZ otherwise.
match_prefix:
    ld hl, bracket_buf
.loop:
    ld a, (de)
    or a
    ret z                      ; end of DE-string → prefix match
    cp (hl)
    ret nz
    inc de
    inc hl
    jr .loop


; conmode_set — OR mask in A into con_mode.
conmode_set:
    push af
    ld de, 0xFFFF
    ld c, F_CONMODE
    call BDOS                  ; HL = current con_mode
    pop af
    or l
    ld l, a
    ex de, hl                  ; DE = new con_mode
    ld c, F_CONMODE
    call BDOS
    ret


; conmode_clear — AND ~mask in A into con_mode.
conmode_clear:
    push af
    ld de, 0xFFFF
    ld c, F_CONMODE
    call BDOS                  ; HL = current con_mode
    pop af
    cpl
    and l
    ld l, a
    ex de, hl                  ; DE = new con_mode
    ld c, F_CONMODE
    call BDOS
    ret


; set_temporary — Parse "X:" at HL and write to scb_tempdrv.
;   HL points at the first char after "TEMPORARY=" in bracket_buf.
set_temporary:
    ld a, (hl)
    cp '0'
    jr nz, .letter
    ; "0:" → reset to default (scb_tempdrv = 0)
    inc hl
    ld a, (hl)
    cp ':'
    jp nz, err_syntax
    inc hl
    ld a, (hl)
    or a
    jp nz, err_syntax
    xor a
    jr .write
.letter:
    sub 'A'
    jp c, err_syntax
    cp 16
    jp nc, err_syntax
    inc a                      ; 1..16 = A..P
    push af
    inc hl
    ld a, (hl)
    cp ':'
    jp nz, err_syntax
    inc hl
    ld a, (hl)
    or a
    jp nz, err_syntax
    pop af
.write:
    ld (scb_pb_set_tempdrv + 2), a
    ld de, scb_pb_set_tempdrv
    ld c, F_GETSCB
    call BDOS
    ret


show_settings:
    ; Page mode
    ld de, msg_page
    ld c, F_PRINT
    call BDOS
    ld de, 0xFFFF
    ld c, F_CONMODE
    call BDOS                  ; HL = con_mode
    push hl
    ld a, l
    and CON_MODE_PAGE
    call print_on_off

    ; Display mode
    ld de, msg_display
    ld c, F_PRINT
    call BDOS
    pop hl
    ld a, l
    and CON_MODE_DISPLAY
    call print_on_off

    ; Temporary drive
    ld de, msg_tempdrv
    ld c, F_PRINT
    call BDOS
    ld de, scb_pb_get_tempdrv
    ld c, F_GETSCB
    call BDOS                  ; HL low byte = scb_tempdrv
    ld a, l
    or a
    jr z, .default
    add a, 'A' - 1
    push af
    ld e, a
    ld c, F_COUT
    call BDOS
    ld e, ':'
    ld c, F_COUT
    call BDOS
    pop af
    jr .done
.default:
    ld de, msg_default
    ld c, F_PRINT
    call BDOS
.done:
    ld de, msg_crlf
    ld c, F_PRINT
    call BDOS
    jp done


print_on_off:
    or a
    jr z, .off
    ld de, msg_on
    ld c, F_PRINT
    jp BDOS
.off:
    ld de, msg_off
    ld c, F_PRINT
    jp BDOS


err_syntax:
    ld de, msg_syntax
    ld c, F_PRINT
    call BDOS
    rst 0

err_not_supported:
    ld de, msg_not_supported
    ld c, F_PRINT
    call BDOS
    rst 0


upper:
    cp 'a'
    ret c
    cp 'z' + 1
    ret nc
    sub 0x20
    ret


str_page:       db 'PAGE', 0
str_nopage:     db 'NOPAGE', 0
str_no_page:    db 'NO PAGE', 0
str_display:    db 'DISPLAY', 0
str_nodisplay:  db 'NODISPLAY', 0
str_no_display: db 'NO DISPLAY', 0
str_temporary:  db 'TEMPORARY=', 0
str_order:      db 'ORDER=', 0

msg_page:     db 'Page mode:       $'
msg_display:  db 0x0D, 0x0A, 'Display mode:    $'
msg_tempdrv:  db 0x0D, 0x0A, 'Temporary drive: $'
msg_default:  db 'default$'
msg_on:       db 'ON$'
msg_off:      db 'OFF$'
msg_crlf:     db 0x0D, 0x0A, '$'

msg_syntax:       db 'SETDEF: syntax error', 0x0D, 0x0A, '$'
msg_not_supported: db 'SETDEF: that form is not supported yet', 0x0D, 0x0A, '$'

scb_pb_get_tempdrv: db SCB_TEMPDRV, 0x00
scb_pb_set_tempdrv: db SCB_TEMPDRV, 0xFE, 0

BRACKET_BUF_MAX equ 32
bracket_buf:  ds BRACKET_BUF_MAX
