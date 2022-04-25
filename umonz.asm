; umonz.asm
; RAMless Z80 monitor
; Copyright 2022 Eric Smith <spacewar@gmail.com>
; SPDX-License-Identifier: GPL-3.0-only

	cpu	z80

use_mmap	equ	0	; set for RC2014 512K Flash/RAM style mapper
use_sio		equ	1	; set to use Z80-SIO serial channel
use_acia	equ	0	; set to use MC6850 ACIA serial channel


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


; other I/O ports

		if	use_sio
p_sio_c		equ	080h		; control, r/w
p_sio_d		equ	p_sio_c+1	; data, r/w
		endif

		if	use_acia
p_acia_c	equ	080h		; control, write only
p_acia_s	equ	p_acia_c	; status, read only
p_acia_d	equ	p_acia_c+1	; data, r/w
		endif


; character definitions
c_etx		equ	003h		; control-C
c_cr		equ	00dh
c_lf		equ	00ah


ramloc		equ	8000h

	org	0000h

reset:	di
	ld	sp,0ffffh

	if	use_mmap
	ixcall	bank_setup
	endif

	ixcall	uart_setup

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
	jr	nz,skip_line	;   no, skip

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

ihex_bad_char:
	ixcall	msg_out_inline
	db	"bad char in hex file",000h
	jp	mloop_crlf

ihex_bad_checksum:
	ixcall	msg_out_inline
	db	"bad checksum in hex file",000h
	jp	mloop_crlf
	

skip_line:
	ld	a,'%'
	iycall	char_out
	
	iycall	char_in
	cp	c_etx
	jp	z,mloop_crlf
	cp	c_cr
	jp	z,mloop
	jr	skip_line


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
;    C points to SIO port control register
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
; fall into char_out
	

; on entry:
;    A contains character to output
;    IY contains return address
; on return:
;    A unchanged
;    C destroyed
char_out:
	if	use_sio
	ld	c,a
char_out_loop:
	in	a,(p_sio_c)	; read RR0, loop if not transmit buffer empty
	bit	2,a
	jr	z,char_out_loop 
	ld	a,c
	out	(p_sio_d),a	; output the character
	iyret
	endif

	if	use_acia
	ld	c,a
char_out_loop:
	in	a,(p_acia_s)
	bit	1,a
	jr	z,char_out_loop
	ld	a,c
	out	(p_acia_d),a	; output the character
	iyret
	endif



; on entry:
;    IY contains return address
; on return
;    Z flag clear if read character available
;    A destroyed
char_avail
	if	use_sio
	in	a,(p_sio_c)	; read RR0
	bit	0,a
	iyret
	endif

	if	use_acia	; read status
	in	a,(p_acia_s)
	bit	0,a
	iyret
	endif


; on entry:
;    IY contains return address
; on return
;    A contains recieved character
char_in
	if	use_sio
	in	a,(p_sio_c)	; read RR0, loop if not receive character available
	bit	0,a
	jr	z,char_in
	in	a,(p_sio_d)	; read the character
	iyret
	endif

	if	use_acia	; read status, loop if not receive data register full
	in	a,(p_acia_s)
	bit	0,a
	jr	z,char_in
	in	a,(p_acia_d)	; read the character
	iyret
	endif


; on entry:
;    IX contains return address
; on return:
;    A destroyed
uart_setup:

	if	use_sio
	
	in	a,(p_sio_c)	; dummy read; if pointer was non-zero, now it will be zero

	ld	a,018h		; write into WR0: channel reset
	out	(p_sio_c),a

	ld	a,030h		; write into WR0: error reset, select WR0
	out	(p_sio_c),a

	ld	a,003h		; write into WR0: select WR3
	out	(p_sio_c),a
	ld	a,0c1h		; write into WR3: RX 8 bits, RX enable
	out	(p_sio_c),a
	
	ld	a,004h		; write into WR0: select WR4
	out	(p_sio_c),a
	ld	a,0c4h		; write into WR4: clk64x, async, 1 stop bit, no parity
	out	(p_sio_c),a

	ld	a,005h		; write into WR0: select WR5
	out	(p_sio_c),a
	ld	a,0eah		; write into WR5: DTR active, TX 8 bits, break off, TX on, RTS active
	out	(p_sio_c),a

	ixret

	endif

	if	use_acia

	ld	a,015h		; div 16, 8N1, RTS active, interrupts disabled
	out	(p_acia_c),a
	ixret

	endif


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


	end
