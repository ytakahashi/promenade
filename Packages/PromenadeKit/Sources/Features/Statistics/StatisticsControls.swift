import Domain
import SwiftUI

struct StatisticsControls: View {
  let model: StatisticsModel
  @Environment(\.locale) private var locale

  var body: some View {
    VStack(spacing: 16) {
      Picker(
        selection: Binding(get: { model.granularity }, set: { model.setGranularity($0) })
      ) {
        ForEach(StatisticsGranularity.allCases, id: \.self) { granularity in
          granularity.title.tag(granularity)
        }
      } label: {
        Text("Period", bundle: .module)
      }
      .pickerStyle(.segmented)
      HStack {
        Button(action: model.moveBackward) {
          Image(systemName: "chevron.left")
        }
        .accessibilityLabel(Text("Previous period", bundle: .module))
        .disabled(!model.canMoveBackward)
        Spacer(minLength: 8)
        if let period = model.period {
          Text(
            verbatim: StatisticsFormatting(locale: locale, calendar: model.calendar).title(
              for: period)
          )
          .font(.headline)
          .multilineTextAlignment(.center)
        }
        Spacer(minLength: 8)
        Button(action: model.moveForward) {
          Image(systemName: "chevron.right")
        }
        .accessibilityLabel(Text("Next period", bundle: .module))
        .disabled(!model.canMoveForward)
      }
      .buttonStyle(.bordered)
    }
  }
}
