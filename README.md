# Lumen

A calm, private health coach for iPhone. Lumen brings sleep, energy, movement and nutrition together in one place, learns your body's rhythm from Apple Health, and tells you what to do today.

Built natively in SwiftUI with a Liquid Glass design. Everything is stored on your device.

## Features

- **First-run onboarding.** You create a local profile, connect Apple Health (which prefills your age, sex, height and weight and imports your full sleep history), set your focus and activity level, set up your rhythm and reminders, and get a personalised plan.
- **Today.** A readiness score from sleep debt, resting heart rate and HRV. It shows "calibrating" until there's real data and never guesses. Also on this screen: activity rings, a coach briefing, vitals, fuel, movement and insights. Tap readiness to see what's driving it.
- **Sleep.**
  - Up to two years of nights imported from Health, with stages (deep, core, REM, awake) and efficiency.
  - A personal sleep need and 14-night sleep debt.
  - A circadian energy curve, a timed daily schedule and a suggested bedtime.
  - A journal, rituals, sleep sounds and short science articles.
- **Activity.** Workouts from Apple Health, Strava and manual logs, deduplicated and grouped by day. Also training load and vitals (resting HR, HRV, SpO₂, respiratory rate, weight, VO₂ max).
- **Trends.** 7-day, 30-day, 90-day and 1-year charts for sleep, steps, active energy, exercise, resting HR, HRV and weight. Each shows the average, the change versus the previous period, and the best day, with scrub-to-inspect.
- **Snap & nutrition.** Photo meal logging and quick-add, protein-first macros, hydration, and a 7-day history. Meals, water and weight are written back to Apple Health.
- **Coach.** Chat grounded in your real data. It runs fully on-device by default; you can optionally connect your own AI provider (API key or Google OAuth with PKCE).
- **Apple Watch.** A companion app with six vertical pages:
  - Readiness and today's training window.
  - Last night's sleep with stages, debt and energy.
  - Tonight's bedtime, wind-down, melatonin window, caffeine cutoff and energy curve.
  - Live activity rings, steps and heart rate read on the wrist.
  - Fuel, with one-tap water logging saved to Health.
  - Rituals you can check off from your wrist.
  - Complications: readiness (circular, rectangular, corner, inline) and bedtime.
- **Widgets.** Readiness (small, medium, Lock Screen rectangular and circular) and a one-tap "Snap a meal" widget, both with deep links into the app.
- **Privacy.**
  - Local-first storage in the App Group container.
  - Secrets (API keys, OAuth tokens) kept in the Keychain.
  - Optional Face ID lock.
  - One-tap JSON export and erase-all.

## Data

Lumen is local-first:

| What | Where |
| --- | --- |
| Profile, sleep, meals, workouts, water, goals, chat | JSON files in the App Group container (`LocalStore`) |
| API keys, OAuth tokens, Strava credentials | Keychain (`SecureStore`) |
| Widget snapshot | Shared `UserDefaults` in the App Group |
| Apple Watch | The phone sends a `WatchSnapshot` via WatchConnectivity application context; the Watch sends back ritual check-offs and water. Activity and heart rate are read directly on the Watch |
| Health data | Read from Apple Health on launch and on every return to the foreground. Meals, water and weight are written back |

The persistence layer is isolated in `Persistence/`, so a sync backend (for example Supabase) can be added later without touching the views.

## Build & run

1. Open `Lumen.xcodeproj` in Xcode 26 or later (iOS 18+; Liquid Glass lights up on iOS 26).
2. Select the **Lumen** scheme and run on a simulator or an iPhone.
   - Bundle IDs are `com.dbakp.lumen`, `com.dbakp.lumen.LumenWidget`, `com.dbakp.lumen.watchkitapp` and `com.dbakp.lumen.watchkitapp.widgets`, with the App Group `group.com.dbakp.lumen`.
   - The Watch app is embedded in the iPhone app. Install it from the iPhone's Watch app, or run the **LumenWatch** scheme on a watch with Developer Mode enabled.
   - To use a different Apple developer team, change `DEVELOPMENT_TEAM` and the IDs above.
3. Sources are folder-synced: new files under `Lumen/` are picked up automatically.

Optional connections, configured in the app under **Settings**:

- **Strava.** Create a free API app at strava.com/settings/api, then paste the Client ID and Secret.
- **Coach AI.** Add an OpenAI-compatible API key (OpenAI, Google AI Studio, or a custom endpoint), or use Google OAuth.

## Architecture

- `Persistence/`: `LocalStore` (file-based JSON in the App Group) and `SecureStore` (Keychain).
- `Models/`: `SleepStore` and `HealthStore` (single sources of truth), sleep, health and nutrition models, units.
- `Algorithms/`: `SleepAlgorithms` (sleep need, debt, circadian prediction) and `CoachingEngine` (readiness, day plan, insights).
- `Services/`:
  - `HealthKitService`: permissions, today, sleep with stages, workouts, history, write-back.
  - `SyncCoordinator`: keeps the stores in step.
  - `WatchSync`: pushes the snapshot to the Watch and handles its messages.
  - Notifications, Strava, the LLM client, nutrition, sounds, app lock and deep links.
- `Views/`: Onboarding, Today, Activity, Trends, Sleep, Nutrition, Coach and Settings, plus the design system components.
- `Shared/`: `WatchSnapshot`, compiled into both the iPhone and Watch targets.
- `LumenWatch/`: the watchOS app (`WatchStore` for WatchConnectivity and HealthKit on the wrist, plus the page views).
- `LumenWatchWidget/`: watch complications.
- `LumenWidget/`: WidgetKit extension.
- `LumenUITests/`: an end-to-end smoke test covering fresh onboarding, every tab, logging a workout and a night, and coach chat.

## Testing

```bash
xcodebuild test -project Lumen.xcodeproj -scheme Lumen -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

The UI test launches with `-resetForUITests` so it always starts from a clean onboarding. Screenshots of every screen are attached to the result bundle.

Some things can only be checked on a real iPhone: the HealthKit permission sheet, camera capture, the Strava and Google OAuth redirects, haptics, Face ID, and widgets on the Home Screen.

## Disclaimer

Lumen provides wellness guidance, not medical advice. If you suspect a sleep disorder or another health condition, talk to a clinician.
