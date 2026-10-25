extends SceneTree

func _initialize() -> void:
	var tracks := Tracks.from_files()
	for id in [1, 2, 3]:
		if not tracks.has_track(id):
			continue
		var track := tracks.track(id)
		print("track %d: %d points, length %.0f, min profile %.0f" % [id, track.point_count(), track.length(), Array(track.speed_profile).min()])
		for rate in [30, 60, 120, 144]:
			var race := Race.new(track, tracks.drivers_for(3, 7, true), rate)
			var off := 0
			while race.finish_order.size() < 4 and race.tick < rate * 200:
				race.step()
				for c in race.cars:
					if not c.on_road: off += 1
			var laps := []
			for t in race.trackers:
				laps.append(Array(t.lap_times).map(func(x): return "%.2f" % (x / float(rate))))
			print("  %d Hz: finish %s, laps %s, off-road ticks %d, lookups/car/tick %.1f" % [rate, race.finish_order, laps, off, track.lookups / float(race.tick * 4)])
			track.lookups = 0
	quit()
