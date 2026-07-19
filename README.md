# Forge (working title)

Structured strength programming + training-load-adaptive nutrition. See `../prd.html`, `../engineering-backlog.html`, and `../Wireframes/` for product context.

## Structure

- `Sources/ForgeCore` — pure Swift business logic (Load Score, TDEE, macro/calorie engine). No UIKit/SwiftUI dependency, builds and tests with just the Swift toolchain — no Xcode required.
- `Tests/ForgeCoreTests` — Swift Testing (`import Testing`) coverage for the engine above.
- `App/` — the SwiftUI iOS app. Requires Xcode to build.
- `project.yml` — [XcodeGen](https://github.com/yonaskolb/XcodeGen) spec. The `.xcodeproj` is generated, not committed — regenerate after adding files.

## Getting started

Xcode is installed on this machine. XcodeGen isn't available via Homebrew here (Homebrew itself isn't installed), so it was built from source once — if you need to regenerate the project after adding files and don't have `xcodegen` on PATH, either `brew install xcodegen` or build it yourself:

```
git clone --depth 1 https://github.com/yonaskolb/XcodeGen.git /tmp/XcodeGen
cd /tmp/XcodeGen && swift build -c release --product xcodegen
```

Then from this folder: `xcodegen generate`, open `Forge.xcodeproj`, select a simulator, and run.

To run just the engine tests: `swift test`.

## Status (2026-07-19)

**Done and verified — both compiled and run in Simulator (iPhone 17), not just compile-checked:**
- `ForgeCore` — Load Score, TDEE/macro calculation, RED-S floor guardrail, carb-band selection, exercise library (`free-exercise-db`, 873 exercises). 14 tests passing (`swift test`).
- Onboarding (4 steps), Today (target card, Load Score/kcal rings, macros, workout card), Target Explanation sheet, Train (per-exercise sets with RPE picker), Eat (diary + manual food search, no barcode per the P1 decision), Progress (bodyweight trend, weekly adherence, PRs), You (profile, dark mode, settings). Both light and dark mode confirmed.

**Three real bugs found by actually running it, not by reading the code — worth knowing before trusting anything here blind:**
1. **RED-S floor over-elevated ordinary targets.** The floor folded general daily activity into "exercise expenditure," pushing it above baseline for anyone above sedentary. Fixed to 30×FFM alone; see PRD Appendix step 3.
2. **Macros didn't sum to the stated calorie total.** Protein (cut-level g/kg) plus the full researched carb band could exceed the total target before fat was even added — a 1,951 kcal target showing macros that implied ~3,100 kcal. Carbs now compress to fit the budget; protein and the fat floor never move. See PRD Appendix step 4.
3. **Every exercise's sets showed the same seed weight** (100 kg) regardless of which exercise — `AppStore.init` computed a per-exercise target weight but didn't pass it into the seeded sets. Fixed.

Plus one polish fix: a bodyweight chart with a single data point (day one, right after onboarding) rendered as an invisible axis with no line to draw — added an explicit "log a couple more weigh-ins" empty state instead.

**Not started:** CloudKit persistence (FRG-130/131 — screens currently run on in-memory `AppStore`, swapping the storage shouldn't require view changes), food database integrations (USDA/Open Food Facts/FatSecret — Food Search uses a 5-item mock list), PostHog instrumentation. See `../engineering-backlog.html`.

**Also needed before shipping, not before building:**
- Inter font files (Google Fonts, OFL license) aren't bundled yet — `ForgeType` falls back to the system font until they're added and registered in `Info.plist`.
- Exercise demo images/GIFs aren't bundled — `free-exercise-db`'s `images` field is just relative paths; the actual image files live in a separate, much larger part of the upstream repo. Worth raising with design rather than pulling in an uncertain third-party asset set.
- The floating glassmorphic tab bar from the hi-fi prototype was simplified to a native `TabView` for now — functionally equivalent, visually plainer.
