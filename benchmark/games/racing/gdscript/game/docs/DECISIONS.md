# Decisions

- 2026-10-01 Prototype verdict: PROCEED. One oval, one car and three AI rivals were enough to feel the braking points.
- The race lives in plain classes (Car, Track, LapTracker, AiDriver, Race, Ghost), so tests run whole races without a
  scene; the game node only counts down, reads the input and draws.
- Physics on a fixed step with every rate per second, and drag taken implicitly (no exp()), so a lap takes the same time
  at any tick rate and replays the same on every machine.
- Every input is quantised to hundredths before a car uses it, so a ghost of inputs replays its lap exactly.
- Laps by gates crossed in order and direction, never by distance travelled: the grass infield cannot be a shortcut.
- The camera moves every drawn frame with exponential easing and a hard limit on how far the car may be from the middle.
- Only keyboard keys are rebindable; the gamepad keeps its bindings, so a bad rebind never locks a player out.
