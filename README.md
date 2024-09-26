# Brawl

Just an experiment to see if I can get real time combat working in Baldur's Gate 3.  Warning, this is very barebones right now and is not ready for use in the campaign yet!  Download/test at your own risk...

Thanks to Focus for the idea and advice and [Hippo0o](https://github.com/Hippo0o) for the excellent library.

## Status

- Reactions: ok
- Pausing: ok, still needs tuning
- Dialogue: ok (pending further testing)
- Sprinting during fights: fixed
- Combat start delay: fixed
- Crashing during fights: fixed (pending further testing)
- Enemy round timer: fixed (pending further testing)
- Enemy fight stance vfx: fixed
- Player fight stance vfx: unimplemented
- Enemy death vfx: band-aided / fixed to the casual observer...
- Enemy AI: usable but very simplistic (see below)
- Companion AI: unimplemented
- Tracking/targeting assist: unimplemented
- Multiple attacks: unimplemented
- Initiative: unimplemented
- Haste: unimplemented
- Bonus actions: the same as actions :/
- Attacks of opportunity: unimplemented
- Stealth: unimplemented
- Balance: utterly borked

Many people have commented that combat seems really imbalanced, which is 100% true!  Right now, I'm just trying to see if this system fundamentally works, or if there are show-stoppers that would make RTwP impossible in BG3.  (Among other things, it's definitely true that the enemies attack too quickly in the demo videos...)

The main challenge right now is that the built-in BG3 combat AI is only accessible during normal turn-based combat.  Just to test things out, I'm using a simple randomizer to decide among the enemy units' available actions, spells, etc, but this won't work well for more complicated encounters.  I'm currently digging through the Osiris APIs and Larian's goals (scripts) looking for a way to poll the built-in AI ("what would you do, hypothetically, in this situation?") outside of turn-based combat.  If anyone knows about this, please look me up on Discord (@tinybike, am in both the official Larian and the "secret" unlocked toolkit Discord) -- this stuff is mostly undocumented so it's a bit of a bear to sort through.

## Videos

[![Real time combat test (Baldur's Gate 3)](https://img.youtube.com/vi/nEBW4qIW28c/0.jpg)](https://www.youtube.com/watch?v=nEBW4qIW28c)

[![Real time combat test 2 (Baldur's Gate 3)](https://img.youtube.com/vi/ikxgAcxSv50/0.jpg)](https://www.youtube.com/watch?v=ikxgAcxSv50)
