#if DEBUG
  import Testing

  @testable import Sensors

  struct ReplayLaunchOptionsTests {
    @Test func ignoresUnrelatedArguments() throws {
      #expect(try ReplayLaunchOptions.parse(["App", "-AppleLanguages", "(en)"]) == nil)
    }

    @Test func defaultsToNormalSpeed() throws {
      let options = try #require(
        try ReplayLaunchOptions.parse(["App", "-ReplayGPX", "/tmp/walk with spaces.gpx"]))
      #expect(options.path == "/tmp/walk with spaces.gpx")
      #expect(options.speedMultiplier == 1)
    }

    @Test func acceptsReorderedOptionsAndSystemArguments() throws {
      let options = try #require(
        try ReplayLaunchOptions.parse([
          "App", "-ReplaySpeed", "2.5", "-ApplePersistenceIgnoreState", "YES",
          "-ReplayGPX", "/tmp/walk.gpx",
        ]))
      #expect(options.speedMultiplier == 2.5)
    }

    @Test(arguments: ["0", "-1", "nan", "inf", "-inf", "abc", "1e999"])
    func rejectsInvalidSpeed(_ value: String) {
      #expect(throws: ReplayLaunchOptions.ParseError.invalidSpeed) {
        try ReplayLaunchOptions.parse(["-ReplayGPX", "/tmp/walk.gpx", "-ReplaySpeed", value])
      }
    }

    @Test(arguments: ["-ReplayGPX", "-ReplaySpeed"])
    func rejectsMissingValues(_ option: String) {
      for arguments in [[option], [option, ""], [option, "-ReplayGPX"]] {
        #expect(throws: ReplayLaunchOptions.ParseError.missingValue(option)) {
          try ReplayLaunchOptions.parse(arguments)
        }
      }
    }

    @Test func rejectsRelativePathAndOrphanSpeed() {
      #expect(throws: ReplayLaunchOptions.ParseError.absolutePathRequired) {
        try ReplayLaunchOptions.parse(["-ReplayGPX", "walk.gpx"])
      }
      #expect(throws: ReplayLaunchOptions.ParseError.missingGPX) {
        try ReplayLaunchOptions.parse(["-ReplaySpeed", "2"])
      }
    }

    @Test(arguments: ["-ReplayGPX", "-ReplaySpeed"])
    func rejectsDuplicateOptions(_ option: String) {
      #expect(throws: ReplayLaunchOptions.ParseError.duplicateOption(option)) {
        try ReplayLaunchOptions.parse([option, "/tmp/walk.gpx", option, "2"])
      }
    }
  }
#endif
