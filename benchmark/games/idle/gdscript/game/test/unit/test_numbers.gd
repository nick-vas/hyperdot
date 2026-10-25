extends GutTest
## Numbers: how glow is shown, from a few motes to past a double's 2^53, and the arithmetic behind it.


func test_small_numbers_are_whole_or_one_decimal():
	assert_eq(Numbers.format(0.0), "0")
	assert_eq(Numbers.format(0.5), "0.5")
	assert_eq(Numbers.format(7.0), "7")
	assert_eq(Numbers.format(999.9), "999")


func test_thousands_take_a_suffix_and_three_digits():
	assert_eq(Numbers.format(1000.0), "1.00K")
	assert_eq(Numbers.format(12345.0), "12.3K")
	assert_eq(Numbers.format(999999.0), "999K")
	assert_eq(Numbers.format(1.5e9), "1.50B")
	assert_eq(Numbers.format(2.5e12), "2.50T")


func test_the_screen_rounds_down():
	assert_eq(Numbers.format(1999.0), "1.99K")
	assert_eq(Numbers.format(9.999e6), "9.99M")


func test_decillions_are_the_last_short_name():
	assert_eq(Numbers.format(1e33), "1.00Dc")
	assert_eq(Numbers.format(4.2e35), "420Dc")


func test_past_decillions_letters_take_over():
	assert_eq(Numbers.format(1.5e36), "1.50aa")
	assert_eq(Numbers.format(1e39), "1.00ab")
	assert_eq(Numbers.format(1e114), "1.00ba")


func test_no_number_prints_in_scientific_notation():
	for exponent in range(0, 301, 7):
		var text := Numbers.format(("3.7e%d" % exponent).to_float())
		assert_false(text.contains("e+") or text.contains("e-"), text)
		assert_lte(text.length(), 6, text)


func test_powers_are_multiplied_out():
	assert_eq(Numbers.power(1.15, 0), 1.0)
	assert_eq(Numbers.power(2.0, 10), 1024.0)
	assert_true(Numbers.close(Numbers.power(1.15, 100), 1174313.4507002793, 1e-14))
	assert_eq(Numbers.power(2.0, -2), 0.25)


func test_close_is_relative():
	assert_true(Numbers.close(1e20, 1e20 + 1e7))
	assert_false(Numbers.close(1e20, 1e20 * (1.0 + 1e-10)))
