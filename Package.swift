// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "CaseSensitivityCore",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [.library(name: "CaseSensitivityCore", targets: ["CaseSensitivityCore"])],
    targets: [
        .target(name: "CaseSensitivityCore", path: "Shared"),
        .testTarget(name: "CoreUnitTests", dependencies: ["CaseSensitivityCore"], path: "Tests/Unit"),
        .testTarget(name: "CoreIntegrationTests", dependencies: ["CaseSensitivityCore"], path: "Tests/Integration"),
        .target(name: "CaseSensitivityRendering", dependencies: ["CaseSensitivityCore"], path: "SharedUI",
                exclude: ["TesterModel.swift", "ResultsView.swift", "ReportImportButton.swift"],
                sources: ["ImageReportExporter.swift"]),
        .testTarget(name: "ReportRenderingTests", dependencies: ["CaseSensitivityCore", "CaseSensitivityRendering"],
                    path: "Tests/Rendering")
    ]
)
