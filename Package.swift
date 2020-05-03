// swift-tools-version:5.1

import PackageDescription

let package = Package(
    name: "TestReportWebsite",
    products: [
        .executable(name: "TestReportWebsite", targets: ["TestReportWebsite"])
    ],
    dependencies: [
        .package(url: "https://github.com/johnsundell/publish.git", from: "0.3.0")
    ],
    targets: [
        .target(
            name: "TestReportWebsite",
            dependencies: ["Publish"]
        )
    ]
)