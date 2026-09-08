// swift-tools-version: 6.3

import PackageDescription

// パッケージ名・モジュール名は公開識別子の写像表 (cross/ADR-0005) に、
// 最低対象 OS は iOS 17 (cross/ADR-0002) に従う。
let package = Package(
    name: "KsDialogs",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "KsDialogs",
            targets: ["KsDialogs"]
        )
    ],
    targets: [
        .target(
            name: "KsDialogs"
        ),
        .testTarget(
            name: "KsDialogsTests",
            dependencies: ["KsDialogs"]
        )
    ],
    swiftLanguageModes: [.v6]
)
