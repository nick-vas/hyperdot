# Cinderloop

**Pitch:** a small top-down racer: three tracks of cinder road, three rivals who drive the racing line at their own
pace, and the ghost of your best lap to beat.

**Pillars:** handling that is the same on every machine (a fixed step, a replay that never drifts); a fair lap (every
checkpoint, in order); a camera that always shows the car and the road ahead.

## Features

### F1 Handling
Priority: must
Done when:
- throttle, brake and reverse, steering that needs speed and grip that limits it at speed, the grass slower than the
  road, and the same lap time at any physics tick rate

### F2 Laps
Priority: must
Done when:
- checkpoints crossed in order and in the direction of travel make a lap; lap times to the thousandth; a shortcut
  across the grass never counts

### F3 Rivals
Priority: must
Done when:
- three rivals follow the racing line, braking for the bends at their own pace; the grid is shuffled by the race seed

### F4 Ghost
Priority: must
Done when:
- the best lap is recorded as inputs, saved with its time, and drives the same line when played back

### F5 Camera
Priority: must
Done when:
- the view looks ahead of the car, eases at the same speed at any frame rate and never lets the car leave the screen

### F6 Menus, pause, settings, saves
Priority: must
Done when:
- track select, pause and restart, volume, language and rebindable keys (the gamepad always works); best laps, ghosts,
  open tracks and keys are saved, and old saves load

### F7 Languages
Priority: should
Done when:
- English, French and German, every visible text through tr()
