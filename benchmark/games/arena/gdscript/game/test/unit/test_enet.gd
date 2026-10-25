extends GutTest
## The netcode over real ENet, server and client in one Godot: each in its own branch with its own SceneMultiplayer.

const PORT := 24651

var host_session: NetSession
var join_session: NetSession
var server: ArenaServer
var client: ArenaClient


func before_each():
	var courts := Court.load_all()
	server = ArenaServer.new(courts, 3)
	client = ArenaClient.new(courts)
	host_session = _branch("Host")
	join_session = _branch("Joiner")
	assert_eq(host_session.host(PORT), OK)
	host_session.serve(server)
	assert_eq(join_session.join("127.0.0.1", PORT, client), OK)


func after_each():
	host_session.close()
	join_session.close()


func _branch(branch_name: String) -> NetSession:
	var branch := Node.new()
	branch.name = branch_name
	add_child_autofree(branch)
	get_tree().set_multiplayer(SceneMultiplayer.new(), branch.get_path())
	var session := NetSession.new()
	branch.add_child(session)
	return session


func _wait_for(condition: Callable, frames := 300) -> bool:
	for i in frames:
		if condition.call():
			return true
		await wait_process_frames(1)
	return condition.call()


func test_a_client_joins_plays_and_leaves_over_enet():
	assert_true(await _wait_for(func() -> bool: return client.is_playing()), "welcomed")
	assert_eq(client.slot, 0)
	assert_eq(server.peer_count(), 1)
	for i in 60:
		client.step(1, 0, 1, 0, false)
		server.tick()
		await wait_process_frames(1)
	assert_true(await _wait_for(func() -> bool: return client.snapshots > 20), "snapshots arrive")
	join_session.close()
	assert_true(await _wait_for(func() -> bool: return server.peer_count() == 0), "the server saw it leave")
	assert_true(server.arena.is_bot(0))
