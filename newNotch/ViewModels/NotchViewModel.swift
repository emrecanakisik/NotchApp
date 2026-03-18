//
//  NotchViewModel.swift
//  newNotch
//
//  Created by Emre Can Akisik on 19/03/2026.
//

import SwiftUI
import Combine

class NotchViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    /// Notch genişliği (pt)
    @Published var notchWidth: CGFloat = 200
    
    /// Notch yüksekliği (pt)
    @Published var notchHeight: CGFloat = 32
    
    // MARK: - Init
    
    init() {
        // İleriki aşamalarda burada animasyon, hover, medya kontrolü gibi
        // setup işlemleri yapılacak.
    }
}
