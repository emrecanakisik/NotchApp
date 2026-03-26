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
    case idleExpanded         // Idle'dayken tıklama → son çalanı göster
    case mediaExpanded
    case mediaCollapsed
    case mediaPausing         // Müzik durdu ama henüz kapanmıyor (2 sn grace period)
    case mediaPlayerActive    // Tam açık interaktif player (tıklama ile)
    case multiMediaListActive // Çoklu medya mikser paneli
    case progress
    case notification
}

// MARK: - NotchViewModel

class NotchViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var currentState: NotchState = .idle
    @Published var mediaInfo: MediaInfo?
    @Published var lastKnownMedia: MediaInfo?
    @Published var activeMediaList: [MediaInfo] = []
    
    // MARK: - Managers
    
    let mediaManager = MediaManager()
    
    // MARK: - Private
    
    private var cancellables = Set<AnyCancellable>()
    private var collapseTask: DispatchWorkItem?
    private var pauseDismissTask: DispatchWorkItem?
    private var playerDismissTask: DispatchWorkItem?
    private var idleExpandedDismissTask: DispatchWorkItem?
    private var hoverDismissTask: DispatchWorkItem?
    
    private var lastTrackTitle: String?
    private var wasPlaying: Bool = false
    private var isHovered: Bool = false
    
    private let collapseDelay: TimeInterval = 3.0
    private let pauseDismissDelay: TimeInterval = 2.0
    private let playerAutoCloseDelay: TimeInterval = 8.0
    private let idleExpandedAutoCloseDelay: TimeInterval = 6.0
    private let hoverGracePeriod: TimeInterval = 2.5
    
    // MARK: - Size Functions (Fiziksel Çentik Referans Metrikleri)
    
    func notchWidth(for state: NotchState) -> CGFloat {
        switch state {
        case .idle:                  return 220
        case .idleExpanded:          return 350
        case .mediaExpanded:         return 350
        case .mediaCollapsed:        return 305
        case .mediaPausing:          return 305
        case .mediaPlayerActive:     return 350
        case .multiMediaListActive:  return 350
        case .progress:              return 305
        case .notification:          return 350
        }
    }
    
    func notchHeight(for state: NotchState) -> CGFloat {
        switch state {
        case .idle:                  return 38
        case .idleExpanded:          return 85
        case .mediaExpanded:         return 85
        case .mediaCollapsed:        return 38
        case .mediaPausing:          return 38
        case .mediaPlayerActive:     return 200
        case .multiMediaListActive:
            let dynamicHeight = 40 + CGFloat(activeMediaList.count) * 50
            return min(dynamicHeight, 300)
        case .progress:              return 42
        case .notification:          return 85
        }
    }
    
    func notchCornerRadius(for state: NotchState) -> CGFloat {
        switch state {
        case .idle:               return 12
        case .mediaCollapsed, .mediaPausing:
                                  return 12
        case .idleExpanded, .mediaExpanded, .notification:
                                  return 18
        case .mediaPlayerActive, .multiMediaListActive:
                                  return 26
        case .progress:           return 14
        }
    }
    
    func notchFlareRadius(for state: NotchState) -> CGFloat {
        switch state {
        case .idle:               return 6
        case .mediaCollapsed, .mediaPausing:
                                  return 6
        case .idleExpanded, .mediaExpanded, .notification:
                                  return 10
        case .mediaPlayerActive, .multiMediaListActive:
                                  return 12
        case .progress:           return 8
        }
    }
    
    // MARK: - Convenience (currentState üzerinden)
    
    var notchWidth: CGFloat { notchWidth(for: currentState) }
    var notchHeight: CGFloat { notchHeight(for: currentState) }
    var notchCornerRadius: CGFloat { notchCornerRadius(for: currentState) }
    var notchFlareRadius: CGFloat { notchFlareRadius(for: currentState) }
    
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
        
        // lastKnownMedia binding
        mediaManager.$lastKnownMedia
            .receive(on: DispatchQueue.main)
            .assign(to: &$lastKnownMedia)
        
        // activeMediaList binding
        mediaManager.$activeMediaList
            .receive(on: DispatchQueue.main)
            .assign(to: &$activeMediaList)
    }
    
    // MARK: - Media State Machine
    
    private func handleMediaUpdate(_ info: MediaInfo?) {
        self.mediaInfo = info
        
        guard let info = info else {
            cancelAllTimers()
            wasPlaying = false
            if currentState != .idle && currentState != .idleExpanded {
                currentState = .idle
            }
            return
        }
        
        let trackChanged = (info.title != lastTrackTitle)
        let playResumed = (info.isPlaying && !wasPlaying)
        
        lastTrackTitle = info.title
        wasPlaying = info.isPlaying
        
        if info.isPlaying {
            cancelPauseDismissTimer()
            
            // idleExpanded açıkken müzik başlarsa → mediaExpanded'a geç
            if currentState == .idleExpanded {
                cancelIdleExpandedDismissTimer()
                wakeUpNotch()
                return
            }
            
            // mediaPlayerActive veya multiMediaListActive açıkken state değiştirme — sadece veriyi güncelle
            if currentState == .mediaPlayerActive || currentState == .multiMediaListActive {
                if trackChanged {
                    // Şarkı değişti — panel açık kalsın, auto-close timer sıfırla
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
            
            // Player veya mikser açıksa açık kalsın (kullanıcı bilerek açtı)
            if currentState == .mediaPlayerActive || currentState == .multiMediaListActive {
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
        
        // Çoklu medya varsa mikser panelini aç, yoksa tek player
        if mediaManager.activeMediaList.count > 1 {
            currentState = .multiMediaListActive
        } else {
            currentState = .mediaPlayerActive
        }
        
        // Fare zaten üzerindeyse timer başlatma
        if !isHovered {
            startPlayerAutoCloseTimer()
        }
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
    
    // MARK: - Select Primary Media (Mikser Panelinden Seçim)
    
    /// Mikser panelinden bir medya seçildiğinde birincil medya olarak atar ve DJ Masası'na geçer
    func selectPrimaryMedia(_ media: MediaInfo) {
        mediaManager.setPrimaryMedia(media)
        cancelAllTimers()
        currentState = .mediaPlayerActive
        if !isHovered {
            startPlayerAutoCloseTimer()
        }
    }
    
    /// Hedefli play/pause — mikser panelindeki mini buton için
    func togglePlayPause(for source: MediaSource, title: String?) {
        mediaManager.togglePlayPause(for: source, title: title)
        resetPlayerAutoCloseTimer()
    }
    
    // MARK: - Idle Expanded Toggle
    
    /// Idle ↔ idleExpanded geçişi
    func toggleIdleExpanded() {
        if currentState == .idle {
            cancelAllTimers()
            currentState = .idleExpanded
            // Fare zaten üzerindeyse timer başlatma — hover çıkınca grace period halleder
            if !isHovered {
                startIdleExpandedDismissTimer()
            }
        } else if currentState == .idleExpanded {
            cancelIdleExpandedDismissTimer()
            currentState = .idle
        }
    }
    
    /// idleExpanded'dan play'e basıldığında
    func playFromIdleExpanded() {
        cancelIdleExpandedDismissTimer()
        mediaManager.togglePlayPause()
        // Müzik başlayınca handleMediaUpdate otomatik olarak mediaExpanded'a geçecek
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
            if self.currentState == .mediaPlayerActive || self.currentState == .multiMediaListActive {
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
        cancelIdleExpandedDismissTimer()
        cancelHoverDismissTimer()
    }
    
    // MARK: - Idle Expanded Auto-Close Timer
    
    private func startIdleExpandedDismissTimer() {
        cancelIdleExpandedDismissTimer()
        
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            if self.currentState == .idleExpanded {
                self.currentState = .idle
            }
        }
        idleExpandedDismissTask = work
        DispatchQueue.main.asyncAfter(deadline: .now() + idleExpandedAutoCloseDelay, execute: work)
    }
    
    private func cancelIdleExpandedDismissTimer() {
        idleExpandedDismissTask?.cancel()
        idleExpandedDismissTask = nil
    }
    
    // MARK: - Hover Grace Period (2.5 sn debounce)
    
    /// Fare çentikten ayrıldığında, interaktif state'lerde anlık kapatma yerine 2.5 sn bekle.
    /// Fare geri gelirse iptal et.
    func handleHoverChange(_ isHovered: Bool) {
        self.isHovered = isHovered
        
        if isHovered {
            // Fare içeride → bekleyen TÜM otomatik kapanma sayaçlarını durdur
            cancelHoverDismissTimer()
            cancelPlayerAutoCloseTimer()
            cancelIdleExpandedDismissTimer()
        } else {
            // Fare ayrıldı → interaktif state'lerde grace period başlat
            switch currentState {
            case .idleExpanded:
                startHoverDismissTimer(targetState: .idle)
            case .mediaPlayerActive, .multiMediaListActive:
                startHoverDismissTimer(targetState: mediaInfo?.isPlaying == true ? .mediaCollapsed : .mediaPausing)
            default:
                break
            }
        }
    }
    
    private func startHoverDismissTimer(targetState: NotchState) {
        cancelHoverDismissTimer()
        
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.currentState = targetState
            if targetState == .mediaPausing {
                self.startPauseDismissTimer()
            }
        }
        hoverDismissTask = work
        DispatchQueue.main.asyncAfter(deadline: .now() + hoverGracePeriod, execute: work)
    }
    
    private func cancelHoverDismissTimer() {
        hoverDismissTask?.cancel()
        hoverDismissTask = nil
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
