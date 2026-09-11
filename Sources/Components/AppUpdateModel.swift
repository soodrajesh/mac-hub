import SwiftUI

/// Owns the launch-time "is a newer MacHub available?" check as its own
/// small `@StateObject`, living for the app's lifetime on `MacHubApp` —
/// mirrors mac-groom's `SweepModel.availableUpdate` /
/// `SweepModel.checkForUpdates()`, just split into its own model since
/// MacHub has no single app-lifetime model of its own to attach this to.
@MainActor
final class AppUpdateModel: ObservableObject {
    /// Set once a launch-time (or manual, from Settings) update check
    /// finds a newer version than this build — `nil` means "none found,"
    /// which covers both "already latest" and "check failed/offline,"
    /// identically silent either way (see `checkForUpdates()`).
    @Published var availableUpdate: UpdateManifest?

    /// Runs once at launch (silently — no failure UI, no "you're up to
    /// date" toast) and on demand from Settings' "Check for Updates"
    /// button. Network failure and "already latest" both just leave
    /// `availableUpdate` at `nil`; there's nothing meaningfully different
    /// to tell the user between those two cases.
    func checkForUpdates() {
        Task.detached(priority: .background) { [weak self] in
            let manifest = await UpdateCheckService.checkForUpdate()
            guard let self else { return }
            await MainActor.run { self.availableUpdate = manifest }
        }
    }
}
