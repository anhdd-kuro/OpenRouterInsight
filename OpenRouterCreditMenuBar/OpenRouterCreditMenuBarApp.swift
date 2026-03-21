//
//  OpenRouterCreditMenuBarApp.swift
//  OpenRouterCreditMenuBar
//
//  Created by Kittithat Patepakorn on 24/5/2568 BE.
//

import SwiftUI
import Combine
import AppKit

extension Notification.Name {
    static let openSettingsRequested = Notification.Name("openSettingsRequested")
}

@main
struct OpenRouterCreditMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appDelegate.creditManager)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    var settingsWindow: NSWindow?
    @Published var creditManager = OpenRouterCreditManager()
    private var cancellables = Set<AnyCancellable>()
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?
    private let popoverWidth: CGFloat = 400

    private var popoverHeight: CGFloat {
        let visibleHeight = NSScreen.main?.visibleFrame.height ?? 900
        return visibleHeight * 0.8
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let appIcon = NSImage(named: "AppIcon") {
            NSApplication.shared.applicationIconImage = appIcon
        }

        NSApp.setActivationPolicy(.accessory)

        if let mainWindow = NSApp.windows.first(where: { $0.title.isEmpty }) {
            mainWindow.close()
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let statusButton = statusItem?.button {
            statusButton.title = "Loading..."
            statusButton.image = makeStatusIcon()
            statusButton.imagePosition = .imageLeading
            statusButton.action = #selector(showMenu)
            statusButton.target = self
        }

        creditManager.$currentCredit
            .combineLatest(creditManager.$apiKeyUsages, creditManager.$errorMessage, creditManager.$isLoading)
            .sink { [weak self] _, _, _, _ in
                self?.updateMenuBarTitle()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .openSettingsRequested)
            .sink { [weak self] _ in
                self?.openSettingsWindow()
            }
            .store(in: &cancellables)

        popover = NSPopover()
        popover?.contentSize = NSSize(width: popoverWidth, height: popoverHeight)
        popover?.contentViewController = NSHostingController(
            rootView: MenuBarView()
                .environmentObject(creditManager)
        )
        popover?.behavior = .transient

        Task {
            await creditManager.fetchCredit(showLoadingText: false)
            await MainActor.run {
                updateMenuBarTitle()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        creditManager.stopMonitoring()
    }

    @objc func showMenu() {
        if let statusButton = statusItem?.button {
            if popover?.isShown == true {
                popover?.performClose(nil)
                stopOutsideClickMonitoring()
            } else {
                // Recreate the content view to ensure fresh SwiftUI lifecycle
                popover?.contentViewController = NSHostingController(
                    rootView: MenuBarView()
                        .environmentObject(creditManager)
                )
                popover?.show(
                    relativeTo: statusButton.bounds, of: statusButton, preferredEdge: .minY)
                startOutsideClickMonitoring()
            }
        }
    }

    @objc func openSettingsWindow() {
        if settingsWindow == nil {
            let settingsView = SettingsView()
                .environmentObject(creditManager)
            let hostingController = NSHostingController(rootView: settingsView)

            let window = NSWindow(contentViewController: hostingController)
            window.title = "Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.setContentSize(NSSize(width: 420, height: 460))
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }

        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func updateMenuBarTitle() {
        statusItem?.button?.image = makeStatusIcon()

        if creditManager.isLoading {
            setStatusTitle("Loading...", showWarning: false)
            return
        }

        if creditManager.apiKey.isEmpty {
            setStatusTitle("Set API Key", showWarning: false)
            return
        }

        if !creditManager.isEnabled {
            setStatusTitle("Paused", showWarning: false)
            return
        }

        if let credit = creditManager.currentCredit {
            setStatusTitle("$\(String(format: "%.2f", credit))", showWarning: creditManager.isNearWarningPoint)
        } else if creditManager.errorMessage != nil {
            setStatusTitle("Error", showWarning: creditManager.isNearWarningPoint)
        } else {
            setStatusTitle("--", showWarning: creditManager.isNearWarningPoint)
        }
    }

    private func makeStatusIcon() -> NSImage? {
        if let assetImage = NSImage(named: "OpenRouterStatusIcon") {
            let icon = assetImage.copy() as? NSImage
            icon?.size = NSSize(width: 16, height: 16)
            icon?.isTemplate = false
            return icon
        }

        let fallbackImage = NSImage(systemSymbolName: "network", accessibilityDescription: "OpenRouter")
        fallbackImage?.isTemplate = true
        return fallbackImage
    }

    private func setStatusTitle(_ text: String, showWarning: Bool) {
        guard let button = statusItem?.button else { return }
        _ = showWarning
        button.title = text
        button.attributedTitle = NSAttributedString(string: text)
    }

    private func startOutsideClickMonitoring() {
        stopOutsideClickMonitoring()

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            DispatchQueue.main.async {
                self?.closePopoverIfNeeded()
            }
        }

        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.closePopoverIfNeeded(using: event)
            return event
        }
    }

    private func stopOutsideClickMonitoring() {
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }

        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }
    }

    private func closePopoverIfNeeded(using event: NSEvent? = nil) {
        guard popover?.isShown == true else { return }

        let clickPoint: NSPoint

        if let event {
            clickPoint = event.locationInWindow

            if let popoverWindow = popover?.contentViewController?.view.window,
               event.window === popoverWindow
            {
                return
            }

            if let statusWindow = statusItem?.button?.window,
               event.window === statusWindow
            {
                return
            }
        } else {
            clickPoint = NSEvent.mouseLocation
        }

        if let popoverWindow = popover?.contentViewController?.view.window,
           popoverWindow.frame.contains(clickPoint)
        {
            return
        }

        popover?.performClose(nil)
        stopOutsideClickMonitoring()
    }
}
