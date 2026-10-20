/// Actor isolation alone does not serialize operations across awaits to the store.
/// Every operation that reads or changes engine state, including location events, must pass
/// through this queue. `TrackingEngine.flush()` is the one exception; see its documentation.
@MainActor
final class TrackingOperationQueue {
  private var tail: Task<Void, Never>?

  @discardableResult
  func submit(
    runWhenCancelled: Bool = false, _ operation: @escaping @MainActor () async -> Void
  ) -> Task<Void, Never> {
    let previous = tail
    let task = Task {
      await previous?.value
      guard !Task.isCancelled || runWhenCancelled else { return }
      await operation()
    }
    tail = task
    return task
  }

  func run(_ operation: @escaping @MainActor () async -> Void) async {
    let task = submit(operation)
    await withTaskCancellationHandler {
      await task.value
    } onCancel: {
      task.cancel()
    }
  }
}
