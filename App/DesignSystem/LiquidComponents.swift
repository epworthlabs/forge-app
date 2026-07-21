import SwiftUI

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
