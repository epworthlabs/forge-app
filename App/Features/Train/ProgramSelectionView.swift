import SwiftUI
import ForgeCore

/// Feature request — "select which workout program they want to do, especially if they have
/// multiple... this should be the screen that initiates and funnels down to the other screens."
/// Root of the Train tab: a tile grid of everything in `store.savedPrograms`, funneling into
/// DaySelectionView once a program is active.
struct ProgramSelectionView: View {
    @EnvironmentObject var store: AppStore
    var onProgramReady: () -> Void
    @State private var buildingNewProgram = false

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ZStack {
            ForgeColors.backgroundBase.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Train").font(ForgeType.displayLarge).foregroundStyle(ForgeColors.ink)
                    Text("Choose a program").font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(store.savedPrograms) { program in
                            ProgramTile(program: program, isActive: program.id == store.program.id) {
                                if program.id != store.program.id { store.activateProgram(program) }
                                onProgramReady()
                            }
                        }

                        Button { buildingNewProgram = true } label: {
                            VStack(spacing: 6) {
                                Image(systemName: "plus.circle").font(.system(size: 22)).foregroundStyle(ForgeColors.inkMuted)
                                Text("New Program").font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 110)
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(ForgeColors.cardBorder, style: StrokeStyle(dash: [5, 4])))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("Programs")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $buildingNewProgram) {
            ProgramEditorView { newProgram in
                store.activateProgram(newProgram)
                onProgramReady()
            }
        }
    }
}

private struct ProgramTile: View {
    let program: ProgramTemplate
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                if isActive {
                    Text("ACTIVE").font(ForgeType.label).foregroundStyle(Color.white.opacity(0.85))
                }
                Text(program.name).font(ForgeType.body).foregroundStyle(isActive ? Color.white : ForgeColors.ink).lineLimit(2)
                Text(program.meta).font(ForgeType.caption).foregroundStyle(isActive ? Color.white.opacity(0.85) : ForgeColors.inkMuted)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(14)
            .frame(height: 110, alignment: .topLeading)
            .background {
                isActive ? AnyView(ForgeColors.accent) : AnyView(Rectangle().fill(.ultraThinMaterial))
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
