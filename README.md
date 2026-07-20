# Forge (working title)

Structured strength programming + training-load-adaptive nutrition. See `../prd.html`, `../engineering-backlog.html`, and `../Wireframes/` for product context.

## Structure

- `Sources/ForgeCore` — pure Swift business logic (Load Score, TDEE, macro/calorie engine). No UIKit/SwiftUI dependency, builds and tests with just the Swift toolchain — no Xcode required.
- `Tests/ForgeCoreTests` — Swift Testing (`import Testing`) coverage for the engine above.
- `App/` — the SwiftUI iOS app. Requires Xcode to build.
- `project.yml` — [XcodeGen](https://github.com/yonaskolb/XcodeGen) spec. The `.xcodeproj` is generated, not committed — regenerate after adding files.
- `FoodProxy/` — a small Node/Express server that proxies FatSecret API calls (see its README for why: FatSecret requires a fixed, allowlisted IP and server-held credentials, which a mobile app can't provide directly). Deployed separately (Render), not part of the Xcode project.

## Getting started

Xcode is installed on this machine. XcodeGen isn't available via Homebrew here (Homebrew itself isn't installed), so it was built from source once — if you need to regenerate the project after adding files and don't have `xcodegen` on PATH, either `brew install xcodegen` or build it yourself:

```
git clone --depth 1 https://github.com/yonaskolb/XcodeGen.git /tmp/XcodeGen
cd /tmp/XcodeGen && swift build -c release --product xcodegen
```

Then from this folder: `xcodegen generate`, open `Forge.xcodeproj`, select a simulator, and run.

To run just the engine tests: `swift test`.

## Status (2026-07-20)

**Done and verified — both compiled and run in Simulator (iPhone 17), not just compile-checked:**
- `ForgeCore` — Load Score, TDEE/macro calculation, RED-S floor guardrail, carb-band selection, weekly weight-trend recalibration (FRG-301), progressive-overload suggestions (FRG-113), exercise library (`free-exercise-db`, 873 exercises), food database layer (USDA FDC + Open Food Facts + FatSecret, see below). 33 tests passing (`swift test`), stable across repeated runs.
- Onboarding (4 steps), Today, Target Explanation sheet, Train (per-exercise sets with RPE picker), Eat (diary + **live food search** against real USDA/Open Food Facts data, barcode scan entry point, recent/frequent foods), Progress, You. Both light and dark mode confirmed.
- **Food database (FRG-120–124, P0) + barcode scanning (FRG-125, P1) + recent/frequent foods (FRG-302, P1)**: `FoodSearchService` queries USDA FDC and Open Food Facts concurrently and merges results — confirmed with real live network calls in Simulator, not just mocked tests. `FatSecretClient` now calls a proxy server (`FoodProxy/`) instead of FatSecret directly — real credentials confirmed the OAuth2 flow itself is correct (live curl test: token exchange succeeded), but FatSecret rejects direct calls from a mobile app's IP by design (see `FoodProxy/README.md`). The proxy code is built and passes local review + the full test suite, but hasn't been deployed yet — that's the one remaining unverified step, blocked on the user deploying `FoodProxy/` to Render and allowlisting its IP in the FatSecret dashboard.

**Real bugs and findings from actually running this, not from reading the code:**
1. **RED-S floor over-elevated ordinary targets.** Fixed to 30×FFM alone; see PRD Appendix step 3.
2. **Macros didn't sum to the stated calorie total** during a cut. Carbs now compress to fit the budget; protein and the fat floor never move. See PRD Appendix step 4.
3. **Every exercise's sets showed the same seed weight** regardless of which exercise. Fixed.
4. **A single-data-point bodyweight chart** rendered as an invisible axis. Added an explicit empty state.
5. **Open Food Facts silently blocks generic User-Agent strings** — returns an HTML bot-wall page instead of an error. Not documented loudly anywhere; found by trial and error against the live API.
6. **Open Food Facts has no locale awareness by default** and skews heavily French/European — an English "chicken breast" query returned almost entirely French-labeled products until scoped with a country filter (`Secrets.foodDatabaseCountryFilter`, set to `"canada"`). Even scoped, OFF's Canadian coverage is thin for generic categories — USDA's US-branded results (many sold in Canada too) end up filling that gap, which is an honest reflection of real data availability, not a bug to chase further.
7. **A test-harness bug, not a product bug**: the mock network layer for food-database tests (`MockURLProtocol`) used one shared static dictionary, and Swift Testing parallelizes across suites by default — two tests stubbing the same URL fragment raced and clobbered each other intermittently. Fixed by consolidating the network-dependent tests into one `.serialized` suite; confirmed stable across 5+ repeated runs.

**PostHog (FRG-003)**: live and verified — `PostHogSDK` initializes with the real Project API Key in `App/ForgeApp.swift`, confirmed via a real network trace in Simulator (TLS handshake + HTTP 304 from `us-assets.i.posthog.com`, not just a compile check). Two Goal 05 events instrumented so far: `onboarding_completed` (program + goal chosen) and `progress_viewed` (history-depth engagement). More events can be added the same way as other Goal 05 signals (e.g. AI-convenience feature usage) become buildable.

**FRG-301, FRG-304, FRG-306, FRG-307 (P1 fast-follows)** — no wireframes existed for any of these (the 9-screen wireframe set is P0-only); built to match the existing app's visual language instead:
- **FRG-301 weekly recalibration**: `WeeklyRecalibrationEngine` compares actual weight trend (from `bodyweightLogLb`) against the trend the goal's TDEE adjustment implies, and nudges the baseline calorie target to close the gap — damped and capped the same way Load Score's daily swing is. Needs 4+ weigh-ins across a 14-day window before it activates (otherwise a single noisy weigh-in could swing the target). Surfaced as its own line in the Target Explanation sheet.
- **FRG-304 Apple Health sync**: `HealthKitManager` reads steps and sleep (read-only, `com.apple.developer.healthkit` entitlement + `NSHealthShareUsageDescription`). Toggle in You; confirmed the entitlement doesn't break install/launch in Simulator. FRG-305 (the actual Load-Score sleep dampening) is a separate, still-unbuilt ticket — this only makes the data available.
- **FRG-306 logging reminders**: `ReminderManager` schedules local notifications (7pm workout / 8pm meal), cancelled the moment the user actually logs — no server/push infrastructure needed.
- **FRG-307 CSV export**: `CSVExporter` + `ShareLink`. Nutrition and per-exercise detail are limited to today — the in-memory store doesn't persist multi-day detail yet (that's what CloudKit persistence, FRG-130/131, will unlock); historical bodyweight and per-session volume load already export in full.

**CloudKit persistence (FRG-130/131)** — live and verified end-to-end against a real container, not just compiling:
- `CloudKitStore` (private database) persists profile+program, workout session history, bodyweight log, and today's food diary. `AppStore`'s `@Published` state is still the UI's only source of truth (no view code changed) — mutating methods update it immediately and fire a background CloudKit write.
- Closed two real gaps this uncovered: there was previously no UI path that ever logged a second bodyweight entry, and no "finish workout" action that ever archived a session into history — both fixed (`+ Log weight` in Progress, `Finish Workout` in Train), since CloudKit persistence would otherwise have had nothing real to sync.
- Returning users with a saved profile skip onboarding entirely (`RootView` checks CloudKit before deciding which screen to show) — confirmed live: profile save → app relaunch → onboarding skipped.
- Bundle ID is `com.epworthlabs.forge` (changed from `com.forge.app` — that iCloud container identifier was already taken globally, since Apple's iCloud namespace spans every developer, not just one team).
- Live-verified via real device signing (Team `88XVUU2829`) + a real iCloud account signed into Simulator: OAuth-style "no account" error → resolved after Simulator iCloud sign-in → profile fetch/save confirmed working via Simulator log capture (`CKFetchRecordsOperation` succeeding, zero errors). Still to verify once weight-logging/finish-workout are exercised more: the WorkoutSession/BodyweightEntry/FoodEntry record types need their `date` field marked Queryable (and Sortable for BodyweightEntry) in the CloudKit Dashboard's Development schema the first time those types get created by an actual save — CloudKit doesn't auto-index custom fields for query predicates.

**Ticket cleanup pass (2026-07-20)** — real gaps found by reading the actual code against backlog tickets, not by trusting stale "done" tags left over from before this session:
- **FRG-111 rest timer**: was a static Int set once and never decremented — not a real timer. Rebuilt on a stored end `Date` + `TimelineView`, so it's always correct even after backgrounding.
- **FRG-112 previous-session pre-fill**: `ExerciseSlot.lastPerformance` existed but nothing ever populated it. Now backfilled from training history on load/after finishing a workout, and actually displayed in Train ("Last time: …").
- **FRG-113 progressive-overload suggestions**: new `ProgressiveOverloadEngine` in ForgeCore — +5% (rounded to nearest 2.5kg plate) on hitting target reps at RPE ≤8, hold at higher RPE, −10% on missed reps. Surfaced as an Accept/Dismiss card in Train, never auto-applied.
- **FRG-221 PR history**: replaced a hardcoded "Back Squat: 225×5" placeholder in Progress with real per-exercise records from training history. Needed a foundational fix first — `SetLog` had no exercise identity at all (Load Score math never needed it), so historical sets couldn't be attributed to a specific lift.
- **FRG-222 weekly adherence**: "workouts completed" was already real; "target hit: 5/7 days" was hardcoded. Now reconstructs each of the last 7 days' Load Score from sessions strictly before that day and compares against that day's actual logged nutrition (approximates with today's profile, since historical profile snapshots aren't persisted).
- **FRG-206** clarified, not changed: the missed-session half is already covered by the existing math (zero volume on an unlogged day naturally pulls Load Score toward 0); "scheduled deload weeks" specifically is still open since it needs a real weekly program schedule that doesn't exist yet.

**Today screen skinned with "Liquid Glass"** — the design exploration's converged-on direction (frosted blur cards, indigo/teal accent, ring charts), applied to `TodayView` only per explicit scope (other screens still use the original look). Palette is an exact sRGB conversion of the design file's oklch tokens via the standard OKLab matrices, not eyeballed — SwiftUI on iOS 16 has no native oklch support. Verified live in Simulator, light and dark.

**Not started:** AI photo meal estimate (FRG-303, needs a vision-model decision first), sleep modifier activation (FRG-305, depends on FRG-304), custom program builder (FRG-104, only 3 fixed templates exist), offline logging + sync queue (FRG-114). See `../engineering-backlog.html`.

**Also needed before shipping, not before building:**
- Inter font files (Google Fonts, OFL license) aren't bundled yet — `ForgeType` falls back to the system font.
- Exercise demo images/GIFs aren't bundled — raise with design rather than pulling in an uncertain third-party asset set.
- The floating glassmorphic tab bar was simplified to a native `TabView` for now.
- `App/Config/Secrets.swift` is gitignored and currently holds a real, working USDA key. FatSecret is configured with a shared secret but no proxy URL yet (`fatSecretProxyBaseURL` is `nil`), so that source is silently skipped until `FoodProxy/` is deployed — see that folder's README. Copy `Secrets.example.swift` if `Secrets.swift` is ever missing.
- Barcode scanning (`BarcodeScannerView`) uses VisionKit's `DataScannerViewController`, which reports unsupported in Simulator (no camera) — that fallback path is what's actually verified here; the real scan needs a physical device.
