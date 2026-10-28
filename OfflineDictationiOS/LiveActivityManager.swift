import ActivityKit
import Foundation

// Shows the microphone state in the Dynamic Island and on the lock screen: ready, recording (with a
// stopwatch), or transcribing. It lasts while the mic is being kept ready, and ends when it is turned off.
@MainActor
final class LiveActivityManager {
    typealias Phase = DictationActivityAttributes.ContentState.Phase

    private var activity: Activity<DictationActivityAttributes>?
    private var startedAt = Date()
    private var phase: Phase = .standby

    // If the app is killed without a chance to end the activity, it goes "stale" after this long and shows
    // "Mic off" instead of claiming the mic is still ready. The app refreshes it while it is alive.
    private static let staleAfter: TimeInterval = 45

    // A previous run may have been force-quit while its activity was showing. Call once at launch, before
    // this run creates its own, to clear anything left over.
    static func endLeftovers() {
        let leftovers = Activity<DictationActivityAttributes>.activities
        guard !leftovers.isEmpty else { return }
        Task { for old in leftovers { await old.end(nil, dismissalPolicy: .immediate) } }
    }

    private func content() -> ActivityContent<DictationActivityAttributes.ContentState> {
        ActivityContent(
            state: DictationActivityAttributes.ContentState(startedAt: startedAt, phase: phase),
            staleDate: Date().addingTimeInterval(Self.staleAfter)
        )
    }

    func show(_ phase: Phase, startedAt newStart: Date? = nil) {
        self.phase = phase
        if let newStart { startedAt = newStart }

        if let activity {
            let update = content()
            Task { await activity.update(update) }
        } else if ActivityAuthorizationInfo().areActivitiesEnabled {
            // A Live Activity can only be created while the app is in the foreground; updating one works anywhere.
            activity = try? Activity.request(attributes: DictationActivityAttributes(), content: content())
        }
    }

    // Pushes the stale date forward. Called regularly while the app is alive.
    func refresh() {
        guard let activity else { return }
        let update = content()
        Task { await activity.update(update) }
    }

    func end() {
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    // For when the app is about to be terminated: waits briefly so the request isn't lost.
    func endNow(timeout: TimeInterval = 1.5) {
        guard let activity else { return }
        self.activity = nil
        let finished = DispatchSemaphore(value: 0)
        Task.detached {
            await activity.end(nil, dismissalPolicy: .immediate)
            finished.signal()
        }
        _ = finished.wait(timeout: .now() + timeout)
    }
}
