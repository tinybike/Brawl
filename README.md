# Brawl

Just an experiment to see if I can get real time combat working in Baldur's Gate 3.  Warning, this is very barebones right now!  [Download and use at your own risk.](https://www.nexusmods.com/baldursgate3/mods/12614/)

Thanks to Focus for the idea and advice and [Hippo0o](https://github.com/Hippo0o) for the excellent library.

## Status

Lots of stuff unimplemented and/or maybe not feasible to implement for RTwP, but, I'm testing the mod out in act 1 and so far it seems okay...

- Reactions: ok
- Pausing: ok (pending further testing)
- Dialogue: ok (pending further testing)
- Sprinting during fights: fixed
- Combat start delay: fixed
- Crashing during fights: fixed (pending further testing)
- Enemy round timer: fixed (pending further testing)
- Enemy fight stance vfx: fixed
- Player fight stance vfx: unimplemented
- Enemy death vfx: band-aided / fixed to the casual observer...
- Enemy AI: usable but very simplistic (see below)
- Companion AI: usable but very simplistic (see below)
- Companion AIs at least know to help you up if you're at 0 hitpoints: nope lol
- Weird bug where your companions don't go down at 0 hitpoints: fixed (functionally, but vfx are still wonky)
- Bug where the AI takes control of your active character: fixed
- Tracking/targeting assist: unimplemented, but [this mod](https://www.nexusmods.com/baldursgate3/mods/10445) helps a ton
- Multiple attacks: unimplemented
- Initiative: unimplemented
- Haste: unimplemented
- Bonus actions: the same as actions :/
- Attacks of opportunity: unimplemented
- Stealth: unimplemented
- Balance: utterly borked

Many people have commented that combat seems really imbalanced, which is true.  Still in very early testing to find gamebreaking bugs etc.  Balance should hopefully improve over time as everything gets ironed out.

The built-in BG3 combat AI is only accessible during normal turn-based combat, which means that sadly this mod cannot tap into it.  (If you know of a way around this, please let me know.)  I set up some very simple handrolled "AI" logic just to test things out.  I expected this to fall flat on its face for more complex encounters, but I just did the Emerald Grove fight (where you meet Wyll) and it basically seems okay.

## Videos

### 1) Basic Combat

[![Real time combat test 1](https://img.youtube.com/vi/nEBW4qIW28c/0.jpg)](https://www.youtube.com/watch?v=nEBW4qIW28c)

### 2) Pausing, Dialogue, and Reactions

[![Real time combat test 2](https://img.youtube.com/vi/ikxgAcxSv50/0.jpg)](https://www.youtube.com/watch?v=ikxgAcxSv50)

### 3) Companions and Timers

[![Real time combat test 3](https://img.youtube.com/vi/C0FBQknd0mU/0.jpg)](https://www.youtube.com/watch?v=C0FBQknd0mU)

### 4) Early Act 1 Fights

[![Real time combat test 4](https://img.youtube.com/vi/q3lnl3lcDXg/0.jpg)](https://www.youtube.com/watch?v=q3lnl3lcDXg)
