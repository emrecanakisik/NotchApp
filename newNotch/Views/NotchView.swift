//
//  NotchView.swift
//  newNotch
//
//  Created by Emre Can Akisik on 19/03/2026.
//

import SwiftUI

struct NotchView: View {
    
    @StateObject private var viewModel = NotchViewModel()
    
    /// İçerik görünürlüğü (kapsül büyüdükten sonra fade-in)
    @State private var showContent = false
    
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                // Kapsül arka planı
                Capsule()
                    .fill(Color.black)
                    .frame(
                        width: viewModel.notchWidth,
                        height: viewModel.notchHeight
                    )
                
                // Medya içeriği (sadece .media state'inde)
                if viewModel.currentState == .media, showContent {
                    mediaContentView
                        .transition(.opacity)
                        .frame(
                            width: viewModel.notchWidth - 24,
                            height: viewModel.notchHeight - 12
                        )
                }
            }
            .animation(
                .spring(response: 0.4, dampingFraction: 0.6),
                value: viewModel.currentState
            )

            .onChange(of: viewModel.currentState) { newState in
                if newState == .media {
                    // Kapsül büyüdükten sonra içeriği fade-in yap
                    withAnimation(.easeIn(duration: 0.25).delay(0.15)) {
                        showContent = true
                    }
                } else {
                    // Önce içeriği fade-out yap
                    withAnimation(.easeOut(duration: 0.15)) {
                        showContent = false
                    }
                }
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.clear)
        .onAppear {
            // Başlangıçta media state'indeyse içeriği göster
            if viewModel.currentState == .media {
                showContent = true
            }
        }
    }
    
    // MARK: - Media Content View
    
    private var mediaContentView: some View {
        HStack(spacing: 10) {
            // Sol: Albüm kapağı (şimdilik gri daire)
            Circle()
                .fill(Color.gray.opacity(0.5))
                .frame(width: 30, height: 30)
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                )
            
            // Orta: Şarkı adı + Sanatçı
            VStack(alignment: .leading, spacing: 1) {
                Text(viewModel.mediaInfo?.title ?? "Bilinmiyor")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text(viewModel.mediaInfo?.artist ?? "—")
                    .font(.system(size: 9, weight: .regular))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Sağ: Play/Pause butonu
            Button(action: {
                viewModel.togglePlayPause()
            }) {
                Image(systemName: viewModel.mediaInfo?.isPlaying == true ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            .frame(width: 24, height: 24)
        }
        .padding(.horizontal, 4)
    }
}

#Preview {
    NotchView()
        .frame(width: 400, height: 120)
        .background(Color.gray.opacity(0.2))
}
