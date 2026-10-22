#if DEBUG
  import Foundation
  import Testing

  @testable import Persistence

  struct StoreLaunchOptionsTests {
    @Test func absentOptionUsesTheRegularStore() throws {
      #expect(try StoreLaunchOptions.parse(["App", "-AppleLanguages", "(en)"]) == nil)
    }

    @Test func acceptsAnAbsolutePathAmongSystemArguments() throws {
      let url = try StoreLaunchOptions.parse([
        "App", "-ApplePersistenceIgnoreState", "YES", "-StoreURL", "/tmp/ui tests/walks.store",
      ])
      #expect(url == URL(fileURLWithPath: "/tmp/ui tests/walks.store"))
    }

    @Test(arguments: [["-StoreURL"], ["-StoreURL", ""], ["-StoreURL", "-ReplayGPX"]])
    func rejectsAMissingValue(_ arguments: [String]) {
      #expect(throws: StoreLaunchOptions.ParseError.missingValue) {
        try StoreLaunchOptions.parse(arguments)
      }
    }

    @Test func rejectsARelativePath() {
      #expect(throws: StoreLaunchOptions.ParseError.absolutePathRequired) {
        try StoreLaunchOptions.parse(["-StoreURL", "walks.store"])
      }
    }

    @Test func rejectsADuplicateOption() {
      #expect(throws: StoreLaunchOptions.ParseError.duplicateOption) {
        try StoreLaunchOptions.parse(["-StoreURL", "/tmp/a.store", "-StoreURL", "/tmp/b.store"])
      }
    }
  }
#endif
