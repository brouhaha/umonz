; umonz-acia.asm
; RAMless Z80 monitor for MC68B50 ACIA console port
; Copyright 2022 Eric Smith <spacewar@gmail.com>
; SPDX-License-Identifier: GPL-3.0-only


p_acia_c	equ	080h		; control, write only
p_acia_s	equ	p_acia_c	; status, read only
p_acia_d	equ	p_acia_c+1	; data, r/w


	include "umonz.asm"


; on entry:
;    IX contains return address
; on return:
;    A destroyed
console_setup:
	ld	a,015h		; div 16, 8N1, RTS active, interrupts disabled
	out	(p_acia_c),a
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
	in	a,(p_acia_s)	; read status, loop if not transmit buffer empty
	bit	1,a
	jr	z,char_out_loop
	ld	a,c
	out	(p_acia_d),a	; output the character
	iyret


; on entry:
;    IY contains return address
; on return
;    Z flag clear if read character available
;    A destroyed
char_avail
	in	a,(p_acia_s)	; read status
	bit	0,a
	iyret


; on entry:
;    IY contains return address
; on return
;    A contains recieved character
char_in
	in	a,(p_acia_s)	; read status
	bit	0,a		; receive character available?
	jr	z,char_in	;   no, loop
	in	a,(p_acia_d)	; read the character
	iyret


	end
