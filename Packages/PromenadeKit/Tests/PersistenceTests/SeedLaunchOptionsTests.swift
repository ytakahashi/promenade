#if DEBUG
  import Testing

  @testable import Persistence

  struct SeedLaunchOptionsTests {
    @Test func acceptsCountAmongOtherArguments() throws {
      #expect(try SeedLaunchOptions.parse(["App", "-AppleLanguages", "(en)"]) == nil)
      #expect(
        try SeedLaunchOptions.parse([
          "App", "-StoreURL", "/tmp/walks.store", "-SeedSessions", "3000",
        ])
          == 3000)
    }

    @Test(arguments: [["-SeedSessions"], ["-SeedSessions", ""], ["-SeedSessions", "-StoreURL"]])
    func rejectsMissingValue(arguments: [String]) {
      #expect(throws: SeedLaunchOptions.ParseError.missingValue) {
        try SeedLaunchOptions.parse(arguments)
      }
    }

    @Test(arguments: ["0", "-1", "abc", "1.5", "9999999999999999999999999999"])
    func rejectsInvalidCount(value: String) {
      #expect(throws: SeedLaunchOptions.ParseError.invalidCount) {
        try SeedLaunchOptions.parse(["-SeedSessions", value])
      }
    }

    @Test func rejectsDuplicateOption() {
      #expect(throws: SeedLaunchOptions.ParseError.duplicateOption) {
        try SeedLaunchOptions.parse(["-SeedSessions", "1", "-SeedSessions", "2"])
      }
    }
  }
#endif
