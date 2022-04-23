# umonz - RAMless monitor for Z80 microprocessor

Copyright 2022 Eric Smith <spacewar@gmail.com>

SPDX-License-Identifier: GPL-3.0-only

umonz development i shosted at the
[umonz Github repository](https://github.com/brouhaha/umonz/).

## Introduction

I've been helping a friend debug a homebrew Z80 system, and
RAM wasn't working. After developing a series of test programs, including
scope loops, that did not depend on RAM, it occurred to me to write a
simple Z80 monitor also not depending on RAM. I had previously done this
back in 1996 for 64-bit MIPS processors
([mmon](https://github.com/brouhaha/mmon/)),
but it is somewhat more difficult on the Z80. Nevertheless, I have a very
rudimentary monitor working.

The monitor cross-assembles using the
[Macro Assembler AS](http://john.ccac.rwth-aachen.de:8000/as/).
No attempt has been made to code it for native assembly on a Z80 system.

The monitor is accessed via a serial port. By default it expects to use one
channel of a Z80-SIO or equivalent, configured for 64x clock divider (as
common on RC2014 systems). It can be configured to use an MC6850 ACIA instead.

## Usage

The monitor will output a signon banner, then gives a `>` prompt.
All input letters, including commands and hexadecimal values, will be
converted to and printed in lower case.
Commands are a single character. Only the first letter of a command is
input, whereupon the full name of the command is printed.
If the command requires any arguments, it will wait for them to be entered.
Spaces, hypens, and equal signs shown in the commands listed below are
generated automatically.
All argument values are hexadecimal, and exactly two or four digits must
be entered, as appropriate.
There is no backspacing, as there is no buffer to store the command string
for editing. A command being entered may be cancelled using control-C.

An Intel hex file can be downloaded. The leading colon on an input line
triggers this automatically. Only the "00" data record type is
accepted, and only 16-bit addressing is used.

The commands are:

| command             | description |
| ------------------- | ----------- |
| `dump bbbb-eeee`    | dump memmory from adress bbbb to eeee - can halt with control-C |
| `read aaaa`         | read one byte of memory from address aaaa |
| `write aaaa=dd...`  | write one or more cosecutive bytes of memory at address aaaa with the value(s) dd, carriage return when done |
| `input pp`          | input one byte from port address pp |
| `output pp=dd...`   | output one or more bytes to port address pp with the value(s) dd, carriage return when done |
| `go aaaa`           | execute starting at address aaaa |
| `halt`              | halt |
