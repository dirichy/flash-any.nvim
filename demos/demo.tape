# Run from the repository root: vhs demos/demo.tape
Output demos/output/demo.mp4
Output demos/output/demo.gif

Set Shell "bash"
Set FontFamily "JetBrainsMono Nerd Font Mono"
Set FontSize 24
Set Width 1280
Set Height 800
Set Framerate 25
Set TypingSpeed 160ms
Set Padding 16
Set Theme "TokyoNight"
Set CursorBlink false

Hide
Type@1ms "env XDG_CONFIG_HOME=$PWD/demos/output/config XDG_STATE_HOME=$PWD/demos/output/state XDG_CACHE_HOME=$PWD/demos/output/cache NVIM_LOG_FILE=$PWD/demos/output/nvim.log nvim -n -i NONE -u demos/init.lua demos/sample.lua"
Enter
Sleep 2s
Show
Sleep 1s

Type "s"
Sleep 300ms
Type "vs"
Sleep 1s
Type "go"
Sleep 1s
Type "a"
Sleep 1.5s

Type "s"
Sleep 300ms
Type "alpha"
Sleep 1.2s
Type "a"
Sleep 1.5s

Type "s"
Sleep 300ms
Type "grin"
Sleep 1.2s
Type "a"
Sleep 2s

Hide
Type@1ms ":lua FlashAnyDemo.verify()"
Enter
Sleep 200ms
Type@1ms ":qa!"
Enter
Sleep 300ms
