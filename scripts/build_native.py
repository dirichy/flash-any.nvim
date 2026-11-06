"""Build the native module using the repository's existing Unicode property data."""
import os
import json
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent


def unicode_header(path):
    text = (ROOT / 'lua/flash-any/grapheme_data.lua').read_text()
    pages = {int(p, 16): [int(n.strip(), 0) for n in values.split(',') if n.strip()]
             for p, values in re.findall(r'\[(0x[\da-fA-F]+)\]\s*=\s*\{([^}]+)\}', text)}
    starts, ranges = [], []
    for page in range(0x1100):
        starts.append(len(ranges))
        values = pages.get(page, [])
        assert len(values) % 3 == 0
        ranges.extend(zip(values[::3], values[1::3], values[2::3]))
    starts.append(len(ranges))
    assert len(ranges) < 65536
    header = '/* Unicode 17: derived from grapheme_data.lua; licenses/Unicode-3.0.txt. */\n#include <stdint.h>\n'
    header += 'static const uint16_t page_offsets[] = {' + ','.join(map(str, starts)) + '};\n'
    header += 'static const uint8_t ranges[][3] = {' + ','.join('{' + ','.join(map(str, r)) + '}' for r in ranges) + '};\n'
    Path(path).write_text(header)


def compile_module(source, output, sanitize=False):
    cflags = subprocess.check_output(['pkg-config', '--cflags', 'luajit'], text=True).split()
    libs = subprocess.check_output(['pkg-config', '--libs', 'luajit'], text=True).split()
    build = ROOT / 'build'
    build.mkdir(exist_ok=True)
    unicode_header(build / 'grapheme_data.h')
    flags = ['-O1', '-g', '-fsanitize=undefined', '-fno-sanitize-recover=undefined'] if sanitize else ['-O3']
    # Replacing a loaded shared library in place can invalidate a running editor's
    # mappings. Link a temporary output, then atomically publish the new inode.
    with tempfile.TemporaryDirectory(prefix='native-', dir=build) as temporary:
        module = Path(temporary) / 'native.so'
        cmd = shlex.split(os.environ.get('CC', 'cc')) + flags
        cmd += ['-std=c99', '-fPIC', '-shared', '-Wall', '-Wextra', '-Werror', *cflags,
                '-I', str(build), str(source), '-o', str(module), *libs, '-lm']
        (ROOT / 'compile_commands.json').write_text(json.dumps([
            dict(directory=str(ROOT), file=str(source), arguments=cmd)
        ], indent=2) + '\n')
        subprocess.run(cmd, check=True)
        os.replace(module, output)



if __name__ == '__main__':
    output = ROOT / 'lua/flash-any/native.so'
    compile_module(ROOT / 'src/native.c', output, '--sanitize' in sys.argv[1:])
    print(output)
