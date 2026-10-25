#if DEBUG
  import Foundation

  public enum SeedLaunchOptions {
    public enum ParseError: Error, Equatable, LocalizedError {
      case missingValue
      case duplicateOption
      case invalidCount

      public var errorDescription: String? {
        switch self {
        case .missingValue: "Missing value for -SeedSessions."
        case .duplicateOption: "Duplicate option: -SeedSessions."
        case .invalidCount: "-SeedSessions requires a positive integer."
        }
      }
    }

    /// Ignores unrelated arguments. The app must require an isolated store before seeding.
    public static func parse(_ arguments: [String]) throws -> Int? {
      var count: Int?
      var index = 0
      while index < arguments.count {
        let option = arguments[index]
        index += 1
        guard option == "-SeedSessions" else { continue }
        guard count == nil else { throw ParseError.duplicateOption }
        // Unlike a path, a negative number is a value: "-1" is an invalid count, while a following
        // option such as "-StoreURL" means the value is missing.
        guard index < arguments.count, !arguments[index].isEmpty,
          !arguments[index].hasPrefix("-") || Int(arguments[index]) != nil
        else { throw ParseError.missingValue }
        guard let value = Int(arguments[index]), value > 0 else { throw ParseError.invalidCount }
        count = value
        index += 1
      }
      return count
    }
  }
#endif
