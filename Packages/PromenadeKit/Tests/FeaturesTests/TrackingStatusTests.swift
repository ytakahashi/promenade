import Domain
import Foundation
import Testing
import Tracking

@testable import Features

@MainActor
struct TrackingStatusTests {
  // MARK: Idle access

  @Test func idleAccessNoticeFollowsTheMonitor() {
    let cases: [(LocationAccessState, IdleAccessNotice?)] = [
      (.notDetermined, nil), (.available, nil), (.unavailable, nil), (.denied, .denied),
      (.restricted, .restricted), (.servicesDisabled, .servicesDisabled),
      (.fullAccuracyRequired, .approximateOnly),
    ]
    for (access, expected) in cases {
      #expect(IdleAccessNotice(access: access, startFailure: nil) == expected)
    }
  }

  @Test func startFailureExplainsAccessBeforeTheMonitorCatchesUp() {
    let cases: [(LocationAccessIssue, IdleAccessNotice)] = [
      (.denied, .denied), (.servicesDisabled, .servicesDisabled),
      (.accuracyLimited, .approximateOnly),
    ]
    for (issue, expected) in cases {
      #expect(IdleAccessNotice(access: .available, startFailure: .access(issue)) == expected)
    }
    #expect(IdleAccessNotice(access: .available, startFailure: .sensor) == nil)
  }

  @Test func onlyApproximateAccessKeepsStart() {
    #expect(IdleAccessNotice.approximateOnly.allowsStart)
    #expect(!IdleAccessNotice.denied.allowsStart)
    #expect(!IdleAccessNotice.restricted.allowsStart)
    #expect(!IdleAccessNotice.servicesDisabled.allowsStart)
  }

  @Test func settingsAreOfferedOnlyWhereTheAppsPageCanFixAccess() {
    #expect(IdleAccessNotice.denied.opensSettings)
    #expect(IdleAccessNotice.approximateOnly.opensSettings)
    #expect(!IdleAccessNotice.restricted.opensSettings)
    #expect(!IdleAccessNotice.servicesDisabled.opensSettings)
  }

  // MARK: Banner

  @Test func interruptionTakesPrecedenceOverFailures() {
    #expect(
      banner(.recording(.waitingForAccess(.denied)), operation: .sensor)
        == .waitingForAccess(.denied))
  }

  @Test func recordingFailuresChooseTheirRetry() {
    #expect(banner(.recording(.searching), operation: .sensor) == .updatesStopped)
    #expect(banner(.recording(.active), operation: .persistence) == .pointsUnsaved)
    #expect(banner(.paused, operation: .persistence) == .pointsUnsaved)
    #expect(banner(.recording(.searching)) == .searching)
    #expect(banner(.recording(.active)) == nil)
  }

  @Test func accessFailuresAreNotRepeatedInTheBanner() {
    #expect(banner(.recording(.active), operation: .access(.denied)) == nil)
    #expect(banner(.idle, start: .access(.denied)) == nil)
  }

  @Test func idleStartFailuresCanBeDismissed() {
    #expect(banner(.idle, start: .sensor) == .startFailed(.sensor))
    #expect(banner(.idle, start: .persistence) == .startFailed(.persistence))
  }

  @Test func failuresOwnedByDialogsAreHidden() {
    #expect(banner(.recording(.active), operation: .persistence, owned: true) == nil)
    #expect(banner(.idle, start: .sensor, owned: true) == nil)
    #expect(banner(.recording(.searching), operation: .sensor, owned: true) == .searching)
  }

  @Test func remainingFailuresUseAGenericMessage() {
    #expect(banner(.idle, operation: .persistence) == .failed(.persistence))
  }

  private func banner(
    _ phase: TrackingPhase, start: TrackingFailure? = nil, operation: TrackingFailure? = nil,
    owned: Bool = false
  ) -> StatusBannerContent? {
    StatusBannerContent.resolve(
      phase: phase, startFailure: start, operationFailure: operation,
      failureOwnedElsewhere: owned)
  }
}
