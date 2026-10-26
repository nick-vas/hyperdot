One test fails: `Past_decillions_letters_take_over` in `test/NumbersTest.cs`, line 47.

It expected `Numbers.Format(1.5e36)` to give "1.50aa" and got "1.50e36". Its other two checks would fail the same way
(line 48 expects "1.00ab" and would get "1.00e39"; line 49 expects "1.00ba" and would get "1.00e114"), but gdUnit4
stops a test at its first failed assertion.

The game is wrong, not the test. Past the last short name (Dc, 1e33), `Numbers.Suffix` in `scripts/Numbers.cs` returns
"e" and the exponent (`"e" + (group * 3)`) instead of the two-letter names aa, ab ... zz, so every number from 1e36 up
prints in a form of scientific notation, which the game's numbers are meant never to use. The test states that rule;
the fix belongs in `Numbers.Suffix`.
