import UIKit

/// Time to finish something if the app leaves the screen meanwhile: iOS holds off suspending the app until
/// `end()`, or takes the time back itself after about 30 seconds. Held around each write of the saved library.
final class BackgroundTime {
    private var id = UIBackgroundTaskIdentifier.invalid

    init(_ name: String) {
        id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in self?.end() }
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}
