import SwiftUI
import UIKit
import CloudKit
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
    // Feature request — "users should have the option to reset their profile which basically gives
    // them a fresh profile."
    @State private var showingResetConfirmation = false
    @State private var isResettingProfile = false
    // App Store Guideline 5.1.1(v) — "apps that support account creation must also offer the
    // ability to initiate deletion of their account from within the app." `AppleSignInManager
    // .signOut()` already existed but was never wired to any button; there was also no way to
    // delete the account (data + sign-in) at all — only "Reset Profile," which explicitly keeps
    // the profile/account. See `AppStore.deleteAccount`.
    @State private var showingSignOutConfirmation = false
    @State private var showingDeleteAccountConfirmation = false
    @State private var isDeletingAccount = false
    // Bug fix — same investigation as the iCloud-account banner below: an available account
    // doesn't guarantee writes are actually reaching CloudKit (a container/entitlement problem
    // would still fail every write while reporting `.available`). A growing, never-shrinking
    // pending count is the visible symptom of that — checked once per visit since `SyncQueue`
    // has no other way to push updates out.
    @State private var pendingSyncCount = 0

    var body: some View {
        ZStack {
            ForgeColors.backgroundWash
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("You").font(ForgeType.displayLarge).tracking(-0.6).liquidHeadingStyle()

                    // Bug fix — "the workouts/weight/recipes I logged are gone after a day rolls
                    // over or I reinstall." The single most common reason CloudKit silently does
                    // nothing is no iCloud account signed in (or a restricted one) — previously
                    // invisible, since nothing checked or surfaced it, so data just vanished with
                    // no explanation. This is that explanation, whenever it applies.
                    if store.cloudKitAccountStatus != .available && store.cloudKitAccountStatus != .couldNotDetermine {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "exclamationmark.icloud.fill")
                                .foregroundStyle(ForgeColors.accent).font(.system(size: 18))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("iCloud sync isn't available").font(ForgeType.body).foregroundStyle(ForgeColors.ink)
                                Text(cloudKitStatusMessage).font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                            }
                        }
                        .padding(14)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(ForgeColors.accent.opacity(0.4)))
                    } else if pendingSyncCount > 0 {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "exclamationmark.icloud.fill")
                                .foregroundStyle(ForgeColors.accent).font(.system(size: 18))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(pendingSyncCount) change\(pendingSyncCount == 1 ? "" : "s") not yet synced").font(ForgeType.body).foregroundStyle(ForgeColors.ink)
                                Text("iCloud looks available, but some saves are stuck retrying — check your connection.").font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                            }
                        }
                        .padding(14)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(ForgeColors.accent.opacity(0.4)))
                    }

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

                    // Feature request — "users should have the option to reset their profile which
                    // basically gives them a fresh profile." Separate card, isolated from the
                    // settings above, since this is destructive and irreversible rather than a
                    // preference toggle.
                    GlassCard {
                        Button {
                            showingResetConfirmation = true
                        } label: {
                            HStack {
                                Text("Reset Profile").font(ForgeType.body).foregroundStyle(.red)
                                Spacer()
                                if isResettingProfile {
                                    ProgressView()
                                } else {
                                    Image(systemName: "trash").foregroundStyle(.red).font(.body)
                                }
                            }
                            .padding(.vertical, 13)
                        }
                        .buttonStyle(.plain)
                        .disabled(isResettingProfile)
                    }

                    // App Store Guideline 5.1.1(v) — sign-out and full account deletion. Grouped
                    // together, separate from Reset Profile above (that keeps the account; these
                    // two act on the account itself).
                    GlassCard {
                        VStack(spacing: 0) {
                            Button {
                                showingSignOutConfirmation = true
                            } label: {
                                HStack {
                                    Text("Sign Out").font(ForgeType.body).foregroundStyle(ForgeColors.ink)
                                    Spacer()
                                    Image(systemName: "rectangle.portrait.and.arrow.right").foregroundStyle(ForgeColors.inkMuted).font(.body)
                                }
                                .padding(.vertical, 13)
                            }
                            .buttonStyle(.plain)

                            Divider().overlay(ForgeColors.cardBorder)

                            Button {
                                showingDeleteAccountConfirmation = true
                            } label: {
                                HStack {
                                    Text("Delete Account").font(ForgeType.body).foregroundStyle(.red)
                                    Spacer()
                                    if isDeletingAccount {
                                        ProgressView()
                                    } else {
                                        Image(systemName: "trash").foregroundStyle(.red).font(.body)
                                    }
                                }
                                .padding(.vertical, 13)
                            }
                            .buttonStyle(.plain)
                            .disabled(isDeletingAccount)
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
        // V2 feedback — "I want the disclaimer to be a window not a bubble that pops out."
        // `.alert` renders as a centered modal, unlike `.confirmationDialog`'s bottom action sheet.
        .alert("Reset your profile?", isPresented: $showingResetConfirmation) {
            Button("Reset Profile", role: .destructive) {
                isResettingProfile = true
                Task {
                    await store.resetProfile()
                    isResettingProfile = false
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            // V2 feedback — "don't bring the user back to on-boarding, just wipe the current data
            // in Train, Eat and Progress." Profile/program/goals stay put; only history resets.
            Text("This permanently deletes your training history, bodyweight log, and today's food log, and resets your program progress back to week 1, day 1. Your profile, goals, custom foods, exercises, and recipes are kept. This can't be undone.")
        }
        .alert("Sign out?", isPresented: $showingSignOutConfirmation) {
            Button("Sign Out", role: .destructive) { AppleSignInManager.shared.signOut() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can sign back in with the same Apple ID any time — nothing is deleted.")
        }
        .alert("Delete your account?", isPresented: $showingDeleteAccountConfirmation) {
            Button("Delete Account", role: .destructive) {
                isDeletingAccount = true
                Task {
                    await store.deleteAccount()
                    isDeletingAccount = false
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your profile, training history, food log, recipes, and custom exercises/foods, and signs you out. This can't be undone.")
        }
        .task {
            // Returning users with Health sync already on: refresh on each visit rather than
            // only right after the toggle flips.
            if healthSyncEnabled { await store.syncHealthKit() }
            pendingSyncCount = await SyncQueue.shared.pendingCount
        }
    }

    private var cloudKitStatusMessage: String {
        switch store.cloudKitAccountStatus {
        case .noAccount:
            return "Sign in to iCloud in Settings so your data syncs and survives a reinstall."
        case .restricted:
            return "iCloud is restricted on this device (e.g. by Screen Time or a managed profile)."
        case .temporarilyUnavailable:
            return "iCloud is temporarily unavailable — this usually resolves on its own."
        default:
            return "Your data is only stored on this device until iCloud is available."
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
