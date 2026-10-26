# Saltmere Crossing

**Pitch:** ferry a stranger across the Saltmere at night and choose what to say on the way: a short branching story,
told a line at a time, with three endings.

**Pillars:** every choice changes something the story remembers (a flag, the stranger's trust); a crossing read in a
few minutes, worth crossing again; the same story in every language.

## Story

You keep the night ferry at Hensmouth. A stranger in a grey coat asks to be taken to Greywick on the far bank. You
**greet** her or keep silent, **name** the toll honestly or **lie**, **steady** yourself or **hurry** when the fog comes
down, **ask** her name, her bag and the bell you hear, and on the far bank **land**, **turn back** or **row** to the
drowned tower.

## Features

### F1 The story as data
Priority: must
Done when:
- nodes, choices, flags and endings in data/*.json, checked by the data runner; the story check finds every node and
  ending reachable and every flag both set and read

### F2 Choices that matter
Priority: must
Done when:
- choices need flags (the kit's criteria) and raise, set or clear them; the questions at the crossing are asked once

### F3 Three endings
Priority: must
Done when:
- the letter (trust and calm), the empty seat (turning back) and the drowned bell (the stranger's tale); a bot reaches each

### F4 Menus, pause, history, saves
Priority: must
Done when:
- menu, pause, a history of the lines so far; the story is saved at every line and Continue carries on; old saves load

### F5 Languages
Priority: should
Done when:
- English, French and German; every text in a box has a length limit the l10n runner checks
