import Domain
import Foundation
import Persistence
import SwiftUI

/// The caller supplies a navigation container and connects successful saves to its reloads.
struct SessionTrimScreen: View {
  @State private var model: SessionTrimModel
  @State private var action: Task<Void, Never>?
  @Environment(\.dismiss) private var dismiss
  @Environment(\.locale) private var locale
  let saved: () -> Void

  init(model: SessionTrimModel, saved: @escaping () -> Void) {
    _model = State(initialValue: model)
    self.saved = saved
  }

  var body: some View {
    content
      .navigationTitle(Text("Trim Walk", bundle: .module))
      .navigationBarTitleDisplayMode(.inline)
      .navigationBarBackButtonHidden(model.isSaving)
      .interactiveDismissDisabled(model.isSaving)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button {
            action = Task.immediate { await model.requestSave() }
          } label: {
            Text("Save", bundle: .module)
          }
          .disabled(!model.canSave)
          .accessibilityIdentifier("trim.save")
        }
      }
      .task { await model.load() }
      .task(id: model.selectedDate) { await model.refreshMap() }
      .onDisappear {
        if !model.isSaving { action?.cancel() }
        model.leave()
      }
      .alert(
        Text("Trim Walk?", bundle: .module),
        isPresented: Binding(
          get: { model.phase == .confirming },
          set: { if !$0 { model.cancelConfirmation() } }
        )
      ) {
        Button(role: .destructive) {
          action = Task.immediate {
            if await model.confirmSave() {
              saved()
              dismiss()
            }
          }
        } label: {
          Text("Trim", bundle: .module)
        }
        Button(role: .cancel) {
          model.cancelConfirmation()
        } label: {
          Text("Cancel", bundle: .module)
        }
      } message: {
        if let confirmation = model.confirmation {
          let time = MetricFormatting(locale: locale).dateTime(
            confirmation.date, in: model.timeZone)
          if confirmation.stepsAvailable {
            Text("The route after \(time) will be deleted. This can't be undone.", bundle: .module)
          } else {
            Text(
              "The route after \(time) will be deleted. This can't be undone. Steps will be unavailable.",
              bundle: .module)
          }
        }
      }
      .alert(
        Text("Unable to Save Changes", bundle: .module),
        isPresented: Binding(
          get: { model.saveFailed }, set: { if !$0 { model.dismissFailure() } }
        )
      ) {
        Button {
          model.dismissFailure()
        } label: {
          Text("OK", bundle: .module)
        }
      } message: {
        Text("The walk hasn't changed. Try saving again.", bundle: .module)
      }
  }

  @ViewBuilder private var content: some View {
    if model.phase == .loading {
      ProgressView()
    } else if model.phase == .unavailable {
      ContentUnavailableView {
        Label {
          Text("Unable to Trim Walk", bundle: .module)
        } icon: {
          Image(systemName: "scissors")
        }
      } description: {
        Text("A finished walk with recorded locations is required.", bundle: .module)
      }
    } else {
      editor
        .overlay {
          if model.phase == .querying || model.isSaving {
            ZStack {
              Rectangle().fill(.regularMaterial)
              ProgressView {
                if model.isSaving {
                  Text("Saving Changes…", bundle: .module)
                } else {
                  Text("Checking Steps…", bundle: .module)
                }
              }
            }
          }
        }
    }
  }

  private var editor: some View {
    let formatting = MetricFormatting(locale: locale)
    return List {
      Section {
        if let map = model.map {
          SessionTrimMapView(content: map)
            .frame(height: 300)
            .overlay(alignment: .topTrailing) {
              if model.mapDate != model.selectedDate { ProgressView().padding() }
            }
            .listRowInsets(EdgeInsets())
        }
        HStack {
          Label {
            Text("Keep", bundle: .module)
          } icon: {
            Image(systemName: "line.diagonal").foregroundStyle(.blue)
          }
          Spacer()
          Label {
            Text("Remove", bundle: .module)
          } icon: {
            Image(systemName: "line.diagonal").foregroundStyle(.gray)
          }
        }
        .font(.caption)
      }
      Section {
        Slider(
          value: Binding(
            get: { model.selectedOffset }, set: { model.select(offset: $0) }
          ), in: model.sliderRange
        )
        .disabled(model.phase != .editing || model.data?.timeline.dates.count == 1)
        .accessibilityLabel(Text("Finish time", bundle: .module))
        .accessibilityValue(
          model.selectedDate.map { formatting.dateTime($0, in: model.timeZone) } ?? ""
        )
        .accessibilityAdjustableAction { direction in
          guard let index = model.selectedIndex, let data = model.data else { return }
          let next =
            direction == .increment
            ? min(index + 1, data.timeline.dates.count - 1) : max(index - 1, 0)
          model.select(offset: data.timeline.dates[next].timeIntervalSince(data.record.startDate))
        }
        .accessibilityIdentifier("trim.slider")
        if let date = model.selectedDate {
          LabeledContent {
            Text(verbatim: formatting.dateTime(date, in: model.timeZone))
          } label: {
            Text("Finish time", bundle: .module)
          }
        }
        if let distance = model.distance {
          LabeledContent {
            Text(verbatim: formatting.distance(distance))
          } label: {
            Text("Distance", bundle: .module)
          }
          .accessibilityIdentifier("trim.distance")
        }
        if let timing = model.timing {
          LabeledContent {
            Text(verbatim: formatting.duration(timing.walking))
          } label: {
            Text("Walking time", bundle: .module)
          }
          .accessibilityValue(formatting.durationAccessibility(timing.walking))
        }
      } footer: {
        Text(
          "Choose where your walk ended. The route after this point will be removed.",
          bundle: .module)
      }
    }
    .monospacedDigit()
    .disabled(model.phase != .editing)
  }
}

#if DEBUG
  #Preview("Trim a walk") {
    NavigationStack {
      SessionTrimScreen(
        model: SessionTrimModel(
          record: .previewFinished(pointCount: 600), route: .default,
          trimmer: PreviewSessionTrimmer(), querySteps: { _, _ in nil }), saved: {})
    }
  }

  #Preview("Long walk, large text") {
    NavigationStack {
      SessionTrimScreen(
        model: SessionTrimModel(
          record: .previewFinished(pointCount: 3600, pause: 4000), route: .default,
          trimmer: PreviewSessionTrimmer(), querySteps: { _, _ in nil }), saved: {})
    }
    .environment(\.dynamicTypeSize, .accessibility5)
  }

  #Preview("Single point") {
    NavigationStack {
      SessionTrimScreen(model: previewSparseModel(rejected: false), saved: {})
    }
  }

  #Preview("No accepted locations") {
    NavigationStack {
      SessionTrimScreen(model: previewSparseModel(rejected: true), saved: {})
    }
  }

  private func previewSparseModel(rejected: Bool) -> SessionTrimModel {
    var record = SessionRecord.previewFinished(pointCount: 20)
    var points = record.segments.flatMap(\.points)
    if rejected {
      for index in points.indices { points[index].horizontalAccuracy = 100 }
    } else {
      points = Array(points.prefix(1))
    }
    record.segments = [
      .init(
        index: 0, startDate: record.startDate, endDate: record.endDate,
        endReason: .finished, points: points)
    ]
    return SessionTrimModel(
      record: record, route: .default, trimmer: PreviewSessionTrimmer(),
      querySteps: { _, _ in nil })
  }

  private struct PreviewSessionTrimmer: SessionTrimming {
    func trimEnd(sessionID: UUID, at date: Date, steps: Int?) async throws {}
  }
#endif
