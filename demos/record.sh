#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

scene=${1:-demo}
case "$scene" in
  demo) verification=verification.json ;;
  char) verification=char-verification.json ;;
  table) verification=table-verification.json ;;
  *) printf 'Usage: %s [demo|char|table [config.lua]]\n' "$0" >&2; exit 1 ;;
esac

mkdir -p demos/output
for tool in nvim make vhs ttyd ffmpeg ffprobe python3 fc-match fc-query; do
  command -v "$tool" >/dev/null || { printf 'Install %s before recording.\n' "$tool" >&2; exit 1; }
done
font_family=$(python3 -c 'from pathlib import Path; print(next(line.split(chr(34))[1] for line in Path("demos/common/style.tape").read_text().splitlines() if line.startswith("Set FontFamily ")))')
font=$(fc-match -f '%{family}' "$font_family")
case "$font" in
  *"$font_family"*) ;;
  *) printf 'Install %s before recording.\n' "$font_family" >&2; exit 1 ;;
esac
# Keep the same defaults locally and in CI; custom installations can override paths.
export FLASH_NVIM_PATH="${FLASH_NVIM_PATH:-$PWD/.dev/flash.nvim}"
export TOKYONIGHT_PATH="${TOKYONIGHT_PATH:-$PWD/.dev/tokyonight.nvim}"
for plugin in "$FLASH_NVIM_PATH" "$TOKYONIGHT_PATH"; do
  test -d "$plugin" || { printf 'Missing plugin directory: %s\n' "$plugin" >&2; exit 1; }
done

# Empty old evidence so an interrupted recording cannot reuse a previous success.
: > "demos/output/$verification"
make
if test "$scene" = table; then
  if test "$#" -ge 2; then
    nvim --clean -l demos/prepare-table.lua "$2"
  else
    nvim --clean -l demos/prepare-table.lua
  fi
  vhs demos/output/table.tape
else
  vhs "demos/$scene.tape"
fi
python3 - "$scene" "$verification" <<'PYTHON'
import json
import subprocess
import sys
from pathlib import Path

output = Path('demos/output')
scene, verification = sys.argv[1:]
report = json.loads((output / verification).read_text())
assert report['verified'], report.get('error', 'demo verification failed')
print(f'Verified {scene} live playback and unchanged fixture.')

# Two passes bound memory and keep the static gradient stable between frames.
video = str(output / f'{scene}.mp4')
palette = str(output / f'{scene}-palette.png')
gif_filter = 'fps=20,scale=1920:-1:flags=lanczos'
subprocess.run([
    'ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-i', video,
    '-vf', gif_filter + ',palettegen=stats_mode=diff', '-frames:v', '1', palette,
], check=True)
subprocess.run([
    'ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-i', video, '-i', palette,
    '-filter_complex', gif_filter + '[video];[video][1:v]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle',
    '-loop', '0', str(output / f'{scene}.gif'),
], check=True)

media = {}
for extension, codec in [('mp4', 'h264'), ('gif', 'gif')]:
    info = json.loads(subprocess.check_output([
        'ffprobe', '-v', 'error', '-select_streams', 'v:0',
        '-show_entries', 'stream=codec_name,width,height,r_frame_rate,avg_frame_rate:format=duration,size',
        '-of', 'json', str(output / f'{scene}.{extension}'),
    ]))
    stream = info['streams'][0]
    assert stream['codec_name'] == codec, info
    assert (stream['width'], stream['height']) == (1920, 1080), info
    assert float(info['format']['duration']) > 0, info
    assert int(info['format']['size']) > 0, info
    media[extension] = info
(output / ('media.json' if scene == 'demo' else f'{scene}-media.json')).write_text(json.dumps(media, indent=2) + '\n')
print(json.dumps(media, indent=2))
subprocess.run([
    'ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-sseof', '-2', '-i', video,
    '-frames:v', '1', str(output / f'{scene}.png'),
], check=True)
# Keep local preview links usable without release assets.
previews = ['# Local demos', '']
for name, title in [('demo', 'Pinyin and mixed input'), ('char', 'First-code f jumps'), ('table', 'Third-party code table')]:
    if (output / f'{name}.gif').exists():
        previews.extend([f'## {title}', '', f'![{title}]({name}.gif)', '', f'[MP4]({name}.mp4)', ''])
(output / 'README.local.md').write_text('\n'.join(previews))
PYTHON
