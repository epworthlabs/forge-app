import Foundation

/// Feature request — "when users export data (CSV), i want it to contain weight, workout and food
/// log data." Previously honest-but-limited to what the in-memory store held: nutrition was
/// today-only (`mealEntries` isn't day-scoped), and past workouts exported as session-aggregate
/// only (no per-set detail), even though `WorkoutSession.sets` has always carried it. Now: workouts
/// export full per-set detail for every session (not just today's in-progress one), nutrition
/// pulls full history from CloudKit (merged with today's live in-memory state, which wins for
/// anything not yet round-tripped through sync), and bodyweight is unchanged — it was already
/// full history.
@MainActor
enum CSVExporter {
    private static let isoDate: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter
    }()

    static func exportFiles(store: AppStore) async -> [URL] {
        let nutrition = await nutritionCSV(store: store)
        return [
            write(filename: "forge-workouts.csv", contents: workoutsCSV(store: store)),
            write(filename: "forge-nutrition.csv", contents: nutrition),
            write(filename: "forge-bodyweight.csv", contents: bodyweightCSV(store: store)),
        ].compactMap { $0 }
    }

    private static func workoutsCSV(store: AppStore) -> String {
        var rows = ["date,exercise,set,weight_kg,reps,rpe"]
        // Today's in-progress sets, if Finish Workout hasn't been tapped yet — not yet part of
        // trailingSessions, so it'd otherwise be missing entirely until the session is finished.
        let today = isoDate.string(from: Date())
        for slot in store.todaysExercises {
            for (i, set) in slot.sets.enumerated() where set.done {
                rows.append("\(today),\(csvEscape(slot.exercise.name)),\(i + 1),\(set.weightKg),\(set.reps),\(set.rpe.map { String($0) } ?? "")")
            }
        }
        // Every completed session's actual per-set detail — `WorkoutSession.sets` has always
        // carried exerciseName/weight/reps/rpe per set; the old export only used the aggregate
        // `volumeLoad` for past sessions despite the detail already being right there.
        for session in store.trailingSessions {
            let date = isoDate.string(from: session.date)
            for (i, set) in session.sets.enumerated() {
                rows.append("\(date),\(csvEscape(set.exerciseName)),\(i + 1),\(set.weightKg),\(set.reps),\(set.rpe.map { String($0) } ?? "")")
            }
        }
        return rows.joined(separator: "\n")
    }

    private static func nutritionCSV(store: AppStore) async -> String {
        var rows = ["date,meal,food,kcal,protein_g,carb_g,fat_g"]
        let end = Date()
        let start = Calendar.current.date(byAdding: .year, value: -5, to: end) ?? Date.distantPast
        var byID: [FoodEntry.ID: (meal: Meal, entry: FoodEntry)] = [:]
        if let historical = try? await CloudKitStore.shared.fetchFoodEntries(from: start, to: end) {
            for meal in Meal.allCases {
                for entry in historical[meal] ?? [] { byID[entry.id] = (meal, entry) }
            }
        }
        // Today's live in-memory state wins over the CloudKit snapshot above — authoritative for
        // anything logged moments ago (or fully offline) that hasn't round-tripped through sync yet.
        for meal in Meal.allCases {
            for entry in store.mealEntries[meal] ?? [] { byID[entry.id] = (meal, entry) }
        }
        for (meal, entry) in byID.values.sorted(by: { $0.entry.date < $1.entry.date }) {
            rows.append("\(isoDate.string(from: entry.date)),\(meal.rawValue),\(csvEscape(entry.name)),\(entry.kcal),\(entry.proteinG),\(entry.carbG),\(entry.fatG)")
        }
        return rows.joined(separator: "\n")
    }

    private static func bodyweightCSV(store: AppStore) -> String {
        var rows = ["date,weight_lb"]
        for entry in store.bodyweightLogLb {
            rows.append("\(isoDate.string(from: entry.date)),\(entry.weightLb)")
        }
        return rows.joined(separator: "\n")
    }

    private static func csvEscape(_ value: String) -> String {
        value.contains(",") || value.contains("\"") ? "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\"" : value
    }

    private static func write(filename: String, contents: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try contents.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}
