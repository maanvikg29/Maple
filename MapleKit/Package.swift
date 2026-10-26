// swift-tools-version: 6.2
import PackageDescription

/// UI-facing modules run on the main actor by default; MapleCore stays nonisolated
/// so it can be used from extensions and background work.
let mainActorByDefault: [SwiftSetting] = [
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("MemberImportVisibility"),
]

let package = Package(
    name: "MapleKit",
    defaultLocalization: "en",
    platforms: [.iOS("27.0")],
    products: [
        .library(name: "MapleCore", targets: ["MapleCore"]),
        .library(name: "MapleDesign", targets: ["MapleDesign"]),
        .library(name: "MapleData", targets: ["MapleData"]),
        .library(name: "MapleServices", targets: ["MapleServices"]),
        .library(name: "MapleFocusCore", targets: ["MapleFocusCore"]),
        .library(name: "MapleStorage", targets: ["MapleStorage"]),
        .library(name: "MapleActivity", targets: ["MapleActivity"]),
    ],
    targets: [
        // The types the F1-paid extensions share (events, plans, time, the ledger and the reconciler). No
        // resources, so the ~6 MB DeviceActivityMonitor extension can link it on its own. MapleCore re-exports it.
        .target(
            name: "MapleFocusCore",
            swiftSettings: [.enableUpcomingFeature("MemberImportVisibility")]
        ),
        // The App Group container and the JSON-lines ledger files every Maple process writes. Nonisolated.
        .target(
            name: "MapleStorage",
            dependencies: ["MapleFocusCore"],
            swiftSettings: [.enableUpcomingFeature("MemberImportVisibility")]
        ),
        // The Live Activity's attributes and content, shared by the app and the MapleWidgets extension. Nonisolated,
        // with no resources and no other Maple module, so the extension links only this (F1 design §7.7).
        .target(
            name: "MapleActivity",
            swiftSettings: [.enableUpcomingFeature("MemberImportVisibility")]
        ),
        // Pure Foundation. No SwiftUI/SwiftData: it must fit in the ~6 MB DeviceActivityMonitor extension.
        .target(
            name: "MapleCore",
            dependencies: ["MapleFocusCore"],
            resources: [.copy("Resources/species.json"), .copy("Resources/rewards.json")],
            swiftSettings: [.enableUpcomingFeature("MemberImportVisibility")]
        ),
        .target(name: "MapleDesign", dependencies: ["MapleCore"], swiftSettings: mainActorByDefault),
        .target(
            name: "MapleData",
            dependencies: ["MapleCore"],
            swiftSettings: [.enableUpcomingFeature("MemberImportVisibility")]
        ),
        .target(name: "MapleServices", dependencies: ["MapleCore", "MapleData", "MapleStorage"], swiftSettings: mainActorByDefault),
        .testTarget(name: "MapleCoreTests", dependencies: ["MapleCore", "MapleFocusCore"]),
        .testTarget(name: "MapleDesignTests", dependencies: ["MapleDesign", "MapleCore", "MapleActivity"]),
        .testTarget(name: "MapleServicesTests", dependencies: ["MapleServices", "MapleCore", "MapleStorage", "MapleFocusCore"]),
    ]
)
