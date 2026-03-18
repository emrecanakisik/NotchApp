//
//  NotchView.swift
//  newNotch
//
//  Created by Emre Can Akisik on 19/03/2026.
//

import SwiftUI

struct NotchView: View {
    
    @StateObject private var viewModel = NotchViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.black)
                .frame(
                    width: viewModel.notchWidth,
                    height: viewModel.notchHeight
                )
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.clear)
    }
}

#Preview {
    NotchView()
        .frame(width: 300, height: 100)
        .background(Color.gray.opacity(0.2))
}
