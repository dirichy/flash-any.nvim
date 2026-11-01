#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

mkdir -p demos/output
for tool in nvim vhs ttyd ffmpeg ffprobe python3 fc-match; do
  command -v "$tool" >/dev/null || { printf 'Install %s before recording.\n' "$tool" >&2; exit 1; }
done
font=$(fc-match -f '%{family}' 'JetBrainsMono Nerd Font Mono')
case "$font" in
  *'JetBrainsMono Nerd Font Mono'*) ;;
  *) printf '%s\n' 'Install JetBrainsMono Nerd Font Mono before recording.' >&2; exit 1 ;;
esac
# Keep the same defaults locally and in CI; custom installations can override paths.
export FLASH_NVIM_PATH="${FLASH_NVIM_PATH:-$PWD/.dev/flash.nvim}"
export TOKYONIGHT_PATH="${TOKYONIGHT_PATH:-$PWD/.dev/tokyonight.nvim}"
for plugin in "$FLASH_NVIM_PATH" "$TOKYONIGHT_PATH"; do
  test -d "$plugin" || { printf 'Missing plugin directory: %s\n' "$plugin" >&2; exit 1; }
done

# Empty old evidence so an interrupted recording cannot reuse a previous success.
: > demos/output/verification.json
vhs demos/demo.tape
python3 - <<'PYTHON'
import json
import subprocess
from pathlib import Path

output = Path('demos/output')
report = json.loads((output / 'verification.json').read_text())
assert report['verified'], report.get('error', 'demo verification failed')
print('Verified live candidates, labels, all three jumps, and unchanged fixture.')

# Two passes bound memory and keep the static gradient stable between frames.
video = str(output / 'demo.mp4')
palette = str(output / 'palette.png')
gif_filter = 'fps=20,scale=1920:-1:flags=lanczos'
subprocess.run([
    'ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-i', video,
    '-vf', gif_filter + ',palettegen=stats_mode=diff', '-frames:v', '1', palette,
], check=True)
subprocess.run([
    'ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-i', video, '-i', palette,
    '-filter_complex', gif_filter + '[video];[video][1:v]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle',
    '-loop', '0', str(output / 'demo.gif'),
], check=True)

media = {}
for extension, codec in [('mp4', 'h264'), ('gif', 'gif')]:
    info = json.loads(subprocess.check_output([
        'ffprobe', '-v', 'error', '-select_streams', 'v:0',
        '-show_entries', 'stream=codec_name,width,height,r_frame_rate,avg_frame_rate:format=duration,size',
        '-of', 'json', str(output / f'demo.{extension}'),
    ]))
    stream = info['streams'][0]
    assert stream['codec_name'] == codec, info
    assert (stream['width'], stream['height']) == (1920, 1080), info
    assert float(info['format']['duration']) > 0, info
    assert int(info['format']['size']) > 0, info
    media[extension] = info
(output / 'media.json').write_text(json.dumps(media, indent=2) + '\n')
print(json.dumps(media, indent=2))
subprocess.run([
    'ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-sseof', '-2', '-i', video,
    '-frames:v', '1', str(output / 'demo.png'),
], check=True)
PYTHON
