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
    ],
    targets: [
        // Pure Foundation. No SwiftUI/SwiftData: it must fit in the ~6 MB DeviceActivityMonitor extension.
        .target(
            name: "MapleCore",
            resources: [.copy("Resources/species.json"), .copy("Resources/rewards.json")],
            swiftSettings: [.enableUpcomingFeature("MemberImportVisibility")]
        ),
        .target(name: "MapleDesign", dependencies: ["MapleCore"], swiftSettings: mainActorByDefault),
        .target(
            name: "MapleData",
            dependencies: ["MapleCore"],
            swiftSettings: [.enableUpcomingFeature("MemberImportVisibility")]
        ),
        .target(name: "MapleServices", dependencies: ["MapleCore", "MapleData"], swiftSettings: mainActorByDefault),
        .testTarget(name: "MapleCoreTests", dependencies: ["MapleCore"]),
        .testTarget(name: "MapleDesignTests", dependencies: ["MapleDesign", "MapleCore"]),
        .testTarget(name: "MapleServicesTests", dependencies: ["MapleServices", "MapleCore"]),
    ]
)
