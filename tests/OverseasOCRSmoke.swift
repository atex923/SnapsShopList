import AppKit

@main
enum OverseasOCRSmoke {
    static func main() async throws {
        let image = NSImage(size: NSSize(width: 900, height: 300))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 900, height: 300).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 92, weight: .bold),
            .foregroundColor: NSColor.black
        ]
        NSString(string: "MILK 1000ml").draw(at: NSPoint(x: 70, y: 90), withAttributes: attributes)
        image.unlockFocus()

        guard
            let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let data = bitmap.representation(using: .png, properties: [:])
        else {
            fatalError("Unable to encode OCR fixture")
        }
        let lines = try await OverseasTextRecognizer.recognize(data)
        precondition(lines.joined(separator: " ").uppercased().contains("MILK"))
        print("Overseas OCR smoke tests passed")
    }
}
