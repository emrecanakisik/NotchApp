//
//  NotchView.swift
//  newNotch
//
//  Created by Emre Can Akisik on 19/03/2026.
//

import SwiftUI

struct NotchView: View {
    
    @StateObject private var viewModel = NotchViewModel()
    
    /// Expanded içerik görünürlüğü
    @State private var showExpandedContent = false
    
    /// Collapsed indicators görünürlüğü
    @State private var showCollapsedIndicators = false
    
    /// Pausing indicators görünürlüğü
    @State private var showPausingIndicators = false
    
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
                
                // Expanded medya içeriği
                if viewModel.currentState == .mediaExpanded, showExpandedContent {
                    expandedMediaView
                        .transition(.opacity)
                        .frame(
                            width: viewModel.notchWidth - 24,
                            height: viewModel.notchHeight - 12
                        )
                }
                
                // Collapsed mini indicators (müzik çalıyor)
                if viewModel.currentState == .mediaCollapsed, showCollapsedIndicators {
                    collapsedMediaView
                        .transition(.opacity)
                        .frame(
                            width: viewModel.notchWidth - 16,
                            height: viewModel.notchHeight - 8
                        )
                }
                
                // Pausing indicators (müzik duraklatıldı — 2 sn grace period)
                if viewModel.currentState == .mediaPausing, showPausingIndicators {
                    pausingMediaView
                        .transition(.opacity)
                        .frame(
                            width: viewModel.notchWidth - 16,
                            height: viewModel.notchHeight - 8
                        )
                }
            }
            .animation(
                .spring(response: 0.4, dampingFraction: 0.6),
                value: viewModel.currentState
            )
            .onChange(of: viewModel.currentState) { newState in
                handleStateTransition(newState)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.clear)
    }
    
    // MARK: - State Transition Handler
    
    private func handleStateTransition(_ newState: NotchState) {
        switch newState {
        case .mediaExpanded:
            // Diğer indicators'ları kapat
            withAnimation(.easeOut(duration: 0.1)) {
                showCollapsedIndicators = false
                showPausingIndicators = false
            }
            // Expanded içeriği fade-in
            withAnimation(.easeIn(duration: 0.25).delay(0.2)) {
                showExpandedContent = true
            }
            
        case .mediaCollapsed:
            // Expanded içeriği kapat
            withAnimation(.easeOut(duration: 0.15)) {
                showExpandedContent = false
                showPausingIndicators = false
            }
            // Collapsed indicators fade-in
            withAnimation(.easeIn(duration: 0.2).delay(0.25)) {
                showCollapsedIndicators = true
            }
            
        case .mediaPausing:
            // Mevcut indicators'ları kapat
            withAnimation(.easeOut(duration: 0.15)) {
                showExpandedContent = false
                showCollapsedIndicators = false
            }
            // Pausing indicators fade-in (pause ikonu göster)
            withAnimation(.easeIn(duration: 0.2).delay(0.15)) {
                showPausingIndicators = true
            }
            
        case .idle:
            // Her şeyi yumuşakça kapat
            withAnimation(.easeOut(duration: 0.25)) {
                showExpandedContent = false
                showCollapsedIndicators = false
                showPausingIndicators = false
            }
            
        default:
            withAnimation(.easeOut(duration: 0.15)) {
                showExpandedContent = false
                showCollapsedIndicators = false
                showPausingIndicators = false
            }
        }
    }
    
    // MARK: - Expanded Media View
    
    private var expandedMediaView: some View {
        HStack(spacing: 10) {
            // Sol: Albüm kapağı
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
    
    // MARK: - Collapsed Media View (müzik çalıyor — albüm + waveform animasyonlu)
    
    private var collapsedMediaView: some View {
        HStack {
            // Sol uç: Minik albüm kapağı
            Circle()
                .fill(Color.gray.opacity(0.5))
                .frame(width: 18, height: 18)
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(.white.opacity(0.8))
                )
            
            Spacer()
            
            // Sağ uç: Waveform ikonu (animasyonlu)
            Image(systemName: "waveform")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
                .symbolEffect(.variableColor.iterative, isActive: true)
        }
        .padding(.horizontal, 4)
    }
    
    // MARK: - Pausing Media View (müzik durdu — albüm + pause ikonu statik)
    
    private var pausingMediaView: some View {
        HStack {
            // Sol uç: Minik albüm kapağı
            Circle()
                .fill(Color.gray.opacity(0.35))
                .frame(width: 18, height: 18)
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(.white.opacity(0.5))
                )
            
            Spacer()
            
            // Sağ uç: Statik pause ikonu (waveform yerine)
            Image(systemName: "pause.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(.horizontal, 4)
    }
}

#Preview {
    NotchView()
        .frame(width: 400, height: 120)
        .background(Color.gray.opacity(0.2))
}
