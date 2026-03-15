import SwiftUI
import CoreImage.CIFilterBuiltins

/// Generates and displays a QR code from a PairingQRPayload using CoreImage.
struct QRCodeView: View {
    let payload: PairingQRPayload

    var body: some View {
        if let image = generateQRCode() {
            Image(nsImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "qrcode")
                .font(.system(size: 80))
                .foregroundStyle(.secondary)
        }
    }

    private func generateQRCode() -> NSImage? {
        guard let jsonData = try? JSONEncoder().encode(payload),
              let jsonString = String(data: jsonData, encoding: .utf8),
              let messageData = jsonString.data(using: .utf8) else {
            return nil
        }

        let filter = CIFilter.qrCodeGenerator()
        filter.message = messageData
        filter.correctionLevel = "M"

        guard let ciImage = filter.outputImage else { return nil }

        let transform = CGAffineTransform(scaleX: 10, y: 10)
        let scaledImage = ciImage.transformed(by: transform)

        let rep = NSCIImageRep(ciImage: scaledImage)
        let nsImage = NSImage(size: rep.size)
        nsImage.addRepresentation(rep)
        return nsImage
    }
}
