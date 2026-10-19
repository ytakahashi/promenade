// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "PromenadeKit",
  defaultLocalization: "en",
  platforms: [.iOS(.v26)],
  products: [
    // A single product keeps the Xcode project wiring to one package dependency;
    // the app imports only the modules it needs.
    .library(
      name: "PromenadeKit",
      targets: ["Domain", "Persistence", "Sensors", "Tracking", "Features"]
    )
  ],
  targets: [
    .target(name: "Domain"),
    .target(name: "Persistence", dependencies: ["Domain"]),
    .target(name: "Sensors", dependencies: ["Domain"]),
    .target(name: "Tracking", dependencies: ["Domain", "Persistence", "Sensors"]),
    .target(
      name: "Features",
      dependencies: ["Domain", "Persistence", "Tracking"],
      resources: [.process("Resources")],
      swiftSettings: [.defaultIsolation(MainActor.self)]
    ),
    .testTarget(name: "DomainTests", dependencies: ["Domain"]),
    .testTarget(name: "PersistenceTests", dependencies: ["Persistence", "Domain"]),
    .testTarget(name: "SensorsTests", dependencies: ["Sensors", "Domain"]),
    .testTarget(name: "TrackingTests", dependencies: ["Tracking"]),
  ]
)
