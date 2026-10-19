import Testing

@testable import Domain

struct GeoDistanceTests {
  @Test func sameCoordinateIsZero() {
    #expect(GeoDistance.meters(from: .origin, to: .origin) == 0)
  }

  @Test func oneDegreeOfLongitudeAtEquator() {
    let a = Coordinate(latitude: 0, longitude: 0)
    let b = Coordinate(latitude: 0, longitude: 1)
    #expect(abs(GeoDistance.meters(from: a, to: b) - 111_195.08) < 0.1)
  }

  @Test func knownCityPair() {
    // Nashville (BNA) to Los Angeles (LAX): the classic haversine example, which gives
    // 2,887.26 km with R = 6,372.8 km; rescaled to the mean radius used here.
    let bna = Coordinate(latitude: 36.12, longitude: -86.67)
    let lax = Coordinate(latitude: 33.94, longitude: -118.40)
    #expect(abs(GeoDistance.meters(from: bna, to: lax) - 2_886_448.4) < 1)
  }

  @Test func isSymmetric() {
    let a = Coordinate(latitude: 35.681236, longitude: 139.767125)
    let b = Coordinate(latitude: 35.689634, longitude: 139.700566)
    #expect(GeoDistance.meters(from: a, to: b) == GeoDistance.meters(from: b, to: a))
  }
}
