#if DEBUG
  import Foundation

  /// `-StoreURL <absolute path>` stores walks in a separate file, so UI tests can relaunch against
  /// their own data without resetting the regular store.
  public enum StoreLaunchOptions {
    public enum ParseError: Error, Equatable, LocalizedError {
      case missingValue
      case duplicateOption
      case absolutePathRequired

      public var errorDescription: String? {
        switch self {
        case .missingValue: "Missing value for -StoreURL."
        case .duplicateOption: "Duplicate option: -StoreURL."
        case .absolutePathRequired: "-StoreURL requires an absolute file path."
        }
      }
    }

    /// Ignores unrelated system arguments without performing any file access.
    public static func parse(_ arguments: [String]) throws -> URL? {
      var path: String?
      var index = 0
      while index < arguments.count {
        let option = arguments[index]
        index += 1
        guard option == "-StoreURL" else { continue }
        guard path == nil else { throw ParseError.duplicateOption }
        guard index < arguments.count, !arguments[index].isEmpty, !arguments[index].hasPrefix("-")
        else { throw ParseError.missingValue }
        path = arguments[index]
        index += 1
      }
      guard let path else { return nil }
      guard (path as NSString).isAbsolutePath else { throw ParseError.absolutePathRequired }
      return URL(fileURLWithPath: path)
    }
  }
#endif
