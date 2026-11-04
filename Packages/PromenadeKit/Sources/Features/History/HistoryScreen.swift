import Domain
import SwiftUI

struct HistoryScreen: View {
  let trim: SessionTrimDependencies
  let model: HistoryModel
  let route: RouteFilter.Configuration
  let readSession: @MainActor (UUID) async throws -> SessionRecord?
  let settings: SettingsModel
  let locationAccess: LocationAccessState
  @State private var showsSettings = false
  @Environment(\.locale) private var locale

  var body: some View {
    NavigationStack {
      content
        .navigationTitle(Text("History", bundle: .module))
        .toolbar {
          ToolbarItem(placement: .topBarTrailing) {
            Button {
              showsSettings = true
            } label: {
              Label {
                Text("Settings", bundle: .module)
              } icon: {
                Image(systemName: "gearshape")
              }
            }
          }
        }
        .navigationDestination(for: UUID.self) { id in
          SessionDetailScreen(
            model: SessionSummaryModel(sessionID: id, route: route, read: readSession), trim: trim)
        }
    }
    .onAppear { model.load() }
    .sheet(isPresented: $showsSettings) {
      SettingsSheet(
        model: settings, locationAccess: locationAccess, close: { showsSettings = false })
    }
    .alert(
      Text("Delete Walk?", bundle: .module),
      isPresented: Binding(
        get: { model.pendingDeletion != nil }, set: { if !$0 { model.cancelDelete() } })
    ) {
      Button(role: .destructive) {
        Task.immediate { await model.confirmDelete() }
      } label: {
        Text("Delete", bundle: .module)
      }
      Button(role: .cancel) {
        model.cancelDelete()
      } label: {
        Text("Cancel", bundle: .module)
      }
    } message: {
      Text("The walk and its route are deleted permanently.", bundle: .module)
    }
    .alert(
      Text("Unable to Delete Walk", bundle: .module),
      isPresented: Binding(
        get: { model.deleteFailed }, set: { if !$0 { model.dismissDeleteFailure() } })
    ) {
      Button {
        model.dismissDeleteFailure()
      } label: {
        Text("OK", bundle: .module)
      }
    } message: {
      Text("The walk is still saved. Try deleting it again.", bundle: .module)
    }
  }

  @ViewBuilder
  private var content: some View {
    switch model.state {
    case .loading:
      ProgressView()
    case .failed:
      WalksReadFailureView(retry: model.load)
    case .loaded(let sections) where sections.isEmpty:
      NoWalksView()
    case .loaded(let sections):
      List {
        ForEach(sections) { section in
          Section {
            ForEach(section.items) { item in
              NavigationLink(value: item.id) { HistoryRow(item: item) }
                .accessibilityIdentifier("history.row")
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                  // Not a destructive role: that removes the row before the user confirms, and
                  // it would stay hidden if they cancel.
                  Button {
                    model.requestDelete(item)
                  } label: {
                    Label {
                      Text("Delete", bundle: .module)
                    } icon: {
                      Image(systemName: "trash")
                    }
                  }
                  .tint(.red)
                  .disabled(model.isDeleting)
                }
            }
          } header: {
            Text(verbatim: section.title(locale: locale))
          }
          .id(section.id)
        }
      }
    }
  }
}
