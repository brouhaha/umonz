; umonz.asm
; RAMless Z80 monitor
; Copyright 2022 Eric Smith <spacewar@gmail.com>
; SPDX-License-IdentifierGPL-3.0-only

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


ramloc		equ	8000h

	org	0000h

reset:	di
	ld	sp,0ffffh

	if	use_mmap
	ixcall	bank_setup
	endif

	ixcall	uart_setup

	ld	hl,m_banner
	ixcall	msg_out

mloop:
	ld	hl,m_prompt
	ixcall	msg_out

mloop2:
	iycall	char_in

	ixcall	dispatch

	db	'd'
	dw	cmd_dump

	db	'r'
	dw	cmd_read

	db	'w'
	dw	cmd_write

	db	'i'
	dw	cmd_input

	db	'o'
	dw	cmd_output

	db	'h'
	dw	cmd_halt

	db	00dh
	dw	cmd_null

	db	0		; end of table

	ld	hl,m_bad_cmd
	ixcall	msg_out
	jr	mloop


cmd_dump:
	ld	hl,m_cmd_dump
	ixcall	msg_out
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

cmd_null:
	ixcall	crlf_out
	jp	mloop

dump_next:
	iycall	char_avail	; is there a received character?
	jr	z,dump_next2
	iycall	char_in
	cp	a,003h		; is it control-C?
	jr	z,cmd_null	; yes, end command

dump_next2:
	inc	hl		; advance pointer
	ld	a,l		; 16-byte boundary?
	and	00fh
	jr	z,dump_addr	; yes, end line and print address
	jr	dump_byte	; no, proceed to next byte


cmd_read:
	ld	hl,m_cmd_read
	ixcall	msg_out
	ixcall	hex16_in
	ixcall	crlf_out
	ixcall	hex16_out
	ld	a,':'
	iycall	char_out
	ld	a,' '
	iycall	char_out
	ld	a,(hl)
	ixcall	hex8_out
	ixcall	crlf_out

	jp	mloop


cmd_write:
	ld	hl,m_cmd_write
	ixcall	msg_out
	ixcall	hex16_in
	ld	d,h
	ld	e,l
	ld	a,'='
	iycall	char_out
	ixcall	hex8_in
	ixcall	crlf_out
	ld	a,l
	ld	(de),a
	jp	mloop


cmd_input:
	ld	hl,m_cmd_input
	ixcall	msg_out
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
	ixcall	crlf_out

	jp	mloop


cmd_output:
	ld	hl,m_cmd_output
	ixcall	msg_out
	ixcall	hex8_in
	ld	e,l
	ld	a,'='
	iycall	char_out
	ixcall	hex8_in
	ixcall	crlf_out
	ld	c,e
	out	(c),l
	jp	mloop


cmd_halt:
	ld	hl,m_cmd_halt
	ixcall	msg_out
	halt


m_banner:
	db	"umonz 0.1",00dh,00ah,000h

m_prompt:
	db	">",000h

m_bad_cmd:
	db	00dh,00ah,"unrecognized command",00dh,00ah,000h

m_cmd_dump:
	db	"ump ",000h

m_cmd_read:
	db	"ead ",000h

m_cmd_write:
	db	"rite ",000h

m_cmd_input:
	db	"nput ",000h

m_cmd_output:
	db	"utput ",000h

m_cmd_halt:
	db	"alt",00dh,00ah,000h


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
	iycall	char_out
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
	ld	a,00dh
	iycall	char_out
	ld	a,00ah
	iycall	char_out
	ixret


; on entry:
;    HL points to message string (null terminated)
;    IX contains return address
; on return:
;    A, C, HL, IY destroyed
msg_out:

msg_loop:
	ld	a,(hl)
	inc	hl
	or	a
	jr	z,msg_done

	iycall	char_out
	jr	msg_loop
msg_done:
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
	ld	c,a		; save the char
	iycall	hex_asc_to_bin	; convert ASCII hex digit to binary
	jr	c,hex_in_loop1	; if not a digit, try again

	ld	a,c		; get original char back
	iycall	char_out
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


	end
