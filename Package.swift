// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ImageResize",
    products: [
        .library(name: "ImageResize", targets: ["ImageResize"]),
    ],
    targets: [
        .target(
            name: "ImageResizeC",
            path: "Sources/ImageResizeC",
            publicHeadersPath: "."
        ),
        .target(
            name: "ImageResize",
            dependencies: ["ImageResizeC"],
            path: "Sources/ImageResize"
        )
    ]
)
