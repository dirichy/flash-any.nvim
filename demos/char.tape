Output demos/output/char.mp4
Require nvim
Source demos/common/style.tape

Hide
Type@1ms "env XDG_CONFIG_HOME=$PWD/demos/output/config XDG_STATE_HOME=$PWD/demos/output/state XDG_CACHE_HOME=$PWD/demos/output/cache NVIM_LOG_FILE=$PWD/demos/output/char-nvim.log nvim -n -i NONE -u demos/char-init.lua demos/char-sample.txt"
Enter
Sleep 2s
Show
Sleep 1.5s

Type "f"
Sleep 600ms
Type "z"
Sleep 2s
Type "f"
Sleep 1.5s
Type ";"
Sleep 1.5s
Type ";"
Sleep 1.5s
Type ","
Sleep 2s

Hide
Type@1ms ":lua FlashAnyCharDemo.verify()"
Enter
Sleep 200ms
Type@1ms ":qa!"
Enter
Sleep 300ms
