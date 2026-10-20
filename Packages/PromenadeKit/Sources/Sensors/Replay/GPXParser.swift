#if DEBUG
  import Domain
  import Foundation

  public enum GPXError: Error, Sendable, Equatable, LocalizedError {
    case malformedXML
    case invalidPoint
    case nonIncreasingTimestamps
    case noTrackPoints
    case invalidSpeedMultiplier
    case invalidReplayTimeline

    public var errorDescription: String? {
      switch self {
      case .malformedXML: "The replay file is not a valid GPX document."
      case .invalidPoint: "A replay point contains an invalid coordinate, timestamp, or elevation."
      case .nonIncreasingTimestamps: "Replay point timestamps must be strictly increasing."
      case .noTrackPoints: "The replay file contains no track points."
      case .invalidSpeedMultiplier: "Replay speed must be a positive, finite number."
      case .invalidReplayTimeline: "The replay speed produces an unsupported playback timeline."
      }
    }
  }

  /// Parses GPX track points only; file access and playback are separate responsibilities.
  public enum GPXParser {
    public static func parse(_ data: Data) throws -> [TrackPoint] {
      let delegate = TrackParser()
      let parser = XMLParser(data: data)
      parser.shouldProcessNamespaces = true
      // GPX never needs external entities. Do not allow XML input to read other resources.
      parser.shouldResolveExternalEntities = false
      parser.delegate = delegate
      let parsed = parser.parse()
      if let error = delegate.error { throw error }
      guard parsed, delegate.hasRoot else { throw GPXError.malformedXML }
      guard !delegate.points.isEmpty else { throw GPXError.noTrackPoints }
      return delegate.points
    }
  }

  private final class TrackParser: NSObject, XMLParserDelegate {
    private struct PointInput {
      let latitude: Double?
      let longitude: Double?
      var time: String?
      var elevation: String?
    }

    private var path: [String] = []
    private var point: PointInput?
    private var text = ""
    private let dateFormatter = ISO8601DateFormatter()
    private(set) var points: [TrackPoint] = []
    private(set) var error: GPXError?
    private(set) var hasRoot = false

    func parser(
      _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
      qualifiedName qName: String?, attributes attributeDict: [String: String]
    ) {
      path.append(elementName)
      if path.count == 1 {
        hasRoot = elementName == "gpx"
        if !hasRoot { fail(.malformedXML, parser: parser) }
      }
      if path == ["gpx", "trk", "trkseg", "trkpt"] {
        point = PointInput(
          latitude: attributeDict["lat"].flatMap(Double.init),
          longitude: attributeDict["lon"].flatMap(Double.init))
      }
      text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(
      _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
      qualifiedName qName: String?
    ) {
      defer {
        path.removeLast()
        text = ""
      }
      let pointPath = ["gpx", "trk", "trkseg", "trkpt"]
      if path == pointPath + ["time"] {
        if point?.time != nil {
          fail(.invalidPoint, parser: parser)
          return
        }
        point?.time = text.trimmingCharacters(in: .whitespacesAndNewlines)
      } else if path == pointPath + ["ele"] {
        if point?.elevation != nil {
          fail(.invalidPoint, parser: parser)
          return
        }
        point?.elevation = text.trimmingCharacters(in: .whitespacesAndNewlines)
      } else if path == pointPath {
        guard let point, let latitude = point.latitude, let longitude = point.longitude,
          latitude.isFinite, longitude.isFinite,
          (-90...90).contains(latitude), (-180...180).contains(longitude),
          let time = point.time, let timestamp = date(time)
        else {
          fail(.invalidPoint, parser: parser)
          return
        }
        var altitude = 0.0
        if let elevation = point.elevation {
          guard let value = Double(elevation), value.isFinite else {
            fail(.invalidPoint, parser: parser)
            return
          }
          altitude = value
        }
        guard points.last.map({ timestamp > $0.timestamp }) ?? true else {
          fail(.nonIncreasingTimestamps, parser: parser)
          return
        }
        points.append(
          TrackPoint(
            timestamp: timestamp, coordinate: Coordinate(latitude: latitude, longitude: longitude),
            horizontalAccuracy: 5, altitude: altitude,
            verticalAccuracy: point.elevation == nil ? -1 : 5,
            speed: -1, speedAccuracy: -1, course: -1))
        self.point = nil
      }
    }

    private func date(_ value: String) -> Date? {
      dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      if let date = dateFormatter.date(from: value) { return date }
      dateFormatter.formatOptions = [.withInternetDateTime]
      return dateFormatter.date(from: value)
    }

    private func fail(_ error: GPXError, parser: XMLParser) {
      self.error = error
      parser.abortParsing()
    }
  }
#endif
