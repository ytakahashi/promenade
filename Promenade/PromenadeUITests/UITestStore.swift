import Foundation

/// A temporary directory holding one UI test's own store, passed with the Debug-only `-StoreURL`
/// option. Launching without it would read, recover, or even auto-finish walks in the regular
/// store, and a leftover unfinished walk would block the tests with a recovery prompt.
final class UITestStore {
  let directory: URL

  init() throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  var launchArguments: [String] {
    ["-StoreURL", directory.appendingPathComponent("walks.store").path]
  }

  func remove() {
    try? FileManager.default.removeItem(at: directory)
  }
}
