<p align="center">
  <img src="Shuru/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-light.png" width="120" alt="Shuru app icon">
</p>

# Shuru (शुरू)

A to-do app for ADHD brains, built around one idea: **starting** is the hard part. *Shuru* is Hindi for "start".

Instead of a long list, the main screen shows **one next thing** over a slowly moving orb. Plans are written as if–then routines ("When I get home → take a bath → eat dinner → study"), because tying a task to a cue makes it far more likely to happen.

## What's in it

- **Now**: just the next step. Press and hold to finish it: a circle fills (fast at first, slower near the edge), bounces once, and a tick appears with sparkles. Tap for options: make it smaller, start a 5-minute timer, not now, pick one for me.
- **Routines**: if–then chains with time limits per step ("at least 2 min, stop by 3 h"), the days they run on, and a backup plan.
  Routines with a cue ("When I get home") wait until it happens: save a location and Shuru starts them when you arrive, or tap Start, or run them from a Shortcut (`shuru://start?routine=<id>`).
- **Calendar**: a week strip. Past days show what you actually did; future days show what's planned. Unfinished tasks roll over to today.
- **Hours**: your waking day as blocks, so time is visible. Log what each hour went to; tasks you start or finish fill it in automatically.
- **Brain dump**: get it out of your head, sort it later.
- **This week**: no streaks. Tokens (1 per finished task or routine, capped per day, cleared every Monday) to spend on rewards you set.
- **Pause before distracting apps**: Instagram, YouTube, X, Safari, Twitch, games, any app you pick. Shuru opens first: breathe, look back, look ahead, say your first step out loud, then decide. To keep going, spend tokens on time (1 token = 15 min by default) or use one of a few free 2-minute quick looks.

Everything stays on your phone. There is no account and no server.

## Add to SideStore (gets updates)

In SideStore or AltStore, go to **Sources** → **+** and paste:

```
https://github.com/Priyansh-Singh/Shuru---An-ADHD-Companion-App/releases/latest/download/source.json
```

Shuru then shows up in the source with an **Install** button, and every new build appears as an update.

## Install without a Mac

Every push to `main` builds an unsigned `.ipa` with GitHub Actions.

1. Download **Shuru.ipa** from the [latest release](../../releases/latest). Every version also has its own release under [Releases](../../releases).
2. Open it with **SideStore**, **AltStore** or **LiveContainer**. They sign it with your own Apple ID.
3. With a free Apple ID, refresh it in SideStore or AltStore every 7 days.

Notifications are local (check-ins and timed routines), so they work when sideloaded. No push server is needed.

## Set up the pause for your apps (one automation)

iOS doesn't let apps create automations, so this is a one-time setup in Shortcuts:

1. **Automation** → **+** → **App**. Pick every app you want a pause before (Instagram, YouTube, X, Safari, Twitch, games…).
2. Keep **Is Opened**, choose **Run Immediately**, then **New Blank Automation**.
3. Add Shuru's **Check before opening** action and set **App** to **Shortcut Input**.
4. Add **If** → *Result* *is true*, and inside it Shuru's **Pause before opening** action (App = Shortcut Input).

The check runs without opening Shuru, so when you've bought time and go back to the app, nothing loops. Apps appear under **Settings → Connected apps** once their automation has run.

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
