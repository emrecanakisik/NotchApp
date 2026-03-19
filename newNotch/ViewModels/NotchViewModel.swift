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
    case mediaPausing         // Müzik durdu ama henüz kapanmıyor (2 sn grace period)
    case mediaPlayerActive    // Tam açık interaktif player (tıklama ile)
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
    private var playerDismissTask: DispatchWorkItem?
    
    private var lastTrackTitle: String?
    private var wasPlaying: Bool = false
    
    private let collapseDelay: TimeInterval = 3.0
    private let pauseDismissDelay: TimeInterval = 2.0
    private let playerAutoCloseDelay: TimeInterval = 8.0
    
    // MARK: - Computed Sizes
    
    var notchWidth: CGFloat {
        switch currentState {
        case .idle:               return 160
        case .mediaExpanded:      return 300
        case .mediaCollapsed:     return 260
        case .mediaPausing:       return 260
        case .mediaPlayerActive:  return 340
        case .progress:           return 280
        case .notification:       return 360
        }
    }
    
    var notchHeight: CGFloat {
        switch currentState {
        case .idle:               return 32
        case .mediaExpanded:      return 48
        case .mediaCollapsed:     return 32
        case .mediaPausing:       return 32
        case .mediaPlayerActive:  return 140
        case .progress:           return 40
        case .notification:       return 56
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
        self.mediaInfo = info
        
        guard let info = info else {
            cancelAllTimers()
            wasPlaying = false
            if currentState != .idle {
                currentState = .idle
            }
            lastTrackTitle = nil
            return
        }
        
        let trackChanged = (info.title != lastTrackTitle)
        let playResumed = (info.isPlaying && !wasPlaying)
        
        lastTrackTitle = info.title
        wasPlaying = info.isPlaying
        
        if info.isPlaying {
            cancelPauseDismissTimer()
            
            // mediaPlayerActive açıkken state değiştirme — sadece veriyi güncelle
            if currentState == .mediaPlayerActive {
                if trackChanged {
                    // Şarkı değişti — player açık kalsın, auto-close timer sıfırla
                    resetPlayerAutoCloseTimer()
                }
                return
            }
            
            let shouldWake = trackChanged || playResumed
            
            if shouldWake {
                wakeUpNotch()
            }
        } else {
            // ⏸ Müzik duraklatıldı
            cancelCollapseTimer()
            
            // Player açıksa açık kalsın (kullanıcı bilerek açtı)
            if currentState == .mediaPlayerActive {
                return
            }
            
            switch currentState {
            case .mediaExpanded, .mediaCollapsed:
                currentState = .mediaPausing
                startPauseDismissTimer()
            case .mediaPausing:
                break
            default:
                break
            }
        }
    }
    
    // MARK: - Wake Up
    
    func wakeUpNotch() {
        cancelAllTimers()
        currentState = .mediaExpanded
        startCollapseTimer()
    }
    
    // MARK: - Open Player (collapsed tıklama → tam player)
    
    func openMediaPlayer() {
        guard mediaInfo != nil else { return }
        cancelAllTimers()
        currentState = .mediaPlayerActive
        startPlayerAutoCloseTimer()
    }
    
    /// Player'ı kapat → collapsed'a dön
    func closeMediaPlayer() {
        cancelPlayerAutoCloseTimer()
        if mediaInfo?.isPlaying == true {
            currentState = .mediaCollapsed
        } else {
            currentState = .mediaPausing
            startPauseDismissTimer()
        }
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
    
    // MARK: - Player Auto-Close Timer (8 sn etkileşim yoksa kapat)
    
    private func startPlayerAutoCloseTimer() {
        cancelPlayerAutoCloseTimer()
        
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            if self.currentState == .mediaPlayerActive {
                self.closeMediaPlayer()
            }
        }
        playerDismissTask = work
        DispatchQueue.main.asyncAfter(deadline: .now() + playerAutoCloseDelay, execute: work)
    }
    
    func resetPlayerAutoCloseTimer() {
        startPlayerAutoCloseTimer()
    }
    
    private func cancelPlayerAutoCloseTimer() {
        playerDismissTask?.cancel()
        playerDismissTask = nil
    }
    
    private func cancelAllTimers() {
        cancelCollapseTimer()
        cancelPauseDismissTimer()
        cancelPlayerAutoCloseTimer()
    }
    
    // MARK: - Media Control Actions
    
    func togglePlayPause() {
        mediaManager.togglePlayPause()
        resetPlayerAutoCloseTimer()
    }
    
    func nextTrack() {
        mediaManager.nextTrack()
        resetPlayerAutoCloseTimer()
    }
    
    func previousTrack() {
        mediaManager.previousTrack()
        resetPlayerAutoCloseTimer()
    }
    
    func skipForward() {
        mediaManager.skipForward(seconds: 10)
        resetPlayerAutoCloseTimer()
    }
    
    func skipBackward() {
        mediaManager.skipBackward(seconds: 10)
        resetPlayerAutoCloseTimer()
    }
}
