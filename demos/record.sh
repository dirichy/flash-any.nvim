#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

mkdir -p demos/output
# Clear the previous verification before starting a new recording.
: > demos/output/verification.json
font=$(fc-match -f '%{family}' 'JetBrainsMono Nerd Font Mono')
case "$font" in
  *'JetBrainsMono Nerd Font Mono'*) ;;
  *) printf '%s\n' 'Install JetBrainsMono Nerd Font Mono before recording.' >&2; exit 1 ;;
esac
vhs demos/demo.tape
python3 - <<'PY'
import json
import subprocess
from pathlib import Path

report = json.loads(Path("demos/output/verification.json").read_text())
assert report["verified"], report.get("error", "demo verification failed")
print("Verified live candidates, labels, three jump positions, and unchanged fixture.")

media = {}
for extension, codec in [("mp4", "h264"), ("gif", "gif")]:
    info = json.loads(subprocess.check_output([
        "ffprobe", "-v", "error", "-select_streams", "v:0",
        "-show_entries", "stream=codec_name,width,height,r_frame_rate:format=duration,size",
        "-of", "json", f"demos/output/demo.{extension}",
    ]))
    assert info["streams"][0]["codec_name"] == codec, info
    assert float(info["format"]["duration"]) > 0, info
    assert int(info["format"]["size"]) > 0, info
    media[extension] = info
Path("demos/output/media.json").write_text(json.dumps(media, indent=2) + "\n")
print(json.dumps(media, indent=2))
PY

ffmpeg -hide_banner -loglevel error -y -ss 3.6 -i demos/output/demo.mp4 -frames:v 1 demos/output/poster.png
