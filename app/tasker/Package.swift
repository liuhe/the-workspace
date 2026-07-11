// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "tasker",
    platforms: [.macOS(.v14)],
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
        .executableTarget(
            name: "tasker",
            dependencies: ["TaskerDomain", "TaskerPersistence"],
            path: "Sources/App"
        ),
        .executableTarget(
            name: "taskerCheck",
            dependencies: ["TaskerDomain", "TaskerPersistence"],
            path: "Sources/Check"
        ),
    ]
)
