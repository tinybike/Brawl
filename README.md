# Brawl

Just an experiment to see if I can get real time combat working in Baldur's Gate 3.  Warning, this is very barebones right now and is not ready for use in the campaign yet!  Download/test at your own risk...

Thanks to Focus for the idea and advice and [Hippo0o](https://github.com/Hippo0o) for the excellent library.

## Video examples

[![Real time combat test (Baldur's Gate 3)](https://img.youtube.com/vi/nEBW4qIW28c/0.jpg)](https://www.youtube.com/watch?v=nEBW4qIW28c)

[![Real time combat test 2 (Baldur's Gate 3)](https://img.youtube.com/vi/ikxgAcxSv50/0.jpg)](https://www.youtube.com/watch?v=ikxgAcxSv50)

## Status

Seems to play nice with dialog now, at least in the scenario I happened to have a save file near.  Reaction prompts work as expected, although normally I'd have them either fully off or on if I was playing in real-time mode, since they break up the action a lot.  Pausing using the built-in start-turn-based-mode button also basically works although it will need a lot of tuning to make it seem fair.

In the comments on the first video, a lot of people noticed that everything seems really imbalanced, which is 100% true!  Right now, I'm just trying to see if this system fundamentally works, or if there are show-stoppers that would make RTwP impossible in BG3.  I'll worry about balance-related stuff later -- but, among other things, it's definitely true that the enemies attack too quickly in the demo videos.  In the most recent changes, the enemy attacks are slowed down substantially.  I also improved the positioning logic a bit.  I need to stress test it (and maybe record another video?) but I felt like it was smoother overall, and possibly a little less unfair to the player.

The main challenge right now is that the built-in BG3 combat AI is only accessible during normal turn-based combat.  Just to test things out, I'm using a simple randomizer to decide among the enemy units' available actions, spells, etc, but this won't work well for more complicated encounters.  I'm currently digging through the Osiris APIs and Larian's goals (scripts) looking for a way to poll the built-in AI ("what would you do, hypothetically, in this situation?") outside of turn-based combat.  If anyone knows about this, please look me up on Discord (@tinybike, am in both the official Larian and the "secret" unlocked toolkit Discord) -- this stuff is mostly undocumented so it's a bit of a bear to sort through.
