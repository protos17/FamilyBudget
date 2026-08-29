import Foundation
import Testing

/// Polls `condition` until it becomes true or `timeout` elapses.
/// Needed because some ViewModel methods fire off detached `Task { }` work
/// (or `DispatchQueue.main.async`) and return before it completes.
@MainActor
func waitUntil(
    timeout: Duration = .seconds(2),
    pollInterval: Duration = .milliseconds(10),
    _ condition: @MainActor () -> Bool
) async {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while !condition() {
        if ContinuousClock.now >= deadline {
            Issue.record("Timed out waiting for condition")
            return
        }
        try? await Task.sleep(for: pollInterval)
    }
}
