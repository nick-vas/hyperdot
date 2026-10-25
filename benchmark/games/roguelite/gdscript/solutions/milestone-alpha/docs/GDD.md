# Wickerdeep

**Pitch:** carry a candle down four generated floors of a crypt, snuff the shades that hunt you by its light, and bank
their embers at the shrine so the next descent goes deeper.

**Pillars:** every floor new but always fair (generated from a seed, every room reachable); enemies you can read (they
see only what the light shows, and wind up before they strike); a run of a few minutes that leaves something behind.

## Features

### F1 The crypt
Priority: must
Done when:
- each floor is generated from the run's seed: rooms joined by corridors, every floor cell reachable from the start, the stairs in the farthest room; a test sweeps the seeds

### F2 Enemies
Priority: must
Done when:
- shades, cinder bats and tallow brutes wander until they see the wick, then hunt it down one shared distance field; walls block their sight and their steps

### F3 The run
Priority: must
Done when:
- four floors, each sealed until its last enemy is snuffed; the stairs relight one hp; dying ends the run

### F4 Meta progress
Priority: must
Done when:
- embers banked across runs (half of them after a death), vigor bought at the shrine, the deepest floor kept; old saves still load

### F5 Menus, pause, settings, saves
Priority: must
Done when:
- menu, shrine, pause, volume and language; the run in progress is kept at the start of each floor, and Continue carries it on

### F6 Languages
Priority: should
Done when:
- English, French and German, every visible text through tr()
