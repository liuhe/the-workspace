// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "tasker",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/liuhe/markdown-lib.git", from: "0.15.0"),
    ],
    targets: [
        .target(
            name: "TaskerDomain",
            path: "Sources/Domain"
        ),
        .target(
            name: "TaskerPersistence",
            dependencies: ["TaskerDomain"],
            path: "Sources/Persistence"
        ),
        .target(
            name: "TaskerIcon",
            path: "Sources/TaskerIcon"
        ),
        .executableTarget(
            name: "tasker",
            dependencies: [
                "TaskerDomain",
                "TaskerPersistence",
                "TaskerIcon",
                .product(name: "MarkdownEditor", package: "markdown-lib"),
            ],
            path: "Sources/App",
            resources: [.copy("Resources")]
        ),
        .executableTarget(
            name: "taskerCheck",
            dependencies: ["TaskerDomain", "TaskerPersistence"],
            path: "Sources/Check"
        ),
        .executableTarget(
            name: "iconGen",
            dependencies: ["TaskerIcon"],
            path: "Sources/IconGen"
        ),
    ]
)
