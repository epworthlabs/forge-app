import SwiftUI
import ForgeCore

struct YouView: View {
    @EnvironmentObject var store: AppStore
    @AppStorage("forceDarkMode") private var forceDarkMode = false
    @AppStorage("remindersEnabled") private var remindersEnabled = false
    @AppStorage("healthSyncEnabled") private var healthSyncEnabled = false

    var body: some View {
        ZStack {
            ForgeColors.backgroundBase.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("You").font(ForgeType.displayLarge).foregroundStyle(ForgeColors.ink)

                    GlassCard {
                        HStack(spacing: 14) {
                            Circle().fill(ForgeColors.accent).frame(width: 52, height: 52)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Alex Rivera").font(ForgeType.body).foregroundStyle(ForgeColors.ink)
                                Text("\(store.profile.goal.displayLabel) · \(Int(store.profile.weightKg)) kg")
                                    .font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                            }
                        }
                    }

                    GlassCard {
                        VStack(spacing: 0) {
                            Toggle(isOn: $forceDarkMode) {
                                Text("Dark Mode").font(ForgeType.body).foregroundStyle(ForgeColors.ink)
                            }
                            .tint(ForgeColors.accent)
                            .padding(.vertical, 9)
                            Divider().overlay(ForgeColors.cardBorder)

                            SettingsRow(title: "Edit Preferences")
                            Divider().overlay(ForgeColors.cardBorder)

                            Toggle(isOn: $remindersEnabled) {
                                Text("Logging reminders").font(ForgeType.body).foregroundStyle(ForgeColors.ink)
                            }
                            .tint(ForgeColors.accent)
                            .padding(.vertical, 9)
                            .onChange(of: remindersEnabled) { enabled in
                                if enabled {
                                    Task {
                                        let granted = await ReminderManager.shared.requestAuthorizationIfNeeded()
                                        if granted { store.refreshReminders() } else { remindersEnabled = false }
                                    }
                                } else {
                                    ReminderManager.shared.cancelAll()
                                }
                            }
                            Divider().overlay(ForgeColors.cardBorder)
                            Toggle(isOn: $healthSyncEnabled) {
                                Text("Apple Health sync").font(ForgeType.body).foregroundStyle(ForgeColors.ink)
                            }
                            .tint(ForgeColors.accent)
                            .padding(.vertical, 9)
                            .onChange(of: healthSyncEnabled) { enabled in
                                guard enabled else { return }
                                Task {
                                    let granted = await HealthKitManager.shared.requestAuthorization()
                                    if granted { await store.syncHealthKit() } else { healthSyncEnabled = false }
                                }
                            }
                            if healthSyncEnabled, store.stepsToday != nil || store.lastNightSleepHours != nil {
                                HStack(spacing: 14) {
                                    if let steps = store.stepsToday {
                                        Text("\(steps) steps today").font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                                    }
                                    if let sleep = store.lastNightSleepHours {
                                        Text(String(format: "%.1fh sleep", sleep)).font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                                    }
                                }
                                .padding(.bottom, 6)
                            }
                            Divider().overlay(ForgeColors.cardBorder)

                            ShareLink(items: CSVExporter.exportFiles(store: store)) {
                                HStack {
                                    Text("Export data (CSV)").font(ForgeType.body).foregroundStyle(ForgeColors.ink)
                                    Spacer()
                                    Image(systemName: "square.and.arrow.up").foregroundStyle(ForgeColors.inkMuted).font(.caption)
                                }
                                .padding(.vertical, 9)
                            }
                        }
                    }
                }
                .padding(20)
                .padding(.bottom, 90)
            }
        }
        .preferredColorScheme(forceDarkMode ? .dark : nil)
        .task {
            // Returning users with Health sync already on: refresh on each visit rather than
            // only right after the toggle flips.
            if healthSyncEnabled { await store.syncHealthKit() }
        }
    }
}

private struct SettingsRow: View {
    let title: String
    var body: some View {
        HStack {
            Text(title).font(ForgeType.body).foregroundStyle(ForgeColors.ink)
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(ForgeColors.inkMuted).font(.caption)
        }
        .padding(.vertical, 9)
    }
}
