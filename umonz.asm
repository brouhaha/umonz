; umonz.asm
; RAMless Z80 monitor
; Copyright 2022 Eric Smith <spacewar@gmail.com>
; SPDX-License-Identifier: GPL-3.0-only

	cpu	z80


; features

use_mmap	equ	0	; set for RC2014 512K Flash/RAM style mapper


; macros for RAM-less subroutine call/return

ixcall	macro	target
	ld	ix,retaddr
	jp	target
retaddr:
	endm

ixret	macro
	jp	(ix)
	endm

iycall	macro	target
	ld	iy,retaddr
	jp	target
retaddr:
	endm

iyret	macro
	jp	(iy)
	endm

	
; memory bank mapping ports

p_bank0	equ	078h		; bank 0 mapping (0000..3fff)
p_bank1	equ	p_bank0+1	; bank 1 mapping (4000..7fff)
p_bank2	equ	p_bank0+2	; bank 2 mapping (4000..7fff)
p_bank3	equ	p_bank0+3	; bank 3 mapping (4000..7fff)
p_bnken	equ	p_bank0+4	; 0 to disable banking, 1 to enable


; character definitions
c_etx	equ	003h		; control-C
c_cr	equ	00dh
c_lf	equ	00ah


ramloc		equ	8000h

	org	0000h

reset:	di
	ld	sp,0ffffh

	if	use_mmap
	ixcall	bank_setup
	endif

	ixcall	console_setup

	ixcall	msg_out_inline
	db	"umonz 0.1",000h

mloop_crlf:
	ixcall	crlf_out

mloop:
	ixcall	msg_out_inline
	db	">",000h

mloop2:
	iycall	char_in
	iycall	downcase

	ixcall	dispatch

	db	':'
	dw	cmd_ihex

	db	'u'
	dw	cmd_ihex_up

	db	'd'
	dw	cmd_dump

	db	'r'
	dw	cmd_read

	db	'w'
	dw	cmd_write

	db	'c'
	dw	cmd_copy

	db	'i'
	dw	cmd_input

	db	'o'
	dw	cmd_output

	db	'g'
	dw	cmd_go

	db	'h'
	dw	cmd_halt

	db	c_etx		; Control-C is a null command
	dw	mloop_crlf

	db	c_cr		; CR is a null command
	dw	mloop_crlf

	db	c_lf		; completely ignore line feed
	dw	mloop2

	db	0		; end of table

	ixcall	msg_out_inline
	db	c_cr,c_lf,"unrecognized command",c_cr,c_lf,000h
	jr	mloop


cmd_dump:
	ixcall	msg_out_inline
	db	"dump ",000h
	ixcall	hex16_in	; get start addr into HL
	ld	d,h		; save start addr into DE
	ld	e,l
	ld	a,'-'
	iycall	char_out
	ixcall	hex16_in	; get end addr into HL
	ex	de,hl		; now HL is start, DE is end

dump_addr:
	ixcall	crlf_out
	ixcall	hex16_out
	ld	a,':'
	iycall	char_out

dump_byte:
	ld	a,' '
	iycall	char_out
	ld	a,(hl)
	ixcall	hex8_out

	ld	a,h
	xor	d
	jr	nz,dump_next
	ld	a,l
	xor	e
	jr	nz,dump_next
	jp	mloop_crlf

dump_next:
	iycall	char_avail	; is there a received character?
	jr	z,dump_next2
	iycall	char_in
	cp	a,c_etx		; is it control-C?
	jp	z,mloop_crlf	; yes, end command

dump_next2:
	inc	hl		; advance pointer
	ld	a,l		; 16-byte boundary?
	and	00fh
	jr	z,dump_addr	; yes, end line and print address
	jr	dump_byte	; no, proceed to next byte


cmd_read:
	ixcall	msg_out_inline
	db	"read ",000h
	ixcall	hex16_in
	ixcall	crlf_out
	ixcall	hex16_out
	ld	a,':'
	iycall	char_out
	ld	a,' '
	iycall	char_out
	ld	a,(hl)
	ixcall	hex8_out

	jp	mloop_crlf


cmd_write:
	ixcall	msg_out_inline
	db	"write ",000h
	ixcall	hex16_in
	ld	d,h
	ld	e,l
	ld	a,'='

cmd_write_loop:
	iycall	char_out
	ixcall	hex8_in_opt
	ld	a,l
	ld	(de),a
	inc	de
	ld	a,' '
	jr	cmd_write_loop


cmd_copy:
	ixcall	msg_out_inline		; get source start into DE and HL
	db	"copy from ",000h
	ixcall	hex16_in
	ld	sp,hl			; SP=src
	ex	de,hl			; DE=src SP=src

	ld	a,'-'			; get source end (inclusive) into HL
	iycall	char_out
	ixcall	hex16_in
	inc	hl			; change end to exclusive
	or	a			; subtract start to get byte count
	sbc	hl,de			; DE=src HL=count SP=src 

	ex	de,hl			; DE=count HL=src SP=src

	ixcall	msg_out_inline		; get destination address into HL
	db	" to ",000h
	ixcall	hex16_in		; DE=count HL=dest SP=src

	ld	b,d
	ld	c,e			; BC=count DE=count HL=dest SP=src

	ex	de,hl			; BC=count DE=dest HL=count SP=src

	ld	hl,0
	add	hl,sp			; BC=count DE=dest HL=src

	ldir				; copy

	jp	mloop_crlf


cmd_input:
	ixcall	msg_out_inline
	db	"input ",000h
	ixcall	hex8_in
	ixcall	crlf_out
	ld	a,l
	ixcall	hex8_out
	ld	a,':'
	iycall	char_out
	ld	a,' '
	iycall	char_out
	ld	c,l
	in	a,(c)
	ixcall	hex8_out

	jp	mloop_crlf


cmd_output:
	ixcall	msg_out_inline
	db	"output ",000h
	ixcall	hex8_in
	ld	e,l
	ld	a,'='

cmd_output_loop:
	iycall	char_out
	ixcall	hex8_in_opt
	ld	c,e
	out	(c),l
	ld	a,' '
	jr	cmd_output_loop


cmd_go:
	ixcall	msg_out_inline
	db	"go ",000h
	ixcall	hex16_in
	ixcall	crlf_out
	jp	(hl)


cmd_halt:
	ixcall	msg_out_inline
	db	"halt",c_cr,c_lf,000h
	halt


cmd_ihex:
	xor	a		; initialize checksum
	ld	i,a

	ixcall	ihex8_in	; get byte count into D
	ld	d,a

	ixcall	ihex8_in	; get address into HL
	ld	h,a
	ixcall	ihex8_in
	ld	l,a

	ixcall	ihex8_in	; get record type
	or	a		; is it a data record?
	jr	nz,ihex_not_data

ihex_next_byte:
	ixcall	ihex8_in	; get a data byte
	ld	(hl),a
	inc	hl

	dec	d		; decrement and test byte count
	jr	nz,ihex_next_byte
	
	ixcall	ihex8_in	; get checksum byte

	ld	a,i		; is the checksum correct?
	jr	nz,ihex_bad_checksum

	iycall	char_in		; next character should be carriage return
	cp	c_cr
	jp	z,mloop2	;   yes, return (silently) to main loop

skip_line:
	ld	a,'%'
	iycall	char_out

	iycall	char_in
	cp	c_etx
	jp	z,mloop_crlf
	cp	c_cr
	jr	nz,skip_line
	jp	mloop2

ihex_not_data:
	cp	a,01h
	jr	nz,ihex_bad_rec_type

ihex_bad_char:
	ixcall	msg_out_inline
	db	"bad char in hex file",000h
	jr	skip_line

ihex_bad_checksum:
	ixcall	msg_out_inline
	db	"bad checksum in hex file",000h
	jr	skip_line

ihex_bad_rec_type:
	ixcall	msg_out_inline
	db	"bad record type in hex file",000h
	jp	skip_line


cmd_ihex_up:
	ixcall	msg_out_inline
	db	"upload ",000h
	ixcall	hex16_in	; get start addr into HL
	ld	d,h		; save start addr into DE
	ld	e,l
	ld	a,'-'
	iycall	char_out
	ixcall	hex16_in	; get end addr into HL
	inc	hl		; user entered end in inclusive, increment to make it exclusive
	ex	de,hl		; now HL is start, DE is end

idump_rec:
	ixcall	crlf_out
	ld	a,':'
	iycall	char_out

	xor	a		; initialize checksum
	ld	i,a

	iycall	idump_get_rec_len	; output record length
	ixcall	ihex8_out

	ld	a,h		; output address
	ixcall  ihex8_out
	ld	a,l
	ixcall  ihex8_out

	xor	a		; output record type 00 = data
	ixcall	ihex8_out

	iycall	idump_get_rec_len	; get record length into B
	ld	b,a

idump_byte:
	ld	a,i		; update checksum
	add	a,(hl)
	ld	i,a

; can't use ihex8_out in the inner loop because it destroys B
	ld	a,(hl)		; output MSD
	rrca			; shift MSD to LSD
	rrca
	rrca
	rrca
	iycall	ihexdig_out
	
	ld	a,(hl)		; output LSD
	iycall	ihexdig_out

	inc	hl
	djnz	idump_byte

	ld	a,i		; output checksum
	neg
	ixcall	ihex8_out

	iycall	char_avail	; is there a received character?
	jr	z,idump_next
	iycall	char_in
	cp	a,c_etx		; is it control-C?
	jp	z,mloop_crlf	; yes, end command

idump_next:
	ld	a,h		; at end of range?
	xor	d
	jp	nz,idump_rec
	ld	a,l
	xor	e
	jp	nz,idump_rec

; output end record
	ixcall	crlf_out

	ld	a,':'
	iycall	char_out

	xor	a		; init checksum
	ld	i,a

	xor	a		; record length
	ixcall	ihex8_out

	xor	a		; address
	ixcall	ihex8_out
	xor	a
	ixcall	ihex8_out

	ld	a,01h		; record type
	ixcall	ihex8_out

	ld	a,i		; output checksum
	neg
	ixcall	ihex8_out

	jp	mloop_crlf


; on entry:
;    HL contains current address
;    DE comtains limit address
;    IY contains return address
; on return:
;    HL, DE unchanged
;    A contains record length, max 16 bytes
idump_get_rec_len:
	or	a		; clear carry
	ex	de,hl		; DE=cur, HL=limit
	sbc	hl,de		; DE=cur, HL=count

	ld	a,h		; if high byte of end-cur != 0, clip to 10
	or	a
	jr	nz,rec_len_10

	ld	a,l		; if low byte is less than 10 use it as-is
	cp	a,10h
	jr	c,rec_len_not_10

rec_len_10:
	ld	a,10h

rec_len_not_10:
	add	hl,de		; restore current address
	ex	de,hl
	iyret


; on entry:
;    A contains character
;    I contains running checksum
;    IY contains return address
; on exit
;    A unchanged (character)
;    I checksum updated
;    B destroyed
update_checksum:
	ld	b,a
	ld	a,i
	add	a,b
	ld	i,a
	ld	a,b
	iyret


; on entry:
;    A contains character
;    IX points to table
; on exit, if a matching table entry was found:
;    B, IY destroyed
;    jumps to address in table entry (no return)
; on exit, no matching table entry found:
;    B, IY destroyed
;    returns to caller (after table)
dispatch:
	ld	b,a
	xor	a
	or	(ix)
	jr	z,d_table_end

	ld	a,b
	cp	(ix)
	inc	ix
	jr	z,d_found

	inc	ix
	inc	ix
	jr	dispatch

d_found:
	ld	sp,ix
	ret

d_table_end:
	inc	ix
	jp	(ix)
	

; on entry:
;    IX contains return address
; on return:
;    A, C, IY destroyed
crlf_out:
	ld	a,c_cr
	iycall	char_out
	ld	a,c_lf
	iycall	char_out
	ixret


; on entry:
;    IX points to message string (null terminated), followed by return point
; on return:
;    A, C, IY destroyed
msg_out_inline:

msg_inline_loop:
	ld	a,(ix)
	inc	ix
	or	a
	jr	z,msg_inline_done

	iycall	char_out
	jr	msg_inline_loop
msg_inline_done:
	ixret


; on entry:
;    A contains 8-bit value to output
;    IX contains return address
; on return:
;    A, B, C, IY destroyed
hex8_out:
	ld	b,a
	iycall	hexdig_msd_out
	ld	a,b
	iycall	hexdig_out
	ixret



; on entry:
;    HL contains 16-bit value to output
;    IX contains return address
; on return:
;    A, C, IY destroyed
hex16_out:
	ld	a,h
	iycall	hexdig_msd_out

	ld	a,h
	iycall	hexdig_out

	ld	a,l
	iycall	hexdig_msd_out

	ld	a,l
	iycall	hexdig_out

	ixret


; on entry:
;    A contains 8-bit value to output
;    I contains running checksum
;    IX contains return address
; on return:
;    I contains updated checkusm
;    A, B  C, IY destroyed
ihex8_out:
	ld	c,a		; update checksum
	ld	a,i
	add	a,c
	ld	i,a
	ld	a,c

	ld	b,a
	rrca			; shift MSD to LSD
	rrca
	rrca
	rrca
	iycall	ihexdig_out
	ld	a,b
	iycall	ihexdig_out
	ixret


; on entry:
;    A contains hex digit to output, in least significant digit
;    I contains running checksum
;    IY contains return address
; on return:
;    I contains updated checkusm
;    A, C destroyed
ihexdig_out:
	and	0fh
	cp	0ah
	jr	c,ihdo_no_adj
	add	a,('A'-'0')-10
ihdo_no_adj:
	add	a,'0'
	jp	char_out


; on entry:
;    I contains running checksum
;    IX contains return address
; on return:
;    A contains input value
;    I contains updated checksum
;    A, B, C, E destroyed
ihex8_in:
	ld	b,2		; digit count
	
ihex8_in_loop1:
	iycall	char_in
	iycall	downcase
	cp	c_etx
	jp	z,mloop_crlf
	ld	c,a		; save the char
	iycall	hex_asc_to_bin	; convert ASCII hex digit to binary
	jp	c,ihex_bad_char
	
	rla			; move hex digit to MSD
	rla
	rla
	rla

	ld	c,b		; temp save outer loop counter in C

	ld	b,4		; interate over four bits
ihex8_in_loop2:
	rla			; rotate one bit from MSB of A into LSB of HL
	rl	e

	djnz	ihex8_in_loop2	; iterate bit

	ld	b,c		; restore outer loop counter from C
	djnz	ihex8_in_loop1	; iterate digit
	
	ld	a,i
	add	a,e
	ld	i,a

	ld	a,e
	ixret



; on entry:
;    IX contains return address
; on return:
;    L contains input value
;    A, B, C destroyed
; note:
;    if CR is entered in place of first digit, will abort command
;    (like control-C in any position)
hex8_in_opt:
	ld	b,2
	xor	a
	ld	l,a

hi8o_loop1:
	iycall	char_in
	cp	c_cr		; carriage return?
	jp	z,mloop_crlf	;   yes, end command
	jr	hi8o_loop1b

hi8o_loop1a:
	iycall	char_in

hi8o_loop1b:
	cp	c_etx		; control-C?
	jp	z,mloop_crlf	;   yes, abort command
	
	iycall	downcase
	ld	c,a		; save the char
	iycall	hex_asc_to_bin	; convert ASCII hex digit to binary
	jr	c,hi8o_loop1
	ld	a,c		; get original char back
	iycall	char_out	; echo it to terminal
	iycall	hex_asc_to_bin	; convert ASCII hex digit to binary (again)

	rla			; move hex digit to MSD
	rla
	rla
	rla

	ld	c,b		; tmep save outer loop counter in C

	ld	b,4		; iterate over four bits
hi8o_loop2:
	rla			; rotate one bit from MSB of A into LSB of L
	rl	l
	djnz	hi8o_loop2	; iterate bit
	ld	b,c		; restore outer loop counter from C
	djnz	hi8o_loop1a	; iterate digit

	ixret



; on entry:
;    IX contains return address
; on return:
;    HL contains input value
;    A, B, C destroyed
hex16_in:
	ld	b,4		; digit count
	jr	hex_in

hex8_in:
	ld	b,2
; fall into hex_in

hex_in:
	xor	a
	ld	h,a
	ld	l,a

hex_in_loop1
	iycall	char_in
	iycall	downcase
	cp	c_etx
	jp	z,mloop_crlf
	ld	c,a		; save the char
	iycall	hex_asc_to_bin	; convert ASCII hex digit to binary
	jr	c,hex_in_loop1	; if not a digit, try again

	ld	a,c		; get original char back
	iycall	char_out	; echo it to terminal
	iycall	hex_asc_to_bin	; convert ASCII hex digit to binary (again)

	rla			; move hex digit to MSD
	rla
	rla
	rla

	ld	c,b		; temp save outer loop counter in C

	ld	b,4		; interate over four bits
hex_in_loop2:
	rla			; rotate one bit from MSB of A into LSB of HL
	rl	l
	rl	h

	djnz	hex_in_loop2	; iterate bit

	ld	b,c		; restore outer loop counter from C
	djnz	hex_in_loop1	; iterate digit

	ixret


; on entry:
;    A contains ASCII character
;    IY contains return address
; on return, if not hex digit:
;    carry flag set
;    A unchanged
; on return, if hex digit:
;    carry flag clear
;    A contains binary value
hex_asc_to_bin:
	sub	a,'0'			; adjust '0' to 000h
	cp	10
	jr	c,hatb_success

	sub	a,'a'-'0'		; adjust 'a' to 000h
	cp	'f'+1-'a'
	jr	nc,hatb_fail
	add	a,0ah
hatb_success:
	or	a			; clear carry (found hex digit)
	iyret
	
hatb_fail:
	add	a,'a'			; restore A to original value
	scf				; indicate not a hex digit
hatb_done:
	iyret



; on entry:
;    A contains hex digit to output, in most significant digit
;    IY contains return address
; on return:
;    A, C destroyed
hexdig_msd_out:
	rrca
	rrca
	rrca
	rrca
; fall into hexdig_out


; on entry:
;    A contains hex digit to output, in least significant digit
;    IY contains return address
; on return:
;    A, C destroyed
hexdig_out:
	and	0fh
	cp	0ah
	jr	c,no_adj
	add	a,('a'-'0')-10
no_adj:
	add	a,'0'
	jp	char_out
	

; on entry:
;    IX contains return address
; on return:
;    A destroyed
bank_setup:
; set up low 16K as flash
	ld	a,00h		; 0000..3fff to flash page 0 (0000..3fff)
	out	(p_bank0),a

; set up high 48K as RAM
	ld	a,20h		; 4000..7fff to RAM page 0 (0000..3fff)
	out	(p_bank1),a
	ld	a,21h		; 8000..bfff to RAM page 1 (4000..7fff)
	out	(p_bank2),a
	ld	a,22h		; c000..ffff to RAM page 1 (8000..bfff)
	out	(p_bank3),a
	
; enable bank switching
	ld	a,01h
	out	(p_bnken),a

	ixret


; on entry:
;    A contains character to downcase
;    IY contains return address
; on return:
;    A downcased
downcase:
	sub	a,'A'
	cp	26
	jr	nc,downcase1
	add	a,32
downcase1:
	add	a,'A'
	iyret
