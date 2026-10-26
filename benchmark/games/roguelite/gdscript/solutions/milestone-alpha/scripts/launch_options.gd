class_name LaunchOptions
extends RefCounted
## The game's own flags, after "--" on the command line: --seed=N, --no-save, --floor=N, --swarm=N.

## 0: no seed given, so each run is seeded at random.
var run_seed := 0
var no_save := false
## The floor a run starts on.
var floor_number := 1
## Extra bats hunting the wick on every floor: the load for bench.
var swarm := 0


static func parse(args: PackedStringArray) -> LaunchOptions:
	var options := LaunchOptions.new()
	for arg in args:
		if arg == "--no-save":
			options.no_save = true
		elif arg.begins_with("--seed="):
			options.run_seed = int(arg.get_slice("=", 1))
		elif arg.begins_with("--floor="):
			options.floor_number = maxi(1, int(arg.get_slice("=", 1)))
		elif arg.begins_with("--swarm="):
			options.swarm = maxi(0, int(arg.get_slice("=", 1)))
	return options


static func from_command_line() -> LaunchOptions:
	return parse(OS.get_cmdline_user_args())
