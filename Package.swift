// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MDMInspector",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MDMInspector", targets: ["MDMInspectorApp"]),
        .executable(name: "MDMInspectorSelfTest", targets: ["MDMInspectorSelfTest"])
    ],
    targets: [
        // Models, collectors and views live in the library so they can be
        // exercised headlessly by the self-test target.
        .target(
            name: "MDMInspectorKit",
            path: "Sources/MDMInspector",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // The shipping app: a thin @main shim over the kit.
        .executableTarget(
            name: "MDMInspectorApp",
            dependencies: ["MDMInspectorKit"],
            path: "Sources/MDMInspectorApp",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Collector verification against the real system:
        //   swift run -c release MDMInspectorSelfTest
        .executableTarget(
            name: "MDMInspectorSelfTest",
            dependencies: ["MDMInspectorKit"],
            path: "Sources/MDMInspectorSelfTest",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
