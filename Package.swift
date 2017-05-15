import PackageDescription

let package = Package(
    name: "LCDI2C",
    targets: [Target(name: "LCDI2C")],
    dependencies: [
        .Package(url: "https://www.github.com/novi/i2c-swift.git", majorVersion: 0)
    ]
)
