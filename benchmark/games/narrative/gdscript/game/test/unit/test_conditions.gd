extends GutTest
## Conditions: a choice's needs in the criteria grammar.


func test_empty_needs_always_hold():
	assert_true(Conditions.holds("", {}))
	assert_true(Conditions.holds("  ", {"trust": 3}))


func test_not_holds_only_on_zero_or_missing():
	assert_true(Conditions.holds("!afraid", {}))
	assert_true(Conditions.holds("!afraid", {"afraid": 0}))
	assert_false(Conditions.holds("!afraid", {"afraid": 1}))


func test_at_least_holds_on_the_bound_and_above():
	assert_false(Conditions.holds("trust>=2", {"trust": 1}))
	assert_true(Conditions.holds("trust>=2", {"trust": 2}))
	assert_true(Conditions.holds("trust>=2", {"trust": 5}))


func test_each_operator():
	var flags := {"trust": 2}
	assert_true(Conditions.holds("trust=2", flags))
	assert_false(Conditions.holds("trust<2", flags))
	assert_true(Conditions.holds("trust<=2", flags))
	assert_false(Conditions.holds("trust>2", flags))
	assert_true(Conditions.holds("trust>1", flags))


func test_every_criterion_must_hold():
	assert_true(Conditions.holds("trust>=2;!afraid", {"trust": 2, "afraid": 0}))
	assert_false(Conditions.holds("trust>=2;!afraid", {"trust": 2, "afraid": 1}))
	assert_false(Conditions.holds("trust>=2; !afraid", {"trust": 1, "afraid": 0}))


func test_keys_lists_the_flags_read():
	assert_eq(Conditions.keys("trust>=2;!afraid"), PackedStringArray(["trust", "afraid"]))
	assert_eq(Conditions.parse("lied=1")[0], {"key": "lied", "op": "=", "value": 1})
