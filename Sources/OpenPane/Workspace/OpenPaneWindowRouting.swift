import AppKit
import SwiftUI

@MainActor
final class OpenPaneWindowRegistry {
    static let shared = OpenPaneWindowRegistry()

    private final class Registration {
        weak var window: NSWindow?
        weak var store: WorkspaceStore?
        let delegateProxy: WorkspaceWindowDelegateProxy
        var openWindow: (WorkspaceLaunch) -> Void

        init(
            window: NSWindow,
            store: WorkspaceStore,
            delegateProxy: WorkspaceWindowDelegateProxy,
            openWindow: @escaping (WorkspaceLaunch) -> Void
        ) {
            self.window = window
            self.store = store
            self.delegateProxy = delegateProxy
            self.openWindow = openWindow
        }
    }

    private var registrations: [Registration] = []
    private var pendingURLs: [URL] = []
    private var isTerminationDecisionPending = false

    private init() {}

    func register(
        window: NSWindow,
        store: WorkspaceStore,
        openWindow: @escaping (WorkspaceLaunch) -> Void
    ) {
        prune()
        let registration: Registration
        if let existing = registrations.first(
            where: { $0.window === window }
        ) {
            existing.store = store
            existing.openWindow = openWindow
            existing.delegateProxy.store = store
            existing.delegateProxy.installIfNeeded()
            registration = existing
        } else {
            let proxy = WorkspaceWindowDelegateProxy(
                window: window,
                store: store
            )
            proxy.onWindowClosed = { [weak self, weak window] in
                guard let self, let window else { return }
                self.unregister(window: window)
            }
            registration = Registration(
                window: window,
                store: store,
                delegateProxy: proxy,
                openWindow: openWindow
            )
            registrations.append(registration)
            proxy.installIfNeeded()
        }

        guard !pendingURLs.isEmpty else { return }
        let urls = pendingURLs
        pendingURLs = []
        registrationDidResolve(registration, pendingURLs: urls)
    }

    func unregister(store: WorkspaceStore) {
        let removed = registrations.filter {
            $0.window == nil || $0.store == nil || $0.store === store
        }
        registrations.removeAll {
            $0.window == nil || $0.store == nil || $0.store === store
        }
        for registration in removed {
            registration.delegateProxy.uninstallIfNeeded()
        }
    }

    func route(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        prune()

        var unopenedURLs: [URL] = []
        for url in urls {
            if !activateIfOpen(url) {
                unopenedURLs.append(url)
            }
        }
        guard !unopenedURLs.isEmpty else { return }

        let keyWindow = NSApp.keyWindow
        let target = registrations.first(where: {
            keyWindow != nil && $0.window === keyWindow
        }) ?? registrations.first

        routeUnopenedURLs(unopenedURLs, preferred: target)
    }

    @discardableResult
    func activateIfOpen(_ url: URL) -> Bool {
        prune()
        let canonicalURL = url.standardizedFileURL
        guard let existing = registrations.first(where: {
            $0.store?.activateOpenFile(canonicalURL) == true
        }) else {
            return false
        }
        existing.window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
        return true
    }

    func applicationShouldTerminate(
        _ application: NSApplication
    ) -> NSApplication.TerminateReply {
        prune()
        let stores = uniqueStores().filter { $0.documents.hasDirtySessions }
        guard !stores.isEmpty else {
            return .terminateNow
        }
        guard !isTerminationDecisionPending else {
            return .terminateLater
        }

        isTerminationDecisionPending = true
        Task { @MainActor [weak self, weak application] in
            guard let self, let application else { return }
            let shouldTerminate = await self.resolveApplicationTermination(
                stores: stores
            )
            self.isTerminationDecisionPending = false
            application.reply(toApplicationShouldTerminate: shouldTerminate)
        }
        return .terminateLater
    }

    private func resolveApplicationTermination(
        stores: [WorkspaceStore]
    ) async -> Bool {
        do {
            for store in stores {
                try await store.documents.flushRecoverySnapshots()
            }
        } catch {
            stores.first?.operationError =
                "OpenPane kept the app open because recovery failed: "
                + error.localizedDescription
            return false
        }

        let dirtyCount = stores.reduce(0) {
            $0 + $1.documents.dirtySessions.count
        }
        let decision = await WorkspaceClosePrompt.present(
            on: NSApp.keyWindow
                ?? registrations.compactMap(\.window).first,
            title: "Save Changes Before Quitting?",
            message: dirtyCount == 1
                ? "One file has unsaved changes. A recovery copy has been written."
                : "\(dirtyCount) files have unsaved changes. Recovery copies have been written."
        )

        do {
            switch decision {
            case .saveAll:
                for store in stores {
                    try await store.documents.saveAllDirtySessions()
                }
                return true
            case .discard:
                for store in stores {
                    try await store.documents.discardAllDirtySessionsForClosing()
                }
                return true
            case .cancel:
                return false
            }
        } catch {
            stores.first?.operationError =
                "OpenPane kept the app open: " + error.localizedDescription
            return false
        }
    }

    private func unregister(window: NSWindow) {
        registrations.removeAll { $0.window == nil || $0.window === window }
    }

    private func registrationDidResolve(
        _ registration: Registration,
        pendingURLs: [URL]
    ) {
        guard !pendingURLs.isEmpty else { return }
        routeUnopenedURLs(pendingURLs, preferred: registration)
    }

    private func routeUnopenedURLs(
        _ urls: [URL],
        preferred registration: Registration?
    ) {
        guard !urls.isEmpty else { return }
        var remainingURLs = urls

        if let store = registration?.store,
           store.canAcceptExternalOpenInCurrentWindow {
            store.handleExternalURLs([remainingURLs.removeFirst()])
        }

        guard !remainingURLs.isEmpty else { return }
        guard let openWindow = registration?.openWindow
            ?? registrations.first?.openWindow else {
            pendingURLs.append(contentsOf: remainingURLs)
            return
        }

        for url in remainingURLs {
            openWindow(Self.launch(for: url))
        }
    }

    private static func launch(for url: URL) -> WorkspaceLaunch {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(
            atPath: url.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue {
            return .folder(url)
        }
        return .file(url)
    }

    private func uniqueStores() -> [WorkspaceStore] {
        var identifiers: Set<ObjectIdentifier> = []
        return registrations.compactMap(\.store).filter { store in
            identifiers.insert(ObjectIdentifier(store)).inserted
        }
    }

    private func prune() {
        registrations.removeAll { $0.window == nil || $0.store == nil }
    }
}

@MainActor
private final class WorkspaceWindowDelegateProxy: NSObject, NSWindowDelegate {
    weak var store: WorkspaceStore?
    var onWindowClosed: (() -> Void)?

    private weak var window: NSWindow?
    // NSObject message forwarding is nonisolated even though AppKit window
    // delegate delivery is main-thread-only. Keep this one weak forwarding
    // reference explicitly unsafe so Swift 6 does not infer a cross-actor
    // access while preserving SwiftUI's delegate callbacks.
    nonisolated(unsafe) private weak var forwardedDelegate: NSWindowDelegate?
    private var isPresentingCloseDecision = false
    private var isAuthorizedToClose = false

    init(window: NSWindow, store: WorkspaceStore) {
        self.window = window
        self.store = store
        forwardedDelegate = window.delegate
        super.init()
    }

    func installIfNeeded() {
        guard let window, window.delegate !== self else { return }
        if window.delegate != nil {
            forwardedDelegate = window.delegate
        }
        window.delegate = self
    }

    func uninstallIfNeeded() {
        guard let window, window.delegate === self else { return }
        window.delegate = forwardedDelegate
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if let forwardedResult = forwardedDelegate?.windowShouldClose?(sender),
           !forwardedResult {
            return false
        }
        if isAuthorizedToClose {
            return true
        }
        guard let store, store.documents.hasDirtySessions else {
            return true
        }
        guard !isPresentingCloseDecision else {
            return false
        }

        isPresentingCloseDecision = true
        Task { @MainActor [weak self, weak sender] in
            guard let self, let sender else { return }
            await self.resolveWindowClose(sender, store: store)
        }
        return false
    }

    func windowWillClose(_ notification: Notification) {
        forwardedDelegate?.windowWillClose?(notification)
        onWindowClosed?()
    }

    private func resolveWindowClose(
        _ window: NSWindow,
        store: WorkspaceStore
    ) async {
        defer { isPresentingCloseDecision = false }

        do {
            try await store.documents.flushRecoverySnapshots()
        } catch {
            store.operationError =
                "OpenPane kept this window open because recovery failed: "
                + error.localizedDescription
            return
        }

        let dirtyCount = store.documents.dirtySessions.count
        let decision = await WorkspaceClosePrompt.present(
            on: window,
            title: "Save Changes Before Closing?",
            message: dirtyCount == 1
                ? "One file has unsaved changes. A recovery copy has been written."
                : "\(dirtyCount) files have unsaved changes. Recovery copies have been written."
        )

        do {
            switch decision {
            case .saveAll:
                try await store.documents.saveAllDirtySessions()
            case .discard:
                try await store.documents.discardAllDirtySessionsForClosing()
            case .cancel:
                return
            }
        } catch {
            store.operationError =
                "OpenPane kept this window open: " + error.localizedDescription
            return
        }

        isAuthorizedToClose = true
        window.performClose(nil)
    }

    override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector)
            || (forwardedDelegate?.responds(to: aSelector) ?? false)
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if forwardedDelegate?.responds(to: aSelector) == true {
            return forwardedDelegate
        }
        return super.forwardingTarget(for: aSelector)
    }
}

private enum WorkspaceCloseDecision {
    case saveAll
    case discard
    case cancel
}

@MainActor
private enum WorkspaceClosePrompt {
    static func present(
        on window: NSWindow?,
        title: String,
        message: String
    ) async -> WorkspaceCloseDecision {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Save All")
        alert.addButton(withTitle: "Discard Changes")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[1].hasDestructiveAction = true

        let response: NSApplication.ModalResponse
        if let window, window.isVisible {
            response = await withCheckedContinuation { continuation in
                alert.beginSheetModal(for: window) { result in
                    continuation.resume(returning: result)
                }
            }
        } else {
            response = alert.runModal()
        }

        return switch response {
        case .alertFirstButtonReturn:
            .saveAll
        case .alertSecondButtonReturn:
            .discard
        default:
            .cancel
        }
    }
}

final class OpenPaneAppDelegate: NSObject, NSApplicationDelegate {
    func application(
        _ application: NSApplication,
        open urls: [URL]
    ) {
        Task { @MainActor in
            OpenPaneWindowRegistry.shared.route(urls)
        }
    }

    func applicationShouldTerminate(
        _ sender: NSApplication
    ) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated {
            OpenPaneWindowRegistry.shared.applicationShouldTerminate(sender)
        }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        true
    }
}

struct WorkspaceWindowAccessor: NSViewRepresentable {
    let didResolveWindow: @MainActor (NSWindow) -> Void

    func makeNSView(context: Context) -> WindowResolvingView {
        WindowResolvingView { window in
            Task { @MainActor in
                didResolveWindow(window)
            }
        }
    }

    func updateNSView(_ nsView: WindowResolvingView, context: Context) {
        nsView.didResolveWindow = { window in
            Task { @MainActor in
                didResolveWindow(window)
            }
        }
        nsView.resolve()
    }
}

final class WindowResolvingView: NSView {
    var didResolveWindow: (NSWindow) -> Void
    private weak var resolvedWindow: NSWindow?

    init(didResolveWindow: @escaping (NSWindow) -> Void) {
        self.didResolveWindow = didResolveWindow
        super.init(frame: .zero)
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        resolve()
    }

    func resolve() {
        guard let window, resolvedWindow !== window else { return }
        resolvedWindow = window
        didResolveWindow(window)
    }
}
