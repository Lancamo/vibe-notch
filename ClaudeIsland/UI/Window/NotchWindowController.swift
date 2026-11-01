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
    private var wasHovering = false
    private var lastStatus: NotchStatus = .closed

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

        let hovering = viewModel.isHovering
        let inNotch = viewModel.isPointerInNotch

        if viewModel.status == .opened && lastStatus != .opened {
            // If the panel appeared under the pointer, that pointer position is
            // not intent. Wait for it to leave and come back, or reach the notch.
            let point = NSEvent.mouseLocation
            let appearedUnderPointer = viewModel.geometry.isPointInNotch(point)
                || viewModel.geometry.isPointInOpenedPanel(point, size: viewModel.openedSize)
            wasHovering = appearedUnderPointer || hovering
            autoOpenInteractive = false
        }
        lastStatus = viewModel.status

        switch viewModel.status {
        case .closed, .popping:
            autoOpenInteractive = false
            window.ignoresMouseEvents = true

        case .opened:
            let deliberate = viewModel.openReason == .click || viewModel.openReason == .hover
            if deliberate {
                window.ignoresMouseEvents = !hovering
            } else {
                // Auto-opened (task finished / confirmation). Stay click-through
                // so the pop-up cannot take the mouse from the app in use. It
                // becomes interactive when the pointer reaches the notch or
                // enters the panel from outside after the pop.
                if !autoOpenInteractive && (inNotch || (hovering && !wasHovering)) {
                    autoOpenInteractive = true
                }
                if autoOpenInteractive && !hovering {
                    autoOpenInteractive = false
                }
                window.ignoresMouseEvents = !autoOpenInteractive
            }
        }

        wasHovering = hovering
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
