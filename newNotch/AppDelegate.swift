//
//  AppDelegate.swift
//  newNotch
//
//  Created by Emre Can Akisik on 19/03/2026.
//

import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    
    // MARK: - Properties
    
    private var panel: NSPanel!
    
    // MARK: - Lifecycle
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupPanel()
    }
    
    // MARK: - Panel Setup
    
    private func setupPanel() {
        
        // Ana ekranı al
        guard let screen = NSScreen.main else { return }
        
        // Panel boyutları (en büyük state olan notification'a göre ayarlanmış)
        let panelWidth: CGFloat = 400
        let panelHeight: CGFloat = 70
        
        // Ekranın üst ortasına konumlandır
        let originX = screen.frame.midX - (panelWidth / 2)
        let originY = screen.frame.maxY - panelHeight
        
        let panelRect = NSRect(
            x: originX,
            y: originY,
            width: panelWidth,
            height: panelHeight
        )
        
        // NSPanel: borderless + nonactivatingPanel
        panel = NSPanel(
            contentRect: panelRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        // Şeffaf arka plan, gölge yok
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        
        // Tüm pencerelerin üstünde (statusBar seviyesi)
        panel.level = .statusBar
        
        // Tüm masaüstlerinde ve fullscreen modda görünür
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        // Fare olaylarını taşımasın, arkasına tıklamayı engellemesin
        panel.isMovableByWindowBackground = false
        panel.ignoresMouseEvents = false
        
        // SwiftUI view'ı barındır
        let hostingView = NSHostingView(rootView: NotchView())
        panel.contentView = hostingView
        
        // Paneli göster
        panel.orderFrontRegardless()
    }
}
