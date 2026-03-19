//
//  NotchViewModel.swift
//  newNotch
//
//  Created by Emre Can Akisik on 19/03/2026.
//

import SwiftUI
import Combine

// MARK: - NotchState

enum NotchState {
    case idle
    case mediaExpanded
    case mediaCollapsed
    case mediaPausing      // Müzik durdu ama henüz kapanmıyor (2 sn grace period)
    case progress
    case notification
}

// MARK: - NotchViewModel

class NotchViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var currentState: NotchState = .idle
    @Published var mediaInfo: MediaInfo?
    
    // MARK: - Managers
    
    let mediaManager = MediaManager()
    
    // MARK: - Private
    
    private var cancellables = Set<AnyCancellable>()
    private var collapseTask: DispatchWorkItem?
    private var pauseDismissTask: DispatchWorkItem?
    
    /// Son alınan şarkı title'ı
    private var lastTrackTitle: String?
    
    /// Son bilinen isPlaying durumu (false→true geçişini algılamak için)
    private var wasPlaying: Bool = false
    
    private let collapseDelay: TimeInterval = 3.0
    private let pauseDismissDelay: TimeInterval = 2.0
    
    // MARK: - Computed Sizes
    
    var notchWidth: CGFloat {
        switch currentState {
        case .idle:             return 160
        case .mediaExpanded:    return 300
        case .mediaCollapsed:   return 260
        case .mediaPausing:     return 260
        case .progress:         return 280
        case .notification:     return 360
        }
    }
    
    var notchHeight: CGFloat {
        switch currentState {
        case .idle:             return 32
        case .mediaExpanded:    return 48
        case .mediaCollapsed:   return 32
        case .mediaPausing:     return 32
        case .progress:         return 40
        case .notification:     return 56
        }
    }
    
    // MARK: - Init
    
    init() {
        bindMediaManager()
    }
    
    // MARK: - Bindings
    
    private func bindMediaManager() {
        mediaManager.$mediaInfo
            .receive(on: DispatchQueue.main)
            .sink { [weak self] info in
                guard let self = self else { return }
                
                DispatchQueue.main.async {
                    self.handleMediaUpdate(info)
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Media State Machine
    
    private func handleMediaUpdate(_ info: MediaInfo?) {
        let previousInfo = self.mediaInfo
        self.mediaInfo = info
        
        guard let info = info else {
            // Medya tamamen yok → direkt kapat
            cancelAllTimers()
            wasPlaying = false
            if currentState != .idle {
                currentState = .idle
            }
            lastTrackTitle = nil
            return
        }
        
        let trackChanged = (info.title != lastTrackTitle)
        let playResumed = (info.isPlaying && !wasPlaying)   // false → true geçişi
        
        lastTrackTitle = info.title
        wasPlaying = info.isPlaying
        
        if info.isPlaying {
            // ▶ Müzik çalıyor
            cancelPauseDismissTimer()
            
            // Uyanma koşulları: şarkı değişti VEYA play resume edildi
            let shouldWake = trackChanged || playResumed
            
            if shouldWake {
                wakeUpNotch()
            } else {
                // Aynı şarkı, zaten çalıyor — mevcut state'i koru
                // (expanded ise expanded, collapsed ise collapsed kalsın)
            }
        } else {
            // ⏸ Müzik duraklatıldı → mediaPausing state'e geç
            cancelCollapseTimer()
            
            switch currentState {
            case .mediaExpanded, .mediaCollapsed:
                currentState = .mediaPausing
                startPauseDismissTimer()
            case .mediaPausing:
                // Zaten pausing'deyiz, timer devam etsin
                break
            default:
                break
            }
        }
    }
    
    // MARK: - Wake Up (Her türlü durumdan → mediaExpanded → 3 sn → mediaCollapsed)
    
    /// Çentiği uyandırır: expanded'a geçer, 3 saniye sonra collapsed'a döner.
    /// Şarkı değişikliği veya play resume'da çağrılır.
    func wakeUpNotch() {
        cancelAllTimers()
        currentState = .mediaExpanded
        startCollapseTimer()
    }
    
    // MARK: - Collapse Timer (expanded → collapsed, 3 sn)
    
    private func startCollapseTimer() {
        cancelCollapseTimer()
        
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            if self.currentState == .mediaExpanded {
                self.currentState = .mediaCollapsed
            }
        }
        collapseTask = work
        DispatchQueue.main.asyncAfter(deadline: .now() + collapseDelay, execute: work)
    }
    
    private func cancelCollapseTimer() {
        collapseTask?.cancel()
        collapseTask = nil
    }
    
    // MARK: - Pause Dismiss Timer (mediaPausing → idle, 2 sn)
    
    private func startPauseDismissTimer() {
        cancelPauseDismissTimer()
        
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            if self.currentState == .mediaPausing {
                self.currentState = .idle
            }
        }
        pauseDismissTask = work
        DispatchQueue.main.asyncAfter(deadline: .now() + pauseDismissDelay, execute: work)
    }
    
    private func cancelPauseDismissTimer() {
        pauseDismissTask?.cancel()
        pauseDismissTask = nil
    }
    
    private func cancelAllTimers() {
        cancelCollapseTimer()
        cancelPauseDismissTimer()
    }
    
    // MARK: - Actions
    
    func togglePlayPause() {
        mediaManager.togglePlayPause()
    }
}
