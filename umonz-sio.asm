; umonz-sio.asm
; RAMless Z80 monitor for Z80 SIO based console
; Copyright 2022 Eric Smith <spacewar@gmail.com>
; SPDX-License-Identifier: GPL-3.0-only


p_sio_c	equ	080h		; control, r/w
p_sio_d	equ	p_sio_c+1	; data, r/w


	include	"umonz.asm"


; on entry:
;    IX contains return address
; on return:
;    A destroyed
console_setup:
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
;    IY contains return address
; on return
;    Z flag clear if read character available
;    A destroyed
char_avail
	in	a,(p_sio_c)	; read RR0
	bit	0,a
	iyret


; on entry:
;    IY contains return address
; on return
;    A contains recieved character
char_in
	in	a,(p_sio_c)	; read RR0
	bit	0,a		; receive character available?
	jr	z,char_in	;   no, loop
	in	a,(p_sio_d)	; read the character
	iyret


	end
