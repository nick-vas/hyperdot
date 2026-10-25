class_name LaunchOptions
extends RefCounted
## The game's own flags, after "--" on the command line: --autoplay, --seed=N, --no-save, --lag=MS, --server, --port=N,
## and the soak contract's --soak-role=server|client, --soak-port=N and --soak-id=N.

const DEFAULT_PORT := 24650

var autoplay := false
## 0: no seed given, so the bots and the jitter are seeded at random.
var run_seed := 0
var no_save := false
## A simulated round trip for local play, in milliseconds (half each way).
var lag_ms := 0
## A dedicated server, headless, with no local player.
var server := false
var port := DEFAULT_PORT
var soak_role := ""
var soak_id := 0


static func parse(args: PackedStringArray) -> LaunchOptions:
	var options := LaunchOptions.new()
	for arg in args:
		var value := arg.get_slice("=", 1)
		match arg.get_slice("=", 0):
			"--autoplay":
				options.autoplay = true
			"--no-save":
				options.no_save = true
			"--server":
				options.server = true
			"--seed":
				options.run_seed = int(value)
			"--lag":
				options.lag_ms = clampi(int(value), 0, 1000)
			"--port", "--soak-port":
				options.port = int(value)
			"--soak-role":
				options.soak_role = value
			"--soak-id":
				options.soak_id = int(value)
	if options.soak_role == "server":
		options.server = true
	return options


static func from_command_line() -> LaunchOptions:
	return parse(OS.get_cmdline_user_args())


## The seed of the n-th match of a run with --seed, so a run replays; 0 without it (the game picks one at random).
func match_seed(n: int) -> int:
	return run_seed * 1009 + n if run_seed > 0 else 0
