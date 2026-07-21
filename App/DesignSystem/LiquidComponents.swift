import SwiftUI
import UIKit

/// "Liquid Glass" — the design direction the style exploration converged on (see
/// `../../../Wireframes/updated/uploads/Fitness and nutrition tracker app/`: TodayGlassLight.dc.html
/// / TodayGlassDark.dc.html). Originally Today-only ("the plan is to roll the same system out
/// elsewhere once this is confirmed live, not change every screen's look in one shot" — see git
/// history); this file is that rollout. `GlassCard` — used by every screen — now *is* the Liquid
/// Glass treatment, so skinning the rest of the app was mostly a matter of nothing needing to
/// change at call sites at all.
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 24
    var dashed: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(20)
            .background(ForgeColors.cardBackground)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(ForgeColors.cardBorder, style: StrokeStyle(lineWidth: 1, dash: dashed ? [5, 4] : []))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(ForgeColors.cardHighlight, lineWidth: 1)
                    .blendMode(.plusLighter)
                    .padding(0.5)
                    .opacity(dashed ? 0 : 1)
            )
            .shadow(color: ForgeColors.cardShadow, radius: 16, x: 0, y: 8)
    }
}

/// A frosted, bordered tile — the flat-value counterpart to `GlassCard`'s full card treatment.
/// Used for compact stat readouts (Today's calorie/protein tiles, elsewhere for anything that
/// needs the same glass texture at a smaller size than a full card).
struct LiquidTile: View {
    let label: String
    let value: String
    var delta: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
            Text(value).font(.system(size: 20, weight: .bold)).foregroundStyle(ForgeColors.ink)
            if let delta {
                Text(delta).font(ForgeType.caption).fontWeight(.semibold).foregroundStyle(ForgeColors.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(ForgeColors.tileBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(ForgeColors.tileBorder, lineWidth: 1))
    }
}

/// A ring-chart stat inside a `GlassCard` — progress-toward-a-number in glanceable form.
struct RingStat: View {
    let label: String
    let value: String
    let progress: Double
    let color: Color

    var body: some View {
        GlassCard {
            VStack(spacing: 8) {
                ZStack {
                    Circle().stroke(ForgeColors.ringTrack, lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: max(0.001, min(1, progress)))
                        .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Circle().fill(ForgeColors.ringFillBackground).padding(9)
                    Text(value).font(.system(size: 14, weight: .bold)).foregroundStyle(ForgeColors.ink)
                }
                .frame(width: 74, height: 74)
                Text(label).font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

/// A labeled progress bar row (current/target), styled to match the glass system's track fill.
struct LiquidMacroRow: View {
    let label: String
    let current: Int
    let target: Int
    var color: Color = ForgeColors.accent

    var body: some View {
        HStack(spacing: 10) {
            Text(label).font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted).frame(width: 56, alignment: .leading)
            GeometryReader { geo in
                let pct = target > 0 ? min(1.0, Double(current) / Double(target)) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(ForgeColors.trackBackground)
                    Capsule().fill(color).frame(width: geo.size.width * pct)
                }
            }
            .frame(height: 8)
            Text("\(current)/\(target)g").font(ForgeType.caption).foregroundStyle(ForgeColors.ink).frame(width: 76, alignment: .trailing)
        }
    }
}

/// Feature request — "give a default avatar... let users edit... upload a photo." Falls back to
/// a plain SF Symbol silhouette when no photo has been picked, rather than an empty box.
struct AvatarView: View {
    let imageData: Data?
    var size: CGFloat = 52

    var body: some View {
        Group {
            if let imageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage).resizable().scaledToFill()
            } else {
                ZStack {
                    ForgeColors.accent
                    Image(systemName: "person.fill")
                        .resizable().scaledToFit()
                        .foregroundStyle(.white)
                        .padding(size * 0.22)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

/// Feature request — "the icon on the left when we add a food item, can we remove that?" That
/// spot was an empty flat-color box (no actual image ever loaded into it — none of the three food
/// sources return one). A letter monogram fills the same space with something real to look at,
/// same idea as the initials-style avatar already used for the profile row in You.
struct FoodMonogram: View {
    let name: String

    var body: some View {
        Circle()
            .fill(ForgeColors.accent.opacity(0.16))
            .overlay(
                Text(name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?")
                    .font(ForgeType.caption).fontWeight(.bold).foregroundStyle(ForgeColors.accent)
            )
    }
}

/// Feature request — "when I input numbers with a numpad... limit the set and rep ranges to be 2
/// digits max, weights... 3 digits max" + "if I first tap that field to edit and input a new
/// number it should replace the existing numbers." Clears on focus (so the first keystroke starts
/// a fresh number instead of appending to what was there) and clamps both digit count and value
/// range as the user types. Generously padded — small tap targets were part of "hard to adjust
/// weights... on such small input buttons."
struct NumpadField: View {
    @Binding var value: Int
    var maxDigits: Int
    var range: ClosedRange<Int>
    var suffix: String?

    @FocusState private var isFocused: Bool
    @State private var text: String = ""

    var body: some View {
        HStack(spacing: 4) {
            TextField("", text: $text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(ForgeType.body).foregroundStyle(ForgeColors.ink)
                .focused($isFocused)
                .frame(minWidth: 40)
            if let suffix {
                Text(suffix).font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
            }
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 10)
        .background(ForgeColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onAppear { text = String(value) }
        .onChange(of: isFocused) { focused in
            // Clearing on focus (rather than trying to detect "first keystroke" from the raw
            // text delta) is what makes typing replace rather than append — SwiftUI's TextField
            // doesn't expose text-selection control on iOS 16 without dropping to UIKit.
            if focused {
                text = ""
            } else if text.isEmpty {
                text = String(value)
            }
        }
        .onChange(of: text) { newText in
            var digits = newText.filter(\.isNumber)
            if digits.count > maxDigits { digits = String(digits.prefix(maxDigits)) }
            if digits != newText { text = digits }
            guard let parsed = Int(digits) else { return }
            value = min(range.upperBound, max(range.lowerBound, parsed))
        }
    }
}

/// Minimum-44pt-tap-target icon button — Apple's own HIG minimum, used for the small circular
/// icon buttons (±, pencil, trash) that were "hard to adjust weights... on such small input
/// buttons" at their old 26-30pt sizes.
struct IconButton: View {
    let systemName: String
    let action: () -> Void
    var size: CGFloat = 44

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ForgeColors.ink)
                .frame(width: size, height: size)
                .background(ForgeColors.cardBackground)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

/// A frosted tile-style button with a dashed border — "add/log something" affordances across the
/// app (Today's quick actions, Train/program editor's "+ Add" buttons, ProgramSelectionView's
/// "New Program" tile all converge on this same shape).
struct DashedActionButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(ForgeType.body).frame(maxWidth: .infinity)
                .padding(14).foregroundStyle(ForgeColors.ink)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(ForgeColors.cardBorder, style: StrokeStyle(dash: [5, 4])))
        }
        .buttonStyle(.plain)
    }
}
