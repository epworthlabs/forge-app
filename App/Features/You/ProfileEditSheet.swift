import SwiftUI
import PhotosUI

/// Feature request — "let users edit those two fields if they want. If they want to upload a
/// photo to change their avatar pic they can, and if they want to change their name they can too."
/// Also — "users should be able to edit their current weight in the profile section... make sure
/// this is taken into account when determining target calories." Current weight lives on
/// `AppStore.profile` (CloudKit-synced core domain data), unlike username/avatar which are purely
/// local `ProfileSettings` — so this sheet touches both.
struct ProfileEditSheet: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject private var settings = ProfileSettings.shared
    @Environment(\.dismiss) private var dismiss

    @State private var username: String
    @State private var avatarData: Data?
    @State private var photoItem: PhotosPickerItem?
    @State private var currentWeightLb: Int

    init(currentWeightLb: Int) {
        _username = State(initialValue: ProfileSettings.shared.username)
        _avatarData = State(initialValue: ProfileSettings.shared.avatarImageData)
        _currentWeightLb = State(initialValue: currentWeightLb)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Capsule().fill(ForgeColors.cardBorder).frame(width: 36, height: 4).frame(maxWidth: .infinity)
            Text("Edit Profile").font(ForgeType.title).foregroundStyle(ForgeColors.ink)

            PhotosPicker(selection: $photoItem, matching: .images) {
                ZStack(alignment: .bottomTrailing) {
                    AvatarView(imageData: avatarData, size: 92)
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(ForgeColors.accent, .white)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .onChange(of: photoItem) { newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self) {
                        avatarData = data
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Username").font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                TextField("Username", text: $username)
                    .font(ForgeType.body).foregroundStyle(ForgeColors.ink)
                    .padding(14)
                    .frame(minHeight: 44)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            HStack {
                Text("Current weight").font(ForgeType.body).foregroundStyle(ForgeColors.ink)
                Spacer()
                NumpadField(value: $currentWeightLb, maxDigits: 3, range: 50...600, suffix: "lb")
            }

            Button {
                let trimmed = username.trimmingCharacters(in: .whitespaces)
                settings.username = trimmed.isEmpty ? settings.username : trimmed
                settings.avatarImageData = avatarData
                store.updateCurrentWeight(Double(currentWeightLb))
                dismiss()
            } label: {
                Text("Save").font(ForgeType.title).frame(maxWidth: .infinity)
                    .padding(16).foregroundStyle(Color.white).background(ForgeColors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(22)
        .presentationDetents([.height(460)])
    }
}
