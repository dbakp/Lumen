# Lumen Health — premium iOS health tracker

Sleep (Rise-parity engine) + activity + nutrition + AI coach, in one Liquid Glass app.

## Open & run
1. Open `Lumen.xcodeproj` in Xcode 16+ (iOS 18 SDK; Liquid Glass lights up on iOS 26).
2. Select the **Lumen** scheme, any iPhone simulator, press Run. No manual setup needed:
   - **Bundle IDs**: `com.lumen.health` + `com.lumen.health.LumenWidget`
   - **Privacy keys**: Health (share + update), Camera, Photos, Motion, Notifications — baked into build settings
   - **Strava + Google OAuth callbacks**: `lumen://` URL scheme registered
   - **Capabilities**: HealthKit + App Groups (`group.com.lumen.health`) via entitlements
   - **Background modes**: audio (sleep sounds) + fetch
   - **App icon, accent color, privacy manifest, widget**: included
3. Sign in with your Apple ID in Xcode (Signing & Capabilities) to run on a real iPhone.

Only two things need your own credentials (both entered **in the app, on the phone** — Profile tab):
- **Strava**: free app at `strava.com/settings/api` → paste Client ID + Secret in code (`StravaService.swift`), then Profile → Connect.
- **Coach AI** (optional): API key (OpenAI, or Google AI Studio with its preset) **or** Google OAuth (PKCE, `lumen://oauth-callback` registered as redirect). Without either, the coach runs fully on-device with your real data.

## What it does
- **Today**: readiness dial + Move/Exercise/Stand rings + 3-bullet coach briefing + fuel + movement + insights. LIVE/DEMO pill always tells you if numbers are real.
- **Activity**: unified workouts (HealthKit + Strava + manual, deduped), vitals (RHR, HRV, SpO₂, weight), weekly load.
- **Snap/Nutrition**: photo → calories + protein in <10s (AI vision if connected, on-device estimate otherwise), macros, hydration, quick-add.
- **Coach**: chat grounded in your real data (offline brain + optional LLM), insight cards, suggestion chips.
- **Sleep**: 14-night debt, personal sleep need, circadian energy schedule, rituals, sounds, library.
- **Real-data-first**: connecting HealthKit/Strava (or logging your own data) permanently retires all demo samples.

## Architecture
- `Models/` — `HealthModels` (Workout/DayMetrics/Readiness/DayPlan/Goals), `NutritionModels`, `HealthStore` (single source of truth), sleep models/store
- `Algorithms/` — `CoachingEngine` (readiness/strain/protein-first plan), `SleepAlgorithms`
- `Services/` — `HealthKitExtended`, `StravaService`, `NutritionEngine`, `ChatCoachService`, `LLMConnectionService` (key + OAuth PKCE → OpenAI-compatible `LLMClient`), notifications, sounds
- `Views/` — Today/Activity/Nutrition/MealCapture/Coach + sleep engine + PremiumUI/HealthCharts components
- `LumenUITests/` — automated smoke test (onboarding → 5 tabs → Snap → Profile → Coach chat)

## Testing
- `swiftc` logic suite: 23 assertions over debt/need/energy/readiness/goals — all pass.
- `xcodebuild test -scheme Lumen`: UI smoke test green on iPhone 17 Pro simulator, screenshots attached to the result bundle.
- Not testable headless (needs your hands + real iPhone): HealthKit permission flow, camera capture, Strava/Google OAuth redirects, haptics, widget on the home screen.

## Production notes
- Move Strava secret + LLM tokens from UserDefaults to Keychain.
- Set your Development Team + App Group ID; file HealthKit/App Store privacy as needed.
- Not medical advice; red-flag symptoms → see a clinician.
