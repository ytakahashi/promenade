import CoreLocation

/// Resolves the access result from service session diagnostics and the authorization state.
///
/// The two sources update independently: a definitive diagnostic can arrive before the location
/// manager reports the new authorization, or the other way around. The result is re-evaluated
/// whenever either changes, so whichever arrives last completes the resolution.
@MainActor
enum LocationAccessResolver {
  private enum Input: Sendable {
    case diagnostic(LocationDiagnostics)
    case authorizationChanged
  }

  static func resolve(
    diagnostics: AsyncThrowingStream<LocationDiagnostics, any Error>,
    authorizationChanges: AsyncStream<Void>,
    authorization: () -> (CLAuthorizationStatus, CLAccuracyAuthorization)
  ) async throws -> LocationAccessResult {
    let (inputs, continuation) = AsyncThrowingStream<Input, any Error>.makeStream()
    let diagnosticsTask = Task {
      do {
        for try await diagnostic in diagnostics { continuation.yield(.diagnostic(diagnostic)) }
        continuation.finish(throwing: LocationSensorError.diagnosticsEnded)
      } catch {
        continuation.finish(throwing: error)
      }
    }
    let changesTask = Task {
      for await _ in authorizationChanges { continuation.yield(.authorizationChanged) }
    }
    defer {
      diagnosticsTask.cancel()
      changesTask.cancel()
    }

    var latest: LocationDiagnostics?
    for try await input in inputs {
      if case .diagnostic(let diagnostic) = input { latest = diagnostic }
      // Authorization alone cannot decide: denial and pending requests come from diagnostics.
      guard let latest else { continue }
      let (status, accuracy) = authorization()
      if let result = latest.accessResult(authorization: status, accuracy: accuracy) {
        return result
      }
    }
    // The input stream also ends when the waiting task is cancelled.
    try Task.checkCancellation()
    throw LocationSensorError.diagnosticsEnded
  }
}
