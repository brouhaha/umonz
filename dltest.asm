; dltest.asm
; small test executable for download to umonz
; Copyright 2022 Eric Smith <spacewar@gmail.com>
; SPDX-License-IdentifierGPL-3.0-only

	cpu	z80

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

	
; other I/O ports

p_sio_c		equ	080h		; control, r/w
p_sio_d		equ	p_sio_c+1	; data, r/w


; character definitions
c_etx		equ	003h		; control-C
c_cr		equ	00dh
c_lf		equ	00ah


	org	8000h

	ixcall	uart_setup

	ld	hl,m_banner
	ixcall	msg_out

	jp	0000h
m_banner:
	db	"foo",c_cr,c_lf,000h
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
;    A contains character to output
;    IY contains return address
; on return:
;    A unchanged
;    C destroyed
char_out:
	ld	c,a
char_out_loop:
	in	a,(p_sio_c)	; read RR0, loop if not transmit buffer empty
	bit	2,a
	jr	z,char_out_loop 
	ld	a,c
	out	(p_sio_d),a	; output the character
	iyret
; on entry:
;    IX contains return address
; on return:
;    A destroyed
uart_setup:
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


	end
