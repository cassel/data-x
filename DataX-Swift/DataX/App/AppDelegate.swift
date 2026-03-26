import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var didFinishLaunching = false
    private var appState: AppState?
    private var finderServicesProvider: FinderServicesProvider?

    func configure(appState: AppState) {
        self.appState = appState
        registerFinderServicesProviderIfNeeded()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        didFinishLaunching = true
        registerFinderServicesProviderIfNeeded()
    }

    private func registerFinderServicesProviderIfNeeded() {
        guard didFinishLaunching, let appState, finderServicesProvider == nil else { return }

        let provider = FinderServicesProvider { directory in
            appState.handleFinderServiceDirectory(directory)
        }

        finderServicesProvider = provider
        NSApp.servicesProvider = provider
    }
}
