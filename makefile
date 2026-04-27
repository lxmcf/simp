CC := odin
BUILD ?= DEBUG

C_FLAGS := -vet -min-link-libs -strict-style -disallow-do
OPT := none

ifeq ($(BUILD),DEBUG)
	C_FLAGS += -debug -microarch:native
else ifeq ($(BUILD), RELEASE)
	OPT = speed
endif

MOLD_EXISTS := $(shell command -v mold 2> /dev/null)

ifneq ($(MOLD_EXISTS),)
    C_FLAGS += -linker:mold
endif

.PHONY: build run clean

build:
	mkdir -p build
	$(CC) build cli/ -out:build/simp $(C_FLAGS) -o:$(OPT)

lib:
	mkdir -p build
	$(CC) build src/ -build-mode:static -out:build/libsimp.a $(C_FLAGS) -o:$(OPT)

run: build
	build/simp

clean:
	rm -rf build/
