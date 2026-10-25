# Decisions

- 2026-10-01 Prototype verdict: PROCEED. Five producers and one upgrade per producer are enough for a choice every minute.
- The economy lives in plain classes (Economy, Catalog, Offline, Bot), so tests play hours of it without a scene.
- Glow is a double: exact to 2^53, then to a relative 1e-12, which is more than the three digits the screen shows.
  Numbers are printed with suffixes and two-letter groups, never in scientific notation.
- No code in scripts/ reads the clock: Main gives Offline the time, so offline progress is tested with any clock.
- Portrait first (720x1280, phones and the Web), with a SafeArea autoload for notches; Android and Web exports.
