import Foundation
import Sparkle

@MainActor
final class SpeecharaUpdateController: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = SpeecharaUpdateController()

    @Published private(set) var availableUpdateDisplayVersion: String?

    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: self,
        userDriverDelegate: nil
    )

    private var didScheduleStartupRefresh = false

    var isUpdateAvailable: Bool {
        availableUpdateDisplayVersion != nil
    }

    private override init() {
        super.init()
    }

    func activate() {
        _ = updaterController
        refreshUpdateAvailability()

        guard !didScheduleStartupRefresh else { return }
        didScheduleStartupRefresh = true

        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            self?.refreshUpdateAvailability()
        }
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    func refreshUpdateAvailability() {
        guard updaterController.updater.canCheckForUpdates else { return }
        updaterController.updater.checkForUpdateInformation()
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        availableUpdateDisplayVersion = item.displayVersionString
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        availableUpdateDisplayVersion = nil
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        availableUpdateDisplayVersion = nil
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: Error?
    ) {
        if error != nil {
            availableUpdateDisplayVersion = nil
        }
    }
}
