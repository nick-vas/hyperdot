class_name LaunchOptions
extends RefCounted
## The game's own flags, after "--" on the command line: --no-save.

var no_save := false


static func parse(args: PackedStringArray) -> LaunchOptions:
	var options := LaunchOptions.new()
	for arg in args:
		if arg == "--no-save":
			options.no_save = true
	return options


static func from_command_line() -> LaunchOptions:
	return parse(OS.get_cmdline_user_args())
