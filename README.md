# Lumen Health — world-class iOS health tracker

Premium Liquid Glass health OS: sleep (Rise-parity engine) + activity + nutrition + AI coach.

## Open in Xcode
1. Xcode 16+ / iOS 18 SDK (Liquid Glass `glassEffect` lights up on iOS 26, graceful blur fallback below).
2. Create a new iOS App project named **Lumen**, bundle id `com.lumen.health`, then drag the `Lumen/` folder into it (or copy these files over).
   - Add frameworks: HealthKit, WidgetKit, Charts, Vision, PhotosUI, AuthenticationServices, UserNotifications.
   - Add the `LumenWidget` target from `LumenWidget/LumenWidget.swift`.
3. Set URL scheme for Strava OAuth: Info → URL Types → `lumen` (so `lumen://strava-callback` works).
4. Paste the Info plist keys from `Resources/InfoPlistKeys.txt`.
5. Enable capabilities: HealthKit, Background Modes (background fetch + background processing for overnight sync), App Groups (for widgets, e.g. `group.com.lumen.health`).

## Integrations
- **Apple Health**: `HealthKitExtended` reads steps, Move/Exercise/Stand, workouts, HR, RHR, HRV, SpO₂, weight, sleep, water, nutrition; writes meals + water back so the Health app stays in sync.
- **Strava**: `StravaService` — create a free API app at strava.com/settings/api, paste Client ID/Secret, connect from Profile → Strava. Activities dedupe against HealthKit by time overlap.
- **Watch / Oura / Whoop / Garmin**: anything that writes to HealthKit (or syncs via Strava for Garmin) flows in automatically. No extra SDKs needed.
- **Photo food logging**: `NutritionEngine` — instant on-device estimate; add an OpenAI-compatible key in Profile → Coach AI for true vision accuracy (`gpt-4o-mini` default, custom endpoint supported).
- **Coach chat**: `ChatCoachService` — offline rule-based brain grounded in your real data; upgrades to LLM with the same key.

## Architecture
- `Models/HealthModels.swift` — Workout, DayMetrics, Readiness, DayPlan, HealthGoals (Mifflin-St Jeor)
- `Models/NutritionModels.swift` — Meal, FoodItem, MealAnalysis, ChatMessage, Insight
- `Models/HealthStore.swift` — single source of truth, sample-seeded, persisted
- `Algorithms/CoachingEngine.swift` — readiness, strain target, protein-first plan, insights
- `Services/HealthKitExtended.swift`, `StravaService.swift`, `NutritionEngine.swift`, `ChatCoachService.swift`
- `Views/TodayView.swift` (hero), `ActivityView`, `NutritionView`, `MealCaptureView`, `CoachView`, sleep engine untouched
- `Views/Components/PremiumUI.swift`, `HealthCharts.swift` — glow rings, animated numbers, briefing + insight cards

## What makes it world-class (research notes)
- One glance answers "how am I + what next": readiness dial + 3-bullet briefing, never a data dump.
- Readiness from HRV + RHR + sleep debt + strain balance (Whoop/Oura lesson); strain target adapts.
- Protein-first, shame-free nutrition; photo → confirm in <10s (MacroFactor/MyFitnessPal lesson).
- Circadian energy schedule carried over from the sleep engine (Rise lesson).
- Rings + streaks + haptics + earned celebration (Apple Fitness lesson).
- Privacy: on-device first, keys on-device, HealthKit descriptions honest.

## Privacy
Not medical advice. Red-flag symptoms → see a clinician. Keys stored in UserDefaults for the demo — move to Keychain for production.
