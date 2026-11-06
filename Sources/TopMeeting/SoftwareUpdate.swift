#if canImport(Sparkle)
import SwiftUI
import Sparkle

@MainActor final class SoftwareUpdate: NSObject, ObservableObject, SPUUpdaterDelegate {
    private weak var store: MeetingStore?
    private var controller: SPUStandardUpdaterController?
    @Published private(set) var canCheck = false

    func start(store: MeetingStore) {
        guard controller == nil else { return }
        self.store = store
        let controller = SPUStandardUpdaterController(startingUpdater:false, updaterDelegate:self, userDriverDelegate:nil)
        self.controller = controller
        controller.updater.publisher(for:\.canCheckForUpdates).assign(to:&$canCheck)
        controller.startUpdater()
    }

    func check() { controller?.checkForUpdates(nil) }

    func updaterShouldRelaunchApplication(_ updater: SPUUpdater) -> Bool {
        store?.canRestartForUpdate == true
    }
}
#endif
