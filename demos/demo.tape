Output demos/output/demo.mp4
Require nvim
Set Shell "bash"
Set FontFamily "JetBrainsMono Nerd Font Mono"
Set FontSize 36
Set Width 1920
Set Height 1080
Set Framerate 30
Set TypingSpeed 120ms
Set Margin 56
Set MarginFill "demos/common/backdrop.png"
Set WindowBar Colorful
Set WindowBarSize 40
Set BorderRadius 24
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
Type "quan"
Sleep 800ms
Type "pin"
Sleep 800ms
Type "a"
Sleep 1.8s

Type "s"
Sleep 300ms
Type "j"
Sleep 800ms
Type "p"
Sleep 800ms
Type "a"
Sleep 1.8s

Type "s"
Sleep 300ms
Type "hun"
Sleep 800ms
Type "s"
Sleep 800ms
Type "ascii"
Sleep 800ms
Type "grin"
Sleep 800ms
Type "a"
Sleep 1.8s

Hide
Type@1ms ":lua FlashAnyDemo.verify()"
Enter
Sleep 200ms
Type@1ms ":qa!"
Enter
Sleep 300ms
