# GNU make 3.81 compatible; no Neovim or data generator is needed to compile.
CC ?= cc
CFLAGS ?= -O3
CPPFLAGS ?=
LDFLAGS ?=

SYSTEM := $(shell uname -s)
ifeq ($(SYSTEM),Darwin)
SHARED_FLAGS = -bundle -undefined dynamic_lookup
else
SHARED_FLAGS = -shared
endif

NATIVE = lua/flash-any/native.so
HEADERS = src/groups.h src/text.h src/grapheme_data.h vendor/luajit/lua.h vendor/luajit/lauxlib.h vendor/luajit/luaconf.h

.PHONY: all clean
all: $(NATIVE)

$(NATIVE): src/native.c $(HEADERS) Makefile
	@set -e; temporary="$@.$$$$.tmp"; trap 'rm -f "$$temporary"' 0; \
	$(CC) $(CPPFLAGS) $(CFLAGS) -std=c99 -fPIC -Wall -Wextra -Werror \
		-Ivendor/luajit src/native.c $(SHARED_FLAGS) $(LDFLAGS) -o "$$temporary"; \
	mv -f "$$temporary" "$@"

clean:
	$(RM) $(NATIVE)
