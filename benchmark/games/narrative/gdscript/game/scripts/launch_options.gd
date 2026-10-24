class_name LaunchOptions
extends RefCounted
## The game's own flags, after "--" on the command line: --autoplay, --no-save.

## The bot plays the story through to every ending, one after another, then quits.
var autoplay := false
var no_save := false


static func parse(args: PackedStringArray) -> LaunchOptions:
	var options := LaunchOptions.new()
	for arg in args:
		if arg == "--autoplay":
			options.autoplay = true
		elif arg == "--no-save":
			options.no_save = true
	return options


static func from_command_line() -> LaunchOptions:
	return parse(OS.get_cmdline_user_args())
