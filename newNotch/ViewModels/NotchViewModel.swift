//
//  NotchViewModel.swift
//  newNotch
//
//  Created by Emre Can Akisik on 19/03/2026.
//

import SwiftUI
import Combine

// MARK: - NotchState

enum NotchState: CaseIterable {
    case idle
    case media
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
    
    // MARK: - Computed Sizes
    
    /// Her state için notch genişliği
    var notchWidth: CGFloat {
        switch currentState {
        case .idle:         return 200
        case .media:        return 300
        case .progress:     return 280
        case .notification: return 360
        }
    }
    
    /// Her state için notch yüksekliği
    var notchHeight: CGFloat {
        switch currentState {
        case .idle:         return 32
        case .media:        return 48
        case .progress:     return 40
        case .notification: return 56
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
                
                // @Published güncellemelerini asenkron yap → SwiftUI render döngüsüyle çakışmasın
                DispatchQueue.main.async {
                    self.mediaInfo = info
                    
                    if let info = info, info.isPlaying {
                        // Müzik çalıyorsa → media state'e geç
                        if self.currentState != .media {
                            self.currentState = .media
                        }
                    } else {
                        // Medya yoksa veya durdurulduysa → idle'a dön
                        if self.currentState == .media {
                            self.currentState = .idle
                        }
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Actions
    
    /// Play/Pause toggle
    func togglePlayPause() {
        mediaManager.togglePlayPause()
    }
}
