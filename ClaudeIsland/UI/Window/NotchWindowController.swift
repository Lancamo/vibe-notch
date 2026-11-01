//
//  NotchWindowController.swift
//  ClaudeIsland
//
//  Controls the notch window positioning and lifecycle
//

import AppKit
import Combine
import SwiftUI

class NotchWindowController: NSWindowController {
    let viewModel: NotchViewModel
    private let screen: NSScreen
    private var cancellables = Set<AnyCancellable>()
    /// Set once the pointer has deliberately reached the notch after an auto-open.
    private var autoOpenInteractive = false

    init(screen: NSScreen, animateOnLaunch: Bool = true) {
        self.screen = screen

        let screenFrame = screen.frame
        let notchSize = screen.notchSize

        // Window covers full width at top, tall enough for largest content (chat view)
        let windowHeight: CGFloat = 750
        let windowFrame = NSRect(
            x: screenFrame.origin.x,
            y: screenFrame.maxY - windowHeight,
            width: screenFrame.width,
            height: windowHeight
        )

        // Device notch rect - positioned at center
        let deviceNotchRect = CGRect(
            x: (screenFrame.width - notchSize.width) / 2,
            y: 0,
            width: notchSize.width,
            height: notchSize.height
        )

        // Create view model
        self.viewModel = NotchViewModel(
            deviceNotchRect: deviceNotchRect,
            screenRect: screenFrame,
            windowHeight: windowHeight,
            hasPhysicalNotch: screen.hasPhysicalNotch
        )

        // Create the window
        let notchWindow = NotchPanel(
            contentRect: windowFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        super.init(window: notchWindow)

        // Create the SwiftUI view with pass-through hosting
        let hostingController = NotchViewController(viewModel: viewModel)
        notchWindow.contentViewController = hostingController

        notchWindow.setFrame(windowFrame, display: true)

        // Dynamically toggle mouse event handling based on notch state:
        // - Closed: ignoresMouseEvents = true (clicks pass through to menu bar/apps)
        // - Opened deliberately (click/hover): buttons work while the pointer is over the panel
        // - Opened automatically (notification/permission): stays click-through until the
        //   pointer is moved onto the notch, so a pop-up never takes over the mouse
        viewModel.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateMouseInteractivity() }
            .store(in: &cancellables)

        viewModel.$isHovering
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateMouseInteractivity() }
            .store(in: &cancellables)

        viewModel.$isPointerInNotch
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateMouseInteractivity() }
            .store(in: &cancellables)

        // Start with ignoring mouse events (closed state)
        notchWindow.ignoresMouseEvents = true

        // Perform boot animation after a brief delay (only on initial launch)
        if animateOnLaunch {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.viewModel.performBootAnimation()
            }
        }
    }

    private func updateMouseInteractivity() {
        guard let window = self.window else { return }

        let inNotch = viewModel.isPointerInNotch
        let inPanel = viewModel.isHovering

        switch viewModel.status {
        case .closed, .popping:
            autoOpenInteractive = false
            window.ignoresMouseEvents = true

        case .opened:
            let deliberate = viewModel.openReason == .click || viewModel.openReason == .hover
            if deliberate {
                window.ignoresMouseEvents = !(inNotch || inPanel)
            } else {
                // Auto-opened (notification / permission prompt). Stay click-through
                // so the pop-up cannot take the mouse from the app in use. The panel
                // becomes interactive only after the pointer deliberately reaches
                // the notch, and stays so while the pointer is on the panel.
                if !autoOpenInteractive && inNotch {
                    autoOpenInteractive = true
                }
                if autoOpenInteractive && !inNotch && !inPanel {
                    autoOpenInteractive = false
                }
                window.ignoresMouseEvents = !autoOpenInteractive
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
