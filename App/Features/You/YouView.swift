import SwiftUI
import ForgeCore

struct YouView: View {
    @EnvironmentObject var store: AppStore
    @AppStorage("forceDarkMode") private var forceDarkMode = false

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
                            SettingsRow(title: "Logging reminders", tag: "P1")
                            Divider().overlay(ForgeColors.cardBorder)
                            SettingsRow(title: "Apple Health sync", tag: "P1")
                            Divider().overlay(ForgeColors.cardBorder)
                            SettingsRow(title: "Export data (CSV)", tag: "P1")
                        }
                    }
                }
                .padding(20)
                .padding(.bottom, 90)
            }
        }
        .preferredColorScheme(forceDarkMode ? .dark : nil)
    }
}

private struct SettingsRow: View {
    let title: String
    var tag: String?
    var body: some View {
        HStack {
            Text(title).font(ForgeType.body).foregroundStyle(ForgeColors.ink)
            if let tag {
                Text(tag).font(ForgeType.label).foregroundStyle(.black)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Color.yellow.opacity(0.7)).clipShape(RoundedRectangle(cornerRadius: 3))
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(ForgeColors.inkMuted).font(.caption)
        }
        .padding(.vertical, 9)
    }
}
