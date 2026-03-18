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
    
    // MARK: - Actions
    
    /// State'ler arası sırayla geçiş yapar (idle → media → progress → notification → idle)
    func cycleState() {
        let allCases = NotchState.allCases
        guard let currentIndex = allCases.firstIndex(of: currentState) else { return }
        let nextIndex = (currentIndex + 1) % allCases.count
        currentState = allCases[nextIndex]
    }
}
