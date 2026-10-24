#if DEBUG
  import Foundation

  public struct ReplayLaunchOptions: Sendable, Equatable {
    public let path: String
    public let speedMultiplier: Double
    /// When false, step counting behaves as if motion access were denied.
    public let measuresSteps: Bool

    public enum ParseError: Error, Equatable, LocalizedError {
      case missingValue(String)
      case duplicateOption(String)
      case absolutePathRequired
      case invalidSpeed
      case invalidSteps
      case missingGPX

      public var errorDescription: String? {
        switch self {
        case .missingValue(let option): "Missing value for \(option)."
        case .duplicateOption(let option): "Duplicate option: \(option)."
        case .absolutePathRequired: "Replay GPX requires an absolute file path."
        case .invalidSpeed: "Replay speed must be a positive, finite number."
        case .invalidSteps: "Replay steps must be \"none\" when specified."
        case .missingGPX: "Replay speed and steps require -ReplayGPX."
        }
      }
    }

    /// Ignores unrelated system arguments without performing any file access.
    public static func parse(_ arguments: [String]) throws -> Self? {
      var values: [String: String] = [:]
      let options: Set<String> = ["-ReplayGPX", "-ReplaySpeed", "-ReplaySteps"]
      var index = 0
      while index < arguments.count {
        let option = arguments[index]
        index += 1
        guard options.contains(option) else { continue }
        guard values[option] == nil else { throw ParseError.duplicateOption(option) }
        guard index < arguments.count, !arguments[index].isEmpty,
          !options.contains(arguments[index])
        else { throw ParseError.missingValue(option) }
        values[option] = arguments[index]
        index += 1
      }
      guard let path = values["-ReplayGPX"] else {
        if values["-ReplaySpeed"] != nil || values["-ReplaySteps"] != nil {
          throw ParseError.missingGPX
        }
        return nil
      }
      guard (path as NSString).isAbsolutePath else { throw ParseError.absolutePathRequired }
      let speed =
        values["-ReplaySpeed"].flatMap(Double.init) ?? (values["-ReplaySpeed"] == nil ? 1 : .nan)
      guard speed.isFinite, speed > 0 else { throw ParseError.invalidSpeed }
      let steps = values["-ReplaySteps"]
      guard steps == nil || steps == "none" else { throw ParseError.invalidSteps }
      return Self(path: path, speedMultiplier: speed, measuresSteps: steps == nil)
    }
  }
#endif
