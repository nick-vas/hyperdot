The failing test is `Three_kind_words_give_three_trust` in `test/StoryTest.cs`, at line 27
(`AssertThat(story.Flags["trust"]).IsEqual(3)`): after three kind words (greeting the stranger, the honest toll and
asking her name) it expected trust 3 and got 6.

The game is wrong, not the test. Each of those choices raises trust once (`data/choices.json`: `"raise": ["trust"]`), so
three of them should give 3. In `Story.Choose` (`scripts/Story.cs`) the loop over `choice.Raise` calls `Change` twice
for each flag, so every raise adds two. The other tests do not count trust, so they pass.
