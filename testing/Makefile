ROOT := $(abspath ..)
APP := $(ROOT)/app
BUILD := $(CURDIR)/build

Z80ASM ?= z88dk-z80asm

CORE_LIB := $(APP)/core.lib
ENGINE_LIB := $(APP)/engine.lib
TEST_BINARY := $(BUILD)/routines.bin
TEST_CODE := $(BUILD)/routines_code.bin
TEST_CORE := $(BUILD)/routines_code_core.bin
TEST_ENGINE := $(BUILD)/routines_code_engine.bin
TEST_MAP := $(BUILD)/routines.map

CORE_ASM := $(APP)/core/interrupt.asm \
	$(APP)/core/flash_lockunlock.asm \
	$(APP)/core/ram_manager.asm \
	$(APP)/core/audio.inc
ENGINE_ASM := $(wildcard $(APP)/engine/*.asm) \
	$(wildcard $(APP)/engine/installed/*.asm) \
	$(APP)/struct_offsets.inc
TEST_ASM := routines.asm heap_routines.asm scl_routines.asm utils_routines.asm test_stubs.asm \
	$(APP)/core/includes/fixed_heap.inc \
	$(APP)/core/includes/utils.inc \
	$(APP)/engine/scl.inc

.PHONY: all test-binary clean

all: test-binary

test-binary: $(TEST_CODE) $(TEST_CORE) $(TEST_ENGINE) $(TEST_MAP)

$(CORE_LIB): $(APP)/Makefile $(CORE_ASM)
	$(MAKE) -C $(APP) core.lib

$(ENGINE_LIB): $(APP)/Makefile $(ENGINE_ASM)
	$(MAKE) -C $(APP) engine.lib

$(TEST_CODE) $(TEST_CORE) $(TEST_ENGINE) $(TEST_BINARY) $(TEST_MAP): $(TEST_ASM) $(CORE_LIB) $(ENGINE_LIB)
	mkdir -p $(BUILD)
	$(Z80ASM) -I$(APP) -L$(APP) -b -split-bin -m -r0x4000 -o$(TEST_BINARY) -lcore -lengine routines.asm heap_routines.asm scl_routines.asm utils_routines.asm test_stubs.asm

clean:
	rm -rf $(BUILD)
