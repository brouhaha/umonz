# Copyright 2022 Eric Smith <spacewar@gmail.com>
# SPDX-License-Identifier: GPL-3.0-only


all: umonz.lst umonz.hex umonz.bin dltest.hex


%.lst %.p: %.asm
	rm -f $*.lst
	asl -cpu z80 -L -C $<

%.hex: %.p
	p2hex -r "\$$-0x" -F Intel $*

%.bin: %.p
	p2bin -r "\$$-0x" $*


SIM = /home/eric/src/rc2014-emu/RC2014/rc2014

# requires umonz.asm to be configured for SIO
sim:	umonz.bin
	cp umonz.bin rc2014.rom
	truncate -s 512K rc2014.rom
	$(SIM) -s


# requires umon1.asm to be configured for ACIA
sim-acia:	umonz.bin
	cp umonz.bin rc2014.rom
	truncate -s 512K rc2014.rom
	$(SIM)


clean:
	rm -f *.p *.hex *.bin *.lst *.rom
