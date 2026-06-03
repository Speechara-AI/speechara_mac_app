import Foundation

@MainActor
final class SpeecharaUpdateController: ObservableObject {
    static let shared = SpeecharaUpdateController()

    @Published private(set) var availableUpdateDisplayVersion: String?

    var isUpdateAvailable: Bool {
        false
    }

    private init() {}

    func activate() {}
    func checkForUpdates() {}
    func refreshUpdateAvailability() {}
}
