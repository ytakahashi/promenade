#if DEBUG
  import Foundation
  import Testing

  @testable import Sensors

  struct GPXParserTests {
    @Test func parsesNamespacedTracksAndPreservesTimeAndElevation() throws {
      let points = try GPXParser.parse(
        Data(
          """
          <gpx xmlns="http://www.topografix.com/GPX/1/1"><trk><trkseg>
            <trkpt lat="35" lon="139"><ele>42.5</ele><time>2026-01-01T00:00:00Z</time></trkpt>
            <trkpt lat="35.1" lon="139.1"><time>2026-01-01T09:00:01.125+09:00</time></trkpt>
          </trkseg></trk></gpx>
          """.utf8))
      #expect(points.count == 2)
      #expect(points[0].coordinate.latitude == 35)
      #expect(points[0].coordinate.longitude == 139)
      #expect(points[0].altitude == 42.5)
      #expect(points[0].horizontalAccuracy == 5)
      #expect(points[0].verticalAccuracy == 5)
      #expect(points[0].speed == -1)
      #expect(points[0].speedAccuracy == -1)
      #expect(points[0].course == -1)
      #expect(points[1].verticalAccuracy == -1)
      #expect(points[1].timestamp.timeIntervalSince(points[0].timestamp) == 1.125)
    }

    @Test(arguments: [
      "<trkpt lon='139'><time>2026-01-01T00:00:00Z</time></trkpt>",
      "<trkpt lat='91' lon='139'><time>2026-01-01T00:00:00Z</time></trkpt>",
      "<trkpt lat='35' lon='nan'><time>2026-01-01T00:00:00Z</time></trkpt>",
      "<trkpt lat='35' lon='139'/>",
      "<trkpt lat='35' lon='139'><time>invalid</time></trkpt>",
      "<trkpt lat='35' lon='139'><ele>nan</ele><time>2026-01-01T00:00:00Z</time></trkpt>",
      "<trkpt lat='35' lon='139'><time>2026-01-01T00:00:00Z</time><time>2026-01-01T00:00:01Z</time></trkpt>",
    ])
    func rejectsInvalidPoints(_ xml: String) {
      #expect(throws: GPXError.invalidPoint) {
        try GPXParser.parse(Data("<gpx><trk><trkseg>\(xml)</trkseg></trk></gpx>".utf8))
      }
    }

    @Test(arguments: ["2026-01-01T00:00:00Z", "2025-12-31T23:59:59Z"])
    func rejectsDuplicateOrReversedTimes(_ second: String) {
      #expect(throws: GPXError.nonIncreasingTimestamps) {
        try GPXParser.parse(
          Data(
            """
            <gpx><trk><trkseg>
            <trkpt lat="35" lon="139"><time>2026-01-01T00:00:00Z</time></trkpt>
            <trkpt lat="35" lon="139"><time>\(second)</time></trkpt>
            </trkseg></trk></gpx>
            """.utf8))
      }
    }

    @Test func rejectsMalformedEmptyAndUnrelatedDocuments() {
      for xml in ["", "<gpx>", "<other/>"] {
        #expect(throws: GPXError.malformedXML) { try GPXParser.parse(Data(xml.utf8)) }
      }
      #expect(throws: GPXError.noTrackPoints) { try GPXParser.parse(Data("<gpx/>".utf8)) }
    }
  }
#endif
