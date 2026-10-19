/// Version of the logic that derives stored metrics (distance, durations) from raw points.
///
/// Bump `current` whenever `RouteFilter` (including `RouteFilter.Configuration`) or the metrics
/// calculation changes, so sessions saved with older logic can be detected and recomputed.
/// `StoragePointPolicy` is not covered: points it discarded are gone and cannot be recomputed.
public enum DerivedDataVersion {
  public static let current = 1
}
