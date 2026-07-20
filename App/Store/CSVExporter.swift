import Foundation

/// FRG-307 — exports what actually exists in the in-memory store today. `trailingSessions` only
/// carries aggregate volume load per session (that's all Load Score needs), not a per-exercise
/// breakdown, so historical workouts export as one row per session rather than one row per set —
/// today's session is the only one with exercise-level detail, since `todaysExercises` is the only
/// place that detail is tracked. Nutrition history is limited to today for the same reason
/// `mealEntries` isn't day-scoped yet — both are honest reflections of the current in-memory data
/// model (CloudKit persistence, FRG-130/131, is what will make multi-day detail possible).
@MainActor
enum CSVExporter {
    private static let isoDate: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter
    }()

    static func exportFiles(store: AppStore) -> [URL] {
        [
            write(filename: "forge-workouts.csv", contents: workoutsCSV(store: store)),
            write(filename: "forge-nutrition.csv", contents: nutritionCSV(store: store)),
            write(filename: "forge-bodyweight.csv", contents: bodyweightCSV(store: store)),
        ].compactMap { $0 }
    }

    private static func workoutsCSV(store: AppStore) -> String {
        var rows = ["date,exercise,set,weight_kg,reps,rpe"]
        let today = isoDate.string(from: Date())
        for slot in store.todaysExercises {
            for (i, set) in slot.sets.enumerated() where set.done {
                rows.append("\(today),\(csvEscape(slot.exercise.name)),\(i + 1),\(set.weightKg),\(set.reps),\(set.rpe.map { String($0) } ?? "")")
            }
        }
        for session in store.trailingSessions {
            rows.append("\(isoDate.string(from: session.date)),session summary (no per-exercise detail),,,,\(Int(session.volumeLoad)) volume load")
        }
        return rows.joined(separator: "\n")
    }

    private static func nutritionCSV(store: AppStore) -> String {
        var rows = ["date,meal,food,kcal,protein_g,carb_g,fat_g"]
        let today = isoDate.string(from: Date())
        for meal in Meal.allCases {
            for entry in store.mealEntries[meal] ?? [] {
                rows.append("\(today),\(meal.rawValue),\(csvEscape(entry.name)),\(entry.kcal),\(entry.proteinG),\(entry.carbG),\(entry.fatG)")
            }
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
