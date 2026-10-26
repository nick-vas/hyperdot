class_name LaunchOptions
extends RefCounted
## The game's own flags, after "--" on the command line: --seed=N, --no-save, --map=N, --speed=N.

## 0: no seed given, so each battle draws its own.
var run_seed := 0
var no_save := false
var map := 1
## Battle ticks per physics tick: 1 is normal speed.
var speed := 1


static func parse(args: PackedStringArray) -> LaunchOptions:
	var options := LaunchOptions.new()
	for arg in args:
		if arg == "--no-save":
			options.no_save = true
		elif arg.begins_with("--seed="):
			options.run_seed = int(arg.get_slice("=", 1))
		elif arg.begins_with("--map="):
			options.map = maxi(1, int(arg.get_slice("=", 1)))
		elif arg.begins_with("--speed="):
			options.speed = clampi(int(arg.get_slice("=", 1)), 1, 8)
	return options


static func from_command_line() -> LaunchOptions:
	return parse(OS.get_cmdline_user_args())
