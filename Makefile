# Copyright 2022 Eric Smith <spacewar@gmail.com>
# SPDX-License-Identifier: GPL-3.0-only


all:    umonz-sio.lst umonz-sio.hex umonz-sio.bin \
        umonz-acia.lst umonz-acia.hex umonz-acia.bin \
        dltest.hex


%.lst %.p: %.asm
	rm -f $*.lst
	asl -cpu z80 -L -C $<

%.hex: %.p
	p2hex -r "\$$-0x" -F Intel $*

%.bin: %.p
	p2bin -r "\$$-0x" $*


%.rom: %.bin
	cp $< $@
	truncate -s 512K $@


umon-sio.lst umon-sio.p: umon-sio.asm umon.asm sio.asm

umon-acia.lst umon-acia.p: umon-acia.asm umon.asm acia.asm


clean:
	rm -f *.p *.hex *.bin *.lst *.rom


# The rc2014 simulator by EtchedPixels is useful for testing.
#    https://github.com/EtchedPixels/RC2014/
# Only the "rc2014" executable is needed. Put it in a directory in
# your path, or redefine SIM.

SIM=rc2014

sim:	umonz-sio.rom
	$(SIM) -s -r $<

sim-acia:	umonz-acia.rom
	$(SIM) -r $<


