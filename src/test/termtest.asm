; TERMTEST.COM - Exercise the BIOS terminal escape-sequence parser
;
; Walks through the VT52/Z19-style sequences that our screen driver
; implements (see docs/cpm-plus-te-escape.md). Each test prints a
; header, runs the sequence, and waits for a key so you can eyeball
; the screen state before moving on.
;
; Build: sjasmplus --raw=build/termtest.com src/test/termtest.asm

    org 0x0100

BDOS    equ 0x0005

; BDOS function numbers
F_CONIN  equ 1      ; read char (blocking)
F_CONOUT equ 2      ; write char (from E)
F_PRINT  equ 9      ; print $-terminated string

; Control codes
ESC     equ 0x1B
CR      equ 0x0D
LF      equ 0x0A

; ============================================================
; Entry
; ============================================================
start:
    call clear_home
    ld de, title_str
    call pstr
    call wait_key

    call test_Y
    call test_ABCD
    call test_H
    call test_E
    call test_J
    call test_K
    call test_d
    call test_l
    call test_o
    call test_L
    call test_M
    call test_N
    call test_I
    call test_jk

    call clear_home
    ld de, done_str
    call pstr
    call wait_key
    jp 0x0000                   ; warm boot

; ============================================================
; Tests
; ============================================================

; ---- ESC Y r c - absolute cursor position ----
test_Y:
    call clear_home
    ld de, hdr_Y
    call pstr
    ; Corners of a box (rows 6..16, cols 10..40) using ESC Y
    ld d, 6
    ld e, 10
    call set_cur
    ld a, '+'
    call cout
    ld d, 6
    ld e, 40
    call set_cur
    ld a, '+'
    call cout
    ld d, 16
    ld e, 10
    call set_cur
    ld a, '+'
    call cout
    ld d, 16
    ld e, 40
    call set_cur
    ld a, '+'
    call cout
    ; Label the corners
    ld d, 7
    ld e, 12
    call set_cur
    ld de, lbl_Y
    call pstr
    call footer_wait
    ret

; ---- ESC A/B/C/D - relative cursor movement ----
test_ABCD:
    call clear_home
    ld de, hdr_ABCD
    call pstr
    ; Drop a '*' at (10, 25) and draw a '+' sign with '.' dots.
    ;
    ; Each cout advances the cursor by 1, so after 'esc_X' + 'cout .'
    ; the cursor ends up one column PAST where we want the next dot.
    ; Precede the next esc_X with an extra esc_D (or start from a
    ; position one column left) to compensate.
    ld d, 10
    ld e, 25
    call set_cur
    ld a, '*'
    call cout               ; cursor now (10, 26)

    ; UP arm: (9..7, 25) via ESC A + ESC D to hold column
    call esc_D              ; (10, 25)
    call esc_A              ; (9, 25)
    ld a, '.'
    call cout               ; cursor (9, 26)
    call esc_D
    call esc_A              ; (8, 25)
    ld a, '.'
    call cout
    call esc_D
    call esc_A              ; (7, 25)
    ld a, '.'
    call cout

    ; DOWN arm: (11..13, 25) via ESC B + ESC D
    ld d, 10
    ld e, 25
    call set_cur
    call esc_B              ; (11, 25)
    ld a, '.'
    call cout
    call esc_D
    call esc_B              ; (12, 25)
    ld a, '.'
    call cout
    call esc_D
    call esc_B              ; (13, 25)
    ld a, '.'
    call cout

    ; RIGHT arm: (10, 26..28) via ESC C + ESC D to cancel cout advance
    ld d, 10
    ld e, 25
    call set_cur
    call esc_C              ; (10, 26)
    ld a, '.'
    call cout               ; cursor (10, 27)
    call esc_D              ; (10, 26)
    call esc_C              ; (10, 27)
    ld a, '.'
    call cout
    call esc_D
    call esc_C              ; (10, 28)
    ld a, '.'
    call cout

    ; LEFT arm: (10, 24..22) via two ESC Ds per dot (one undoes cout)
    ld d, 10
    ld e, 25
    call set_cur
    call esc_D              ; (10, 24)
    ld a, '.'
    call cout               ; cursor (10, 25)
    call esc_D
    call esc_D              ; (10, 23)
    ld a, '.'
    call cout
    call esc_D
    call esc_D              ; (10, 22)
    ld a, '.'
    call cout
    call footer_wait
    ret

; ---- ESC H - home cursor ----
test_H:
    call clear_home
    ld de, hdr_H
    call pstr
    ; Move cursor far away, then ESC H - 'H' should print at (0, 0)
    ld d, 15
    ld e, 45
    call set_cur
    ld a, ESC
    call cout
    ld a, 'H'
    call cout
    ld a, 'H'                   ; now at home
    call cout
    call footer_wait
    ret

; ---- ESC E - clear viewport, cursor unchanged ----
test_E:
    call clear_home
    ld de, hdr_E
    call pstr
    call wait_key
    ; Fill a bunch of lines with digits
    call fill_marker
    call wait_key
    ; Now ESC E - everything should vanish; cursor stays put
    ld a, ESC
    call cout
    ld a, 'E'
    call cout
    ld de, after_E
    call pstr
    call footer_wait
    ret

; ---- ESC J - clear cursor to end of screen ----
test_J:
    call clear_home
    ld de, hdr_J
    call pstr
    call fill_marker
    ; Move to row 8 col 0, clear-to-end
    ld d, 8
    ld e, 0
    call set_cur
    ld a, ESC
    call cout
    ld a, 'J'
    call cout
    call footer_wait
    ret

; ---- ESC K - clear cursor to end of line ----
test_K:
    call clear_home
    ld de, hdr_K
    call pstr
    call fill_marker
    ; Move to row 10 col 20, clear-to-EOL
    ld d, 10
    ld e, 20
    call set_cur
    ld a, ESC
    call cout
    ld a, 'K'
    call cout
    call footer_wait
    ret

; ---- ESC d - clear top-of-screen to cursor ----
test_d:
    call clear_home
    ld de, hdr_d
    call pstr
    call fill_marker
    ld d, 8
    ld e, 20
    call set_cur
    ld a, ESC
    call cout
    ld a, 'd'
    call cout
    call footer_wait
    ret

; ---- ESC l - erase current line ----
test_l:
    call clear_home
    ld de, hdr_l
    call pstr
    call fill_marker
    ld d, 10
    ld e, 15
    call set_cur
    ld a, ESC
    call cout
    ld a, 'l'
    call cout
    call footer_wait
    ret

; ---- ESC o - clear start-of-line to cursor ----
test_o:
    call clear_home
    ld de, hdr_o
    call pstr
    call fill_marker
    ld d, 12
    ld e, 25
    call set_cur
    ld a, ESC
    call cout
    ld a, 'o'
    call cout
    call footer_wait
    ret

; ---- ESC L - insert line at cursor ----
test_L:
    call clear_home
    ld de, hdr_L
    call pstr
    call fill_marker
    ld d, 8
    ld e, 0
    call set_cur
    ld a, ESC
    call cout
    ld a, 'L'
    call cout
    ld de, inserted_str
    call pstr
    call footer_wait
    ret

; ---- ESC M - delete line at cursor ----
test_M:
    call clear_home
    ld de, hdr_M
    call pstr
    call fill_marker
    ld d, 8
    ld e, 0
    call set_cur
    ld a, ESC
    call cout
    ld a, 'M'
    call cout
    call footer_wait
    ret

; ---- ESC N - delete char under cursor ----
test_N:
    call clear_home
    ld de, hdr_N
    call pstr
    ld d, 9
    ld e, 10
    call set_cur
    ld de, abc_before
    call pstr                   ; shows "ABC" + arrow pointing at B
    ld d, 10
    ld e, 10
    call set_cur
    ld de, abc_str              ; prints "ABC" at (10, 10)
    call pstr
    ld d, 10
    ld e, 11                    ; put cursor on 'B'
    call set_cur
    ld a, ESC
    call cout
    ld a, 'N'
    call cout                   ; expect "AC" at (10, 10)
    ld d, 11
    ld e, 10
    call set_cur
    ld de, abc_after
    call pstr
    call footer_wait
    ret

; ---- ESC I - reverse index (cursor up, scroll DOWN if at top) ----
test_I:
    call clear_home
    ld de, hdr_I
    call pstr
    call fill_marker
    ; Go to (0, 0), then ESC I - row 0 should push rows 1..23 down
    ld d, 0
    ld e, 0
    call set_cur
    ld a, ESC
    call cout
    ld a, 'I'
    call cout
    ld de, pushed_down
    call pstr
    call footer_wait
    ret

; ---- ESC j / ESC k - save and restore cursor ----
test_jk:
    call clear_home
    ld de, hdr_jk
    call pstr
    ; Move to (10, 20), save, write something, move away, restore, write '*'
    ld d, 10
    ld e, 20
    call set_cur
    ld a, ESC
    call cout
    ld a, 'j'
    call cout                   ; save
    ld de, saved_here
    call pstr
    ld d, 5
    ld e, 5
    call set_cur
    ld de, moved_here
    call pstr
    ld a, ESC
    call cout
    ld a, 'k'
    call cout                   ; restore
    ld a, '*'                   ; should land right after "saved_here"
    call cout
    call footer_wait
    ret

; ============================================================
; Helpers
; ============================================================

; cout - write A via BDOS CONOUT (preserves AF/BC/DE/HL)
cout:
    push af
    push bc
    push de
    push hl
    ld e, a
    ld c, F_CONOUT
    call BDOS
    pop hl
    pop de
    pop bc
    pop af
    ret

; pstr - print $-terminated string at DE (preserves BC/HL)
pstr:
    push bc
    push hl
    ld c, F_PRINT
    call BDOS
    pop hl
    pop bc
    ret

; wait_key - block on a keystroke
wait_key:
    push af
    push bc
    push de
    push hl
    ld c, F_CONIN
    call BDOS
    pop hl
    pop de
    pop bc
    pop af
    ret

; clear_home - ESC E then ESC H
clear_home:
    ld a, ESC
    call cout
    ld a, 'E'
    call cout
    ld a, ESC
    call cout
    ld a, 'H'
    call cout
    ret

; set_cur - move cursor to row D, col E via ESC Y <r+32> <c+32>
set_cur:
    ld a, ESC
    call cout
    ld a, 'Y'
    call cout
    ld a, d
    add a, 0x20
    call cout
    ld a, e
    add a, 0x20
    call cout
    ret

; esc_A/B/C/D - emit ESC <letter>
esc_A:
    ld a, ESC
    call cout
    ld a, 'A'
    jp cout
esc_B:
    ld a, ESC
    call cout
    ld a, 'B'
    jp cout
esc_C:
    ld a, ESC
    call cout
    ld a, 'C'
    jp cout
esc_D:
    ld a, ESC
    call cout
    ld a, 'D'
    jp cout

; footer_wait - bottom prompt + wait
footer_wait:
    ld d, 23
    ld e, 0
    call set_cur
    ld de, press_any
    call pstr
    jp wait_key

; fill_marker - fill rows 2..18 with a digit-ruler pattern
fill_marker:
    ld d, 2
.fill_row:
    ld a, d
    cp 19
    ret z
    ld e, 0
    call set_cur
    push de
    ld b, 50
    ld a, d
    add a, '0'
    and 0x7F
    ld c, a
.fill_col:
    ld a, c
    push bc
    call cout
    pop bc
    djnz .fill_col
    pop de
    inc d
    jr .fill_row

; ============================================================
; Strings ($-terminated)
; ============================================================

title_str:
    db "termtest - BIOS escape-sequence regression", CR, LF
    db "Press any key between each test.", CR, LF, '$'

hdr_Y:       db "Test ESC Y: four '+' marks at the box corners.$"
lbl_Y:       db "ESC Y positions cursor in absolute coords$"

hdr_ABCD:    db "Test ESC A/B/C/D: '*' centre, '.' arms.$"

hdr_H:       db "Test ESC H: an 'H' should appear at top-left.$"

hdr_E:       db "Test ESC E: fills screen, press key, then clears.$"
after_E:     db "cleared - cursor stayed put$"

hdr_J:       db "Test ESC J: fills, then clears from row 8 onward.$"
hdr_K:       db "Test ESC K: fills, then clears row 10 from col 20.$"
hdr_d:       db "Test ESC d: clears top-of-screen up to (8, 20).$"
hdr_l:       db "Test ESC l: erases row 10 entirely.$"
hdr_o:       db "Test ESC o: clears row 12 from col 0 to col 25.$"
hdr_L:       db "Test ESC L: inserts a blank line at row 8.$"
inserted_str:db "<-- inserted line$"
hdr_M:       db "Test ESC M: deletes row 8; rows below shift up.$"
hdr_N:       db "Test ESC N: delete char under cursor (the 'B').$"
abc_before:  db "ABC    <-- before (cursor on B)$"
abc_str:     db "ABC$"
abc_after:   db "AC     <-- after ('B' deleted, 'C' shifted left)$"
hdr_I:       db "Test ESC I: at row 0, push content down one row.$"
pushed_down: db "<- row 0 after ESC I$"
hdr_jk:      db "Test ESC j/k: save cursor, move, restore, print '*'.$"
saved_here:  db "saved here$"
moved_here:  db "moved away$"

press_any:   db "[press any key]$"

done_str:
    db "All tests done. Press a key to return to CP/M.", CR, LF, '$'
