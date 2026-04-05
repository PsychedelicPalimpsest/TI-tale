all: out.8xk


CFLAGS = "-pragma-define:CRT_ENABLE_STDIO=0" -m --list
SFLAGS = -l

CORE_LIB_FILES = core/interrupt.asm
core.lib: $(CORE_LIB_FILES)
	z88dk-z80asm $(SFLAGS) -xcore.lib $(CORE_LIB_FILES)

ENGINE_LIB_FILES = $(wildcard engine/*.asm)
engine.lib: $(ENGINE_LIB_FILES)
	z88dk-z80asm $(SFLAGS) -xengine.lib $(ENGINE_LIB_FILES)

out.8xk: first_page.c Makefile engine.lib core.lib core/custom_ti83papp_crt0.asm
	zcc +ti83p -lcore -lengine -o out first_page.c -crt0=core/custom_ti83papp_crt0.asm $(CFLAGS)
	z88dk-appmake +ti83papp --single-page --binfile out --crt0file core/custom_ti83papp_crt0.asm --output out.8xk
clean:
	rm -f out.8xk *.bin out *.lib **.o **.lis
