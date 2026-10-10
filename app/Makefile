.DEFAULT_GOAL := all

all: out.8xk out.prof


CFLAGS = "-pragma-define:CRT_ENABLE_STDIO=0" -m --list
SFLAGS = -l


CORE_LIB_FILES := core/interrupt.asm core/flash_lockunlock.asm core/ram_manager.asm
core.lib: $(CORE_LIB_FILES) core/audio.inc core/common.inc
	z88dk-z80asm $(SFLAGS) -x$@ $(CORE_LIB_FILES)

# Each source file is one z88dk library module. Keep code copied to RAM
# separate from the optional ROM routines linked into individual room pages.
RESIDENT_ENGINE_FILES := $(sort $(wildcard engine/resident/*.asm))
RESIDENT_ENGINE_INCLUDES := $(wildcard engine/resident/installed/*.asm) engine/engine_globals.inc engine/scl.inc struct_offsets.inc
PAGE_ENGINE_FILES := $(sort $(wildcard engine/page/*.asm))

engine_resident.lib: $(RESIDENT_ENGINE_FILES) $(RESIDENT_ENGINE_INCLUDES) core/common.inc
	z88dk-z80asm $(SFLAGS) -x$@ $(RESIDENT_ENGINE_FILES)

engine_page.lib: $(PAGE_ENGINE_FILES) core/common.inc
	z88dk-z80asm $(SFLAGS) -x$@ $(PAGE_ENGINE_FILES)


struct_offsets.inc: $(shell python struct_to_asm.py --list)
	python struct_to_asm.py --gen-inc > $@ || rm -f $@

out.prof: $(shell python profile_gen.py --list) out.map
	python profile_gen.py --gen-regions --map out.map > $@ || rm -f $@


out.8xk out.map &: first_page.c Makefile engine_resident.lib engine_page.lib core.lib core/custom_ti83papp_crt0.asm struct_offsets.inc
	zcc +ti83p -L. -lcore -lengine_resident -lengine_page -o out first_page.c -crt0=core/custom_ti83papp_crt0.asm $(CFLAGS)
	z88dk-appmake +ti83papp --single-page --binfile out --crt0file core/custom_ti83papp_crt0.asm --output out.8xk
	test -s out.map
clean:
	rm -f out.8xk *.bin out *.lib **/*.o **/**.lis *.lis *.map struct_offsets.inc out.prof regions.txt
