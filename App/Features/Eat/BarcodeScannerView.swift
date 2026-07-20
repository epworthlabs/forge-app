import SwiftUI
import VisionKit

/// FRG-125. Wraps VisionKit's DataScannerViewController rather than AVFoundation directly — no
/// camera hardware in Simulator, so `isSupported`/`isAvailable` correctly report false there.
/// That path (the fallback message below) is what's actually verified on this machine; the real
/// scan callback needs a physical device to confirm end to end.
struct BarcodeScannerView: View {
    var onScan: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    ScannerRepresentable(onScan: { code in
                        onScan(code)
                        dismiss()
                    })
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "camera.metering.unknown").font(.system(size: 32)).foregroundStyle(ForgeColors.inkMuted)
                        Text("Barcode scanning isn't available on this device.")
                            .font(ForgeType.body).foregroundStyle(ForgeColors.ink).multilineTextAlignment(.center)
                        Text("Search by name instead.")
                            .font(ForgeType.caption).foregroundStyle(ForgeColors.inkMuted)
                    }
                    .padding(32)
                }
            }
            .navigationTitle("Scan Barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}

private struct ScannerRepresentable: UIViewControllerRepresentable {
    var onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode()],
            qualityLevel: .balanced,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        try? uiViewController.startScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        init(onScan: @escaping (String) -> Void) { self.onScan = onScan }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                if case .barcode(let barcode) = item, let payload = barcode.payloadStringValue {
                    onScan(payload)
                    return
                }
            }
        }
    }
}
