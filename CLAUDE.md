# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

**Keep this file current.** When a change alters the architecture described below (a new persistence
layer, a new cross-cutting store, a navigation restructure, a build/test workflow change), update the
relevant section in the same session — this doc goes stale fast otherwise, and the next session will
trust it over re-reading the code.

## Commands

```bash
# ForgeCore (pure Swift logic) — no Xcode needed
swift build
swift test                                  # all ForgeCore tests
swift test --filter FoodSearchServiceTests  # one test target/suite
swift test --filter usdaSearchScopesToGenericDataTypesOnly  # one test by name

# Full app — requires Xcode
xcodegen generate   # regenerate Forge.xcodeproj after adding/removing App/ files — see gotcha below
xcodebuild -project Forge.xcodeproj -scheme Forge -destination 'generic/platform=iOS Simulator' build
```

**xcodegen is not installed on this machine and isn't reliably available via Homebrew here.** If a
file gets added under `App/` and there's no way to run `xcodegen generate`, the new file must be
registered in `Forge.xcodeproj/project.pbxproj` by hand (`PBXBuildFile` + `PBXFileReference` entries,
added to the right `PBXGroup`'s children, added to `PBXSourcesBuildPhase`'s `files`) — `xcodebuild`
will otherwise silently not compile it. `Forge.xcodeproj` is gitignored; `project.yml` is the
source-of-truth spec xcodegen reads, but editing `project.yml` alone does **not** update the already-
generated `.pbxproj` without actually running xcodegen — for build-setting changes (e.g. a version
bump) both files need the edit. `Sources/ForgeCore/**` has no such problem — it's a plain SwiftPM
target, so `swift build`/`swift test` pick up new files automatically.

Archiving/uploading a release build: `xcodebuild archive` (Release config, `generic/platform=iOS`)
then `xcodebuild -exportArchive` with `build/ExportOptions.plist` (method `app-store-connect`,
`destination: upload` — export and upload happen in one step). Bump `CURRENT_PROJECT_VERSION` in both
`project.yml` and the `.pbxproj` before a re-upload; App Store Connect rejects a repeated build number.
`Info.plist`'s `CFBundleVersion`/`CFBundleShortVersionString` are `$(CURRENT_PROJECT_VERSION)`/
`$(MARKETING_VERSION)` — don't hardcode them back to literals.

## Architecture

### Two targets, one repo

- **`Sources/ForgeCore`** — a plain SwiftPM library: TDEE/macro math, Load Score, progressive
  overload, the exercise library, the food-database clients. Zero UIKit/SwiftUI. If it can be
  expressed as pure logic, it belongs here, not in `App/`, so it stays testable with just `swift test`.
- **`App/`** — the SwiftUI app (Xcode-only). `App/Store/` holds the app-layer models/persistence that
  depend on Foundation+CloudKit+UIKit but aren't pure enough for ForgeCore (`AppStore`, `Recipe`,
  `FoodEntry`, `ProgramTemplate` all live here, not in ForgeCore, precisely because of that
  CloudKit/UIKit dependency).

`AppStore` (`App/Store/AppStore.swift`) is the single `@MainActor` `ObservableObject` every view reads
via `@EnvironmentObject` — mutating methods update `@Published` state immediately and fire off
persistence in the background; no view ever awaits a network round-trip to see its own change.

### Persistence: three tiers, and why each exists

This has been rewritten from scratch once already (FRG-383) after a real, hard-learned bug: every
CloudKit history *read* went through `CKQuery`, which requires per-field indexes configured manually
in the CloudKit Dashboard — never done, so every fetch silently threw, every `try?` swallowed it, and
the app started from nothing on every cold launch, while *saves* kept succeeding (schema
auto-creates). Data was reaching the server and then becoming unreachable. Don't reintroduce
`CKQuery`/`NSPredicate` for anything that needs to be reliably read back — the fix removes queries
entirely:

1. **`CloudKitStore`** (`App/Store/CloudKitStore.swift`) — every domain is one fixed-ID record holding
   that domain's *entire* state as a JSON blob, fetched directly by ID (`database.record(for:)` /
   `records(for:)`), which needs zero Dashboard configuration. Sessions chunk by calendar year (1MB
   record cap), food chunks by day, bodyweight/recipes/profile are single records. A "delete" is just
   the next whole-state save without the deleted item — there's no per-entry delete path.
2. **`SyncQueue`** (`App/Store/SyncQueue.swift`) — an offline-safe write queue matching that
   whole-blob shape: each `PendingWrite` case carries a domain's *entire current state*, not a single
   entry, so two queued writes of the same kind coalesce into one (`coalesceIntoPending`). Wraps every
   write in `beginBackgroundTask`/`endBackgroundTask` — without it, a write fired right as the user
   backgrounds the app (the exact moment after tapping "Finish Workout") can get killed mid-flight
   before it either succeeds or lands in the retry queue.
3. **`LocalHistoryStore`** / **`WorkoutDraftStore`** (`App/Store/`) — a device-local mirror, loaded
   synchronously in `AppStore.init` before any network call. A day rollover is, in practice, a cold
   relaunch (the app reopens the next morning) — this is what makes yesterday's sessions/weigh-ins
   appear on screen from the first frame instead of depending on a CloudKit fetch completing first.
   `WorkoutDraftStore` separately persists *in-progress* (checked-off-but-not-yet-Finished) sets on
   every `todaysExercises` change, so a relaunch mid-workout restores exactly where you left off, and
   a day boundary crossed with unsaved progress gets auto-archived as a session (`archiveCompletedSession`)
   rather than silently discarded — see `resumeOrArchiveDraftIfNeeded` and `refreshForNewDayIfNeeded`.

Every CloudKit fetch **merges** (union by id/timestamp) into whatever's already in memory rather than
replacing it — a fetch can never wipe out something logged moments ago that hasn't round-tripped yet.

`CustomExerciseStore`/`CustomFoodStore` used to be the one exception that stayed device-local only
(Application Support, never synced) — a deliberate call for "don't make it publicly shared, we don't
know how reliable their inputs are." Bug fix — "when I reinstall the app, it doesn't remember my
custom workouts or my food": Application Support is wiped along with the rest of the app's local
container on uninstall, same root cause FRG-383 already fixed for recipes/sessions/bodyweight. Both
now sync through `SyncQueue`/`CloudKitStore` exactly like `RecipeStore` (whole-list replace on save,
merge-on-load for the fresh-install direction) — CloudKit's private database is still never shared
with other users or exposed publicly, so this doesn't reopen that concern, it just also means a
reinstall (or another of the user's own signed-in devices) recovers the data too.

### Program/week model

`ProgramTemplate` (`App/Store/Program.swift`) is `weekCount` (editable timeframe) + `defaultDays`
(what every week uses) + a sparse `weekOverrides: [Int: [ProgramDay]]` dictionary (only weeks that
genuinely differ from the default) — not a full `[ProgramWeek]` array, so a program that repeats the
same split every week doesn't store N duplicate copies.

Two distinct "week" concepts, easy to conflate: `currentProgramWeek` is purely calendar-based
(elapsed days since `programStartDate` ÷ 7) and drives scheduled-deload timing; `activeWeek` is
whichever week `todaysExercises` currently reflects, which can lead the calendar if the user finishes
a week's workouts faster than 7 days (`AppStore.suggestedSession()` walks forward from
`currentProgramWeek` to the next week with an uncompleted day — it deliberately does not just look
within the current calendar week and fall back to day 0, which used to re-suggest an already-completed
workout).

Day rotation is session-driven, not calendar-driven — there's no "Push is always Monday" concept;
`currentProgramDayIndex` advances on Finish Workout via `suggestedSession()`, matching how most
non-calendar-locked splits (PPL, Upper/Lower) actually get run.

Editing has two distinct, deliberately separate scopes: swap/add/remove/reorder exercises in
`TrainSessionView` are session-only (never touch `program`) unless the user explicitly confirms
"apply to future weeks" (`applyTodaysChangesToFutureWeeks`); the program editor
(`App/Features/Onboarding/ProgramEditorView.swift` — used from both onboarding and Train's "Edit
Program") is the durable path. Both now expose the same "Swap Exercise" action from each exercise
row's `···` menu (`ExerciseRowEditor.onSwap` here, `ExerciseCard`'s menu in `TrainView.swift`) — the
durable side just overwrites `exerciseName` in place via `ExercisePickerSheet`, no logged-set/
last-performance state to carry over like the session-side `AppStore.swapExercise` handles.

### Food data: four sources merged in one place

`FoodSearchService.search` (`Sources/ForgeCore/FoodDatabase/FoodSearchService.swift`) is the only
place these combine: `CuratedFoodLibrary` (bundled `Resources/foods.json`, hand-maintained — this is
"the developer's own food database," extended by editing that JSON file directly, same workflow as
`exercises.json`) + `CustomFoodStore`/`RecipeStore` (per-device, App-layer, passed in by the caller,
not ForgeCore) + three live APIs (FatSecret via `FoodProxy/`, Open Food Facts, USDA FDC). Merge/dedup
priority (first copy of a name+brand wins): curated → FatSecret → Open Food Facts → USDA. Results are
then **re-ranked** separately from that merge order (unbranded/generic results and exact name matches
rank above branded ones unless the query itself names the brand) — don't conflate the two; changing
merge order changes *which copy* of a duplicate wins, changing rank score changes *display order*.

Every source-parsing path filters `kcal <= 0` — found via a real bug (a USDA/OFF record with
protein/fat listed but no energy value defaulted to `0 kcal` via `?? 0` instead of being excluded,
producing phantom zero-calorie foods like "Kiwi"). If you add a new food source, apply the same guard.

`FoodProxy/` (Node/Express, deployed separately on Render) exists only because FatSecret's API
requires a fixed allowlisted IP and server-held credentials a mobile app can't hold directly — it's
not part of the Xcode project and has its own README.

### Train navigation

`ProgramSelectionView` → `DaySelectionView` → `TrainSessionView` (the actual set-logging screen) →
`WorkoutCompleteView` (full-screen cover after Finish Workout) → back to `DaySelectionView`. Exercise
reordering (drag-and-drop, `.draggable`/`.dropDestination`) exists in both `TrainSessionView`
(session-only) and `ProgramEditorView` (durable) with near-identical logic in each — a shared
`AppStore.moveExercise(id:near:)`/`moveExerciseToTop`/`moveExerciseToBottom` for the session case,
a local equivalent in `ProgramEditorView` for the durable case, since the latter mutates a `@Binding`
array with no `AppStore` involved at all.

One gesture gotcha worth remembering: a `simultaneousGesture(DragGesture(minimumDistance: 0))` placed
on the same view as `.draggable(...)` (tried once, to fire a haptic on touch-down) competes with
`.draggable`'s own touch recognition and can silently prevent the drag from ever starting. The
working fix for "do something exactly when a drag begins" is firing it from the `.draggable(_:preview:)`
closure's `onAppear` instead — that closure is only ever evaluated when a drag session actually starts,
so there's nothing to compete with.

### Design system

`App/DesignSystem/`: `ForgeColors` (exact sRGB conversions of the "Liquid Glass" moodboard's oklch
tokens — SwiftUI on iOS 16 has no native oklch), `ForgeType` (Inter font, bundled as 5 static-weight
`.ttf` files registered in `Info.plist`'s `UIAppFonts` — matching PostScript names `Inter-Regular`
etc., pulled out of Inter's official `.ttc` release since recent Inter releases only ship a variable
font or a multi-face collection, not standalone per-weight files), `LiquidComponents` (`GlassCard`,
`LiquidPrimaryButtonStyle`/`LiquidChipButtonStyle` — every primary CTA and secondary action chip in
the app uses one of these two `ButtonStyle`s rather than one-off `.background(ForgeColors.accent)`
calls), `SelectAllTextField` (a `UIViewRepresentable`-wrapped `UITextField` — plain SwiftUI `TextField`
has no text-selection API pre-iOS 17, so double-tap-to-select-all needs to drop to UIKit).

### Profile reset

`AppStore.resetProfile()` (feature request — "reset their profile which basically gives them a fresh
profile," v2-clarified to mean wiping Train/Eat/Progress data *in place*, not signing the user back
out to onboarding) resets workout history, bodyweight log, and food log while leaving `profile`/
`program`/goals untouched — `currentProgramDayIndex`/`programStartDate`/`activeWeek` reset to week 1,
day 0 so program progress restarts too. Confirmed via a centered `.alert` in `YouView` (not
`.confirmationDialog` — a v2 fix, "window not a bubble").

Deletion spans all three persistence tiers, in order: `CloudKitStore.deleteHistoryKeepingProfile()`
(deletes the bodyweight record, the last 10 years of `workoutSessions-{year}` records, and food-day
records for a deterministic trailing 365-day window — the same client-computed day-key window
`CSVExporter` already uses for "full history," since CloudKit's whole-blob design has no way to
enumerate which food-day records actually exist without reintroducing `CKQuery`; batched via
`modifyRecords` rather than one `deleteRecord` await per day, `atomically: false` so a missing day
doesn't fail the batch — an earlier version of this only deleted *today's* food day, which is why
"stats for this week" under Progress kept showing stale numbers after a reset), `SyncQueue.clearPending()`
(so a write queued before the reset can't resurrect deleted data once it flushes), then
`LocalHistoryStore.clear()` / `WorkoutDraftStore.clear()` (device-local mirrors) — followed by
re-saving the profile (with reset progress fields), an empty bodyweight log, an empty today's food
day, and an empty workout-session list, so CloudKit and local state agree immediately rather than
waiting on the next natural save. Deliberately does **not** touch
`CustomExerciseStore`/`CustomFoodStore`/`RecipeStore` — those are per-device library content the user
built up, not profile/history data, same distinction as elsewhere in this doc.

### Rest timer Live Activity (second Xcode target)

Feature request — "rest timer as an app notification... shows the timer on the lock screen." This
is the one place in the app with **two Xcode targets**: `Forge` (the app) and
`RestTimerWidgetExtension` (a widget extension, `RestTimerWidget/`), because ActivityKit requires a
Live Activity's UI to be declared in a widget extension — the app process can start/update/end the
Activity, but can't render it, since the Lock Screen/Dynamic Island presentation has to keep working
while the app itself is suspended.

- `App/Store/RestTimerAttributes.swift` — the shared `ActivityAttributes` type. Lives under `App/`
  (compiled automatically into the `Forge` target via its `App` source path) but is *also* added
  explicitly to `RestTimerWidgetExtension`'s sources in `project.yml`/`project.pbxproj` — ActivityKit
  requires the exact same attributes type compiled into both targets, so this one file is a member
  of both.
- `App/Store/RestTimerActivityManager.swift` (`Forge` target only) — starts/ends the Activity from
  `AppStore.restEndDate`'s `didSet`, right alongside the existing `ReminderManager` one-shot
  notification call, and from `archiveCompletedSession` when a workout finishes. Uses the
  `ActivityContent`-based request/end APIs (support `staleDate`), which is why the deployment target
  is 16.2, not just 16.1 (the Live Activity type itself only needs 16.1).
- `RestTimerWidget/RestTimerWidgetLiveActivity.swift` (`RestTimerWidgetExtension` target only) — the
  Lock Screen + Dynamic Island SwiftUI, plus the extension's `@main` `WidgetBundle`. Uses
  `Text(timerInterval:countsDown:)` so the countdown ticks on its own with zero polling from either
  process; guards against the now-invalid range once `endDate` has passed (the Activity isn't torn
  down the instant rest hits zero, only when the next set starts or the workout ends).

**xcodegen gotcha, extended**: adding this whole target was done by hand-editing `project.pbxproj`
(new `PBXNativeTarget`, `PBXCopyFilesBuildPhase` to embed the `.appex`, `PBXTargetDependency`/
`PBXContainerItemProxy` so `Forge` builds the extension first, plus configs) since xcodegen isn't
installed — far riskier than the usual single-file gotcha this doc already covers, so `project.yml`
was kept in sync as the authoritative spec for whenever `xcodegen generate` becomes available again,
even though it wasn't actually run. Verify any future hand-edit here with `plutil -lint
Forge.xcodeproj/project.pbxproj` after every change (catches structural corruption immediately) and
a real `xcodebuild -project Forge.xcodeproj -scheme Forge -destination 'generic/platform=iOS
Simulator' build` before trusting it.

### Auth gate

Sign in with Apple (`AppleSignInManager`, gates `RootView`) is the only auth — deliberate, not a
placeholder for more later without a real rearchitecture: all data lives in CloudKit's *private*
database, already scoped to whichever Apple ID the device is signed into. Google/email sign-in would
each need an entirely separate backend, since CloudKit has no non-Apple identity concept.
