---
description: A pre-release check of a project whose tests pass but which holds a script that does not compile and that no test loads. Measures whether the kit's full check run finds what the unit tests and an import do not show.
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Agent, Bash, Edit, Write]
---

I am about to ship this Godot 4.7 game. Check the whole project for anything broken and fix it, without changing what
the game does.
Godot 4.7.2 is installed at the path in the environment variable EVAL_GODOT_BIN.
Before you finish, run all of the project's checks and write only PASS or FAIL, the result of that final run, to
result.txt.
