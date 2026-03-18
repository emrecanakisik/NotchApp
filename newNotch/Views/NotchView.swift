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
                .animation(
                    .spring(response: 0.4, dampingFraction: 0.6),
                    value: viewModel.currentState
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.cycleState()
                }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.clear)
    }
}

#Preview {
    NotchView()
        .frame(width: 400, height: 120)
        .background(Color.gray.opacity(0.2))
}
