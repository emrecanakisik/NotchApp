//
//  NotchView.swift
//  newNotch
//
//  Created by Emre Can Akisik on 19/03/2026.
//

import SwiftUI

struct NotchView: View {
    
    @StateObject private var viewModel = NotchViewModel()
    
    /// İçerik görünürlük flag'leri
    @State private var showExpandedContent = false
    @State private var showCollapsedIndicators = false
    @State private var showPausingIndicators = false
    @State private var showPlayerContent = false
    
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                // Kapsül arka planı (player'da RoundedRectangle)
                notchBackground
                
                // Expanded medya içeriği (bildirim)
                if viewModel.currentState == .mediaExpanded, showExpandedContent {
                    expandedMediaView
                        .transition(.opacity)
                        .frame(
                            width: viewModel.notchWidth - 24,
                            height: viewModel.notchHeight - 12
                        )
                }
                
                // Collapsed mini indicators
                if viewModel.currentState == .mediaCollapsed, showCollapsedIndicators {
                    collapsedMediaView
                        .transition(.opacity)
                        .frame(
                            width: viewModel.notchWidth - 16,
                            height: viewModel.notchHeight - 8
                        )
                }
                
                // Pausing indicators
                if viewModel.currentState == .mediaPausing, showPausingIndicators {
                    pausingMediaView
                        .transition(.opacity)
                        .frame(
                            width: viewModel.notchWidth - 16,
                            height: viewModel.notchHeight - 8
                        )
                }
                
                // Full Media Player
                if viewModel.currentState == .mediaPlayerActive, showPlayerContent {
                    mediaPlayerView
                        .transition(.opacity)
                        .frame(
                            width: viewModel.notchWidth - 28,
                            height: viewModel.notchHeight - 20
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
    
    // MARK: - Notch Background
    
    @ViewBuilder
    private var notchBackground: some View {
        if viewModel.currentState == .mediaPlayerActive {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black)
                .frame(
                    width: viewModel.notchWidth,
                    height: viewModel.notchHeight
                )
        } else {
            Capsule()
                .fill(Color.black)
                .frame(
                    width: viewModel.notchWidth,
                    height: viewModel.notchHeight
                )
        }
    }
    
    // MARK: - State Transition Handler
    
    private func handleStateTransition(_ newState: NotchState) {
        switch newState {
        case .mediaExpanded:
            withAnimation(.easeOut(duration: 0.1)) {
                showCollapsedIndicators = false
                showPausingIndicators = false
                showPlayerContent = false
            }
            withAnimation(.easeIn(duration: 0.25).delay(0.2)) {
                showExpandedContent = true
            }
            
        case .mediaCollapsed:
            withAnimation(.easeOut(duration: 0.15)) {
                showExpandedContent = false
                showPausingIndicators = false
                showPlayerContent = false
            }
            withAnimation(.easeIn(duration: 0.2).delay(0.25)) {
                showCollapsedIndicators = true
            }
            
        case .mediaPausing:
            withAnimation(.easeOut(duration: 0.15)) {
                showExpandedContent = false
                showCollapsedIndicators = false
                showPlayerContent = false
            }
            withAnimation(.easeIn(duration: 0.2).delay(0.15)) {
                showPausingIndicators = true
            }
            
        case .mediaPlayerActive:
            withAnimation(.easeOut(duration: 0.1)) {
                showExpandedContent = false
                showCollapsedIndicators = false
                showPausingIndicators = false
            }
            withAnimation(.easeIn(duration: 0.3).delay(0.2)) {
                showPlayerContent = true
            }
            
        case .idle:
            withAnimation(.easeOut(duration: 0.25)) {
                showExpandedContent = false
                showCollapsedIndicators = false
                showPausingIndicators = false
                showPlayerContent = false
            }
            
        default:
            withAnimation(.easeOut(duration: 0.15)) {
                showExpandedContent = false
                showCollapsedIndicators = false
                showPausingIndicators = false
                showPlayerContent = false
            }
        }
    }
    
    // MARK: - Expanded Media View (Bildirim bandı)
    
    private var expandedMediaView: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.gray.opacity(0.4))
                .frame(width: 30, height: 30)
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                )
            
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
            
            Button(action: { viewModel.togglePlayPause() }) {
                Image(systemName: viewModel.mediaInfo?.isPlaying == true ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            .frame(width: 24, height: 24)
        }
        .padding(.horizontal, 4)
    }
    
    // MARK: - Collapsed Media View (tıklanabilir → player açılır)
    
    private var collapsedMediaView: some View {
        HStack {
            Circle()
                .fill(Color.gray.opacity(0.5))
                .frame(width: 18, height: 18)
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(.white.opacity(0.8))
                )
            
            Spacer()
            
            Image(systemName: "waveform")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
                .symbolEffect(.variableColor.iterative, isActive: true)
        }
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.openMediaPlayer()
        }
    }
    
    // MARK: - Pausing Media View (tıklanabilir → player açılır)
    
    private var pausingMediaView: some View {
        HStack {
            Circle()
                .fill(Color.gray.opacity(0.35))
                .frame(width: 18, height: 18)
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(.white.opacity(0.5))
                )
            
            Spacer()
            
            Image(systemName: "pause.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.openMediaPlayer()
        }
    }
    
    // MARK: - Full Media Player View (Kontrol Merkezi Tarzı)
    
    private var mediaPlayerView: some View {
        VStack(spacing: 12) {
            // Üst bölüm: Albüm kapağı + Şarkı bilgisi
            HStack(spacing: 12) {
                // Albüm kapağı (büyük, köşeleri yuvarlatılmış kare)
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.pink.opacity(0.7), Color.purple.opacity(0.5)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                    )
                
                // Şarkı adı + Sanatçı
                VStack(alignment: .leading, spacing: 3) {
                    Text(viewModel.mediaInfo?.title ?? "Bilinmiyor")
                        .font(.system(size: 14, weight: .semibold, design: .default))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Text(viewModel.mediaInfo?.artist ?? "—")
                        .font(.system(size: 12, weight: .regular, design: .default))
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Waveform / Kapat butonu
                Button(action: { viewModel.closeMediaPlayer() }) {
                    Image(systemName: "chevron.compact.up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
            
            // Alt bölüm: 5'li kontrol butonları
            HStack(spacing: 0) {
                Spacer()
                
                // 1) Geri Şarkı
                playerButton(icon: "backward.fill", size: 16) {
                    viewModel.previousTrack()
                }
                
                Spacer()
                
                // 2) 10 sn Geri
                playerButton(icon: "gobackward.10", size: 18) {
                    viewModel.skipBackward()
                }
                
                Spacer()
                
                // 3) Play / Pause (büyük)
                playerButton(
                    icon: viewModel.mediaInfo?.isPlaying == true ? "pause.fill" : "play.fill",
                    size: 26
                ) {
                    viewModel.togglePlayPause()
                }
                
                Spacer()
                
                // 4) 10 sn İleri
                playerButton(icon: "goforward.10", size: 18) {
                    viewModel.skipForward()
                }
                
                Spacer()
                
                // 5) İleri Şarkı
                playerButton(icon: "forward.fill", size: 16) {
                    viewModel.nextTrack()
                }
                
                Spacer()
            }
            .padding(.horizontal, 4)
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Player Button (Hover efektli)
    
    private func playerButton(icon: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .bold))
                .foregroundColor(.white.opacity(0.85))
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlayerButtonStyle())
    }
}

// MARK: - Player Button Style (Hover glow efekti)

struct PlayerButtonStyle: ButtonStyle {
    @State private var isHovered = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.85 : 1.0)
            .opacity(configuration.isPressed ? 0.6 : 1.0)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(isHovered ? 0.1 : 0))
            )
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

#Preview {
    NotchView()
        .frame(width: 400, height: 200)
        .background(Color.gray.opacity(0.2))
}
