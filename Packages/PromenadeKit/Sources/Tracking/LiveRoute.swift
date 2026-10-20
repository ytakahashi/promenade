import Domain

public struct LiveRoute: Sendable {
  public private(set) var segments: [RouteFilter.Accumulator] = []
  private let filter: RouteFilter

  public init(segments: [SegmentRecord], filter: RouteFilter) {
    self.filter = filter
    self.segments = segments.map { filter.filter($0.points) }
  }

  public var distance: Double { segments.reduce(0) { $0 + $1.distance } }

  mutating func openSegment() { segments.append(filter.makeAccumulator()) }

  mutating func append(_ point: TrackPoint) {
    guard !segments.isEmpty else { return }
    segments[segments.count - 1].add(point)
  }
}
