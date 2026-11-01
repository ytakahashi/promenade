import Domain
import SwiftUI

struct StatisticsDayList: View {
  let entries: [StatisticsEntry]
  let itemsByID: [UUID: SessionListItem]

  var body: some View {
    LazyVStack(alignment: .leading, spacing: 0) {
      Text("Walks", bundle: .module)
        .font(.headline)
        .padding(.bottom, 12)
      if entries.isEmpty {
        Text("No walks on this day", bundle: .module)
          .foregroundStyle(.secondary)
      } else {
        ForEach(entries) { entry in
          if let item = itemsByID[entry.id] {
            NavigationLink(value: item.id) {
              HStack {
                HistoryRow(item: item, style: .timeOnly)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                  .font(.footnote.bold())
                  .foregroundStyle(.tertiary)
              }
              .padding(.vertical, 12)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("statistics.walk")
            if entry.id != entries.last?.id { Divider() }
          }
        }
      }
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
  }
}
