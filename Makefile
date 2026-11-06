.PHONY: all clean
all: lua/flash-any/native.so build/grapheme_data.h compile_commands.json
lua/flash-any/native.so build/grapheme_data.h compile_commands.json &: src/native.c src/text.h lua/flash-any/grapheme_data.lua scripts/build_native.py
	python3 scripts/build_native.py
clean:
	$(RM) lua/flash-any/native.so build/grapheme_data.h compile_commands.json
