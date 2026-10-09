// Snapshot harness: renders the scenes returned by `snapshotScenes()` to PNG files.
// Compiled together with MapleCore + MapleDesign sources by Scripts/snapshot.sh — not part of the app.
import SwiftUI
import AppKit

struct SnapshotScene {
    let name: String
    let size: CGSize
    let view: AnyView

    init<V: View>(_ name: String, size: CGSize = CGSize(width: 402, height: 874), @ViewBuilder _ view: () -> V) {
        self.name = name
        self.size = size
        self.view = AnyView(view())
    }
}

@MainActor
func renderAll(to directory: URL) {
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for scene in snapshotScenes() {
        let content = scene.view
            .frame(width: scene.size.width, height: scene.size.height)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            print("FAILED \(scene.name)")
            continue
        }
        let url = directory.appendingPathComponent("\(scene.name).png")
        try? png.write(to: url)
        print("wrote \(url.path)")
    }
}

@main
struct SnapshotMain {
    static func main() {
        let out = CommandLine.arguments.dropFirst().first ?? "snapshots"
        MainActor.assumeIsolated {
            renderAll(to: URL(fileURLWithPath: out))
        }
    }
}
