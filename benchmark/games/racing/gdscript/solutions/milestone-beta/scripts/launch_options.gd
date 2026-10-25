class_name LaunchOptions
extends RefCounted
## The game's own flags, after "--" on the command line: --autoplay, --seed=N, --no-save, --track=N, --rivals=N.

var autoplay := false
var run_seed := 0
var no_save := false
var track := 1
## How many rivals race; more than the three in the data repeats them (for stress runs).
var rivals := 3


static func parse(args: PackedStringArray) -> LaunchOptions:
	var options := LaunchOptions.new()
	for arg in args:
		if arg == "--autoplay":
			options.autoplay = true
		elif arg == "--no-save":
			options.no_save = true
		elif arg.begins_with("--seed="):
			options.run_seed = int(arg.get_slice("=", 1))
		elif arg.begins_with("--track="):
			options.track = maxi(1, int(arg.get_slice("=", 1)))
		elif arg.begins_with("--rivals="):
			options.rivals = clampi(int(arg.get_slice("=", 1)), 0, 31)
	return options


static func from_command_line() -> LaunchOptions:
	return parse(OS.get_cmdline_user_args())
