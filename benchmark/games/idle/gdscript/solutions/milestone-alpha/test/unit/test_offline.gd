extends GutTest
## Offline progress: the time since the save is paid at the rate saved, up to the cap.

var economy: Economy


func before_each():
	economy = Economy.new(Catalog.from_files())
	economy.owned["glow_snail"] = 5
	economy._dirty = true


func test_an_hour_away_pays_an_hour():
	var away := Offline.apply(economy, 1000.0, 1000.0 + 3600.0)
	assert_eq(away.seconds, 3600.0)
	assert_almost_eq(away.glow, 3600.0 * 20.0, 1e-6)
	assert_almost_eq(economy.glow, 3600.0 * 20.0, 1e-6)


func test_time_away_is_capped_at_eight_hours():
	var away := Offline.apply(economy, 0.0, 30.0 * 86400.0)
	assert_eq(away.seconds, 28800.0)
	assert_almost_eq(economy.glow, 28800.0 * 20.0, 1e-6)


func test_no_time_no_glow():
	var away := Offline.apply(economy, 5000.0, 5000.0)
	assert_eq(away.glow, 0.0)
