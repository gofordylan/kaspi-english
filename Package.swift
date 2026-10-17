// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "KaspiEnglish",
    platforms: [.macOS("15.0")],
    targets: [
        .executableTarget(
            name: "KaspiEnglish",
            path: "Sources/KaspiEnglish"
        )
    ]
)
