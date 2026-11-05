import AppKit
import Combine
import Sparkle

/// One updater for the application's lifetime. Command-line tests never start it.
@MainActor final class AppUpdater: ObservableObject {
    static let shared = AppUpdater()
    @Published private(set) var canCheck = false
    @Published private(set) var automaticChecks = false
    private let controller: SPUStandardUpdaterController?
    let configured: Bool

    private init() {
        let info = Bundle.main.infoDictionary ?? [:]
        let feed = (info["SUFeedURL"] as? String).flatMap(URL.init(string:))
        let key = (info["SUPublicEDKey"] as? String).flatMap { Data(base64Encoded: $0) }
        configured = Bundle.main.bundleURL.pathExtension == "app" && feed?.scheme == "https" && feed?.host != nil && key?.count == 32
        guard configured else { controller = nil; return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main).assign(to: &$canCheck)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates)
            .receive(on: RunLoop.main).assign(to: &$automaticChecks)
        controller.startUpdater()
    }

    func check() { controller?.checkForUpdates(nil) }
    func setAutomaticChecks(_ enabled: Bool) { controller?.updater.automaticallyChecksForUpdates = enabled }
}
