<p align="center">
  <img src="Shuru/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-light.png" width="120" alt="Shuru app icon">
</p>

# Shuru (शुरू)

A to-do app for ADHD brains, built around one idea: **starting** is the hard part. *Shuru* is Hindi for "start".

Instead of a long list, the main screen shows **one next thing** over a slowly moving orb. Plans are written as if–then routines ("When I get home → take a bath → eat dinner → study"), because tying a task to a cue makes it far more likely to happen.

## What's in it

- **Now**: just the next step. Press and hold to finish it: a circle fills (fast at first, slower near the edge), bounces once, and a tick appears with sparkles. Tap for options: make it smaller, start a 5-minute timer, not now, pick one for me.
- **Routines**: if–then chains with time limits per step ("at least 2 min, stop by 3 h"), the days they run on, and a backup plan.
- **Calendar**: a week strip. Past days show what you actually did; future days show what's planned. Unfinished tasks roll over to today.
- **Hours**: your waking day as blocks, so time is visible. Log what each hour went to; tasks you start or finish fill it in automatically.
- **Brain dump**: get it out of your head, sort it later.
- **This week**: no streaks. Tokens (1 per finished task or routine, capped per day, cleared every Monday) to spend on rewards you set.
- **Pause before scrolling**: when Instagram opens, Shuru opens first: breathe, look back, look ahead, say your first step out loud, then decide.

Everything stays on your phone. There is no account and no server.

## Install without a Mac

Every push to `main` builds an unsigned `.ipa` with GitHub Actions.

1. Download **Shuru.ipa** from the [latest release](../../releases/tag/latest).
2. Open it with **SideStore**, **AltStore** or **LiveContainer**. They sign it with your own Apple ID.
3. With a free Apple ID, refresh it in SideStore or AltStore every 7 days.

Notifications are local (check-ins and timed routines), so they work when sideloaded. No push server is needed.

## Make Instagram open Shuru first

1. Open **Shortcuts** → **Automation** → **+** → **App**.
2. Pick **Instagram**, choose **Is Opened**, and set it to **Run Immediately**.
3. Add Shuru's **Pause before scrolling** action.
   In LiveContainer, use LiveContainer's **Launch App** action with the URL `shuru://pause` instead.

If you choose "Back to Instagram for 15 min", Shuru sends you straight back for that long instead of pausing again.

## Build it yourself (Mac)

```sh
brew install xcodegen
xcodegen generate
open Shuru.xcodeproj
```

Requires Xcode 16 and iOS 17 or later.

## Layout

```
Shuru/
  App/        App entry, notification handling, Shortcuts actions
  Model/      Data, saving (JSON in Application Support), queue and tokens
  Theme/      Colours and shared building blocks
  Views/      Now, Calendar, Routines, Composer, Hours, Brain dump, This week, Settings
project.yml   XcodeGen project definition
```

## License

MIT. See [LICENSE](LICENSE).
