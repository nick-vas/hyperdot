One test fails: `test_past_decillions_letters_take_over` in `test/unit/test_numbers.gd`, line 31.

It expected `Numbers.format(1.5e36)` to give "1.50aa" and got "1.50e36". Its other two checks fail the same way
(line 32 expected "1.00ab" and got "1.00e39"; line 33 expected "1.00ba" and got "1.00e114").

The game is wrong, not the test. Past the last short name (Dc, 1e33), `Numbers.suffix` in `scripts/numbers.gd` returns
"e" and the exponent (`"e%d" % (group * 3)`) instead of the two-letter names aa, ab ... zz, so every number from
1e36 up prints in a form of scientific notation, which the game's numbers are meant never to use. The test states
that rule; the fix belongs in `Numbers.suffix`.
