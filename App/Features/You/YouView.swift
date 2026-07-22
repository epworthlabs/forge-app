import SwiftUI
import UIKit
import ForgeCore

struct YouView: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject private var profileSettings = ProfileSettings.shared
    @AppStorage("forceDarkMode") private var forceDarkMode = false
    @AppStorage("remindersEnabled") private var remindersEnabled = false
    @AppStorage("healthSyncEnabled") private var healthSyncEnabled = false
    @State private var showingMethodology = false
    @State private var editingGoalTarget = false
    @State private var editingProfile = false
    @State private var isPreparingExport = false
    @State private var exportedFiles: [URL] = []
    @State private var showingExportSheet = false

    var body: some View {
        ZStack {
            ForgeColors.backgroundWash
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("You").font(ForgeType.displayLarge).foregroundStyle(ForgeColors.ink)

                    // Feature request — "give a default avatar and assign a randomly generated
                    // username at the top. Let users edit those two fields if they want."
                    Button { editingProfile = true } label: {
                        GlassCard {
                            HStack(spacing: 14) {
                                AvatarView(imageData: profileSettings.avatarImageData, size: 56)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(profileSettings.username).font(ForgeType.body).foregroundStyle(ForgeColors.ink)
                                    Text("\(store.profile.goal.displayLabel) · \(WeightUnit.roundedLb(fromKg: store.profile.weightKg)) lb")
                                        .font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                                }
                                Spacer()
                                Image(systemName: "pencil.circle.fill").font(.system(size: 22)).foregroundStyle(ForgeColors.inkMuted)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    GlassCard {
                        VStack(spacing: 0) {
                            Toggle(isOn: $forceDarkMode) {
                                Text("Dark Mode").font(ForgeType.body).foregroundStyle(ForgeColors.ink)
                            }
                            .tint(ForgeColors.accent)
                            .padding(.vertical, 13)
                            Divider().overlay(ForgeColors.cardBorder)

                            // Feature request — "this figure should not change unless these
                            // settings are changed in the app" implies somewhere in the app to
                            // change them; previously this row didn't do anything.
                            Button { editingGoalTarget = true } label: {
                                SettingsRow(title: "Goal & Target")
                            }
                            .buttonStyle(.plain)
                            Divider().overlay(ForgeColors.cardBorder)

                            Toggle(isOn: $remindersEnabled) {
                                Text("Logging reminders").font(ForgeType.body).foregroundStyle(ForgeColors.ink)
                            }
                            .tint(ForgeColors.accent)
                            .padding(.vertical, 13)
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
                            .padding(.vertical, 13)
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
                                .padding(.bottom, 8)
                            }
                            Divider().overlay(ForgeColors.cardBorder)

                            // Feature request — "documentation on the you tab explaining how
                            // everything is calculated."
                            Button { showingMethodology = true } label: {
                                SettingsRow(title: "How your numbers are calculated")
                            }
                            .buttonStyle(.plain)
                            Divider().overlay(ForgeColors.cardBorder)

                            // Feature request — "I want it to contain weight, workout and food log
                            // data" (full history, not just today) — nutrition now requires an
                            // async CloudKit fetch (see CSVExporter), so this is a Button that
                            // prepares the files first rather than a ShareLink handed a
                            // synchronously-computed array.
                            Button {
                                isPreparingExport = true
                                Task {
                                    exportedFiles = await CSVExporter.exportFiles(store: store)
                                    isPreparingExport = false
                                    showingExportSheet = true
                                }
                            } label: {
                                HStack {
                                    Text("Export data (CSV)").font(ForgeType.body).foregroundStyle(ForgeColors.ink)
                                    Spacer()
                                    if isPreparingExport {
                                        ProgressView()
                                    } else {
                                        Image(systemName: "square.and.arrow.up").foregroundStyle(ForgeColors.inkMuted).font(.body)
                                    }
                                }
                                .padding(.vertical, 13)
                            }
                            .buttonStyle(.plain)
                            .disabled(isPreparingExport)
                        }
                    }

                    // FRG-122/FRG-121 — attribution both food-database sources require as a
                    // condition of free-tier use, not decorative: FatSecret's terms require a
                    // "Powered by FatSecret" credit, and Open Food Facts data is ODbL-licensed
                    // (attribution required, same as a code license).
                    Text("Food data from USDA FoodData Central, Open Food Facts (ODbL), and FatSecret.")
                        .font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                        .padding(.top, 4)
                }
                .padding(20)
                .padding(.bottom, 90)
            }
        }
        .sheet(isPresented: $showingMethodology) { CalorieMethodologySheet() }
        .sheet(isPresented: $editingGoalTarget) { GoalTargetEditSheet() }
        .sheet(isPresented: $editingProfile) { ProfileEditSheet(currentWeightLb: WeightUnit.roundedLb(fromKg: store.profile.weightKg)) }
        .sheet(isPresented: $showingExportSheet) { ActivityShareSheet(items: exportedFiles) }
        .task {
            // Returning users with Health sync already on: refresh on each visit rather than
            // only right after the toggle flips.
            if healthSyncEnabled { await store.syncHealthKit() }
        }
    }
}

/// `ShareLink` needs its items known synchronously at view-body time; the CSV export now requires
/// an async CloudKit fetch first (full nutrition history, not just today), so this wraps the plain
/// UIKit share sheet instead, presented once the files are actually ready.
private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct SettingsRow: View {
    let title: String
    var body: some View {
        HStack {
            Text(title).font(ForgeType.body).foregroundStyle(ForgeColors.ink)
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(ForgeColors.inkMuted).font(.body)
        }
        .padding(.vertical, 13)
        .frame(minHeight: 44)
    }
}
