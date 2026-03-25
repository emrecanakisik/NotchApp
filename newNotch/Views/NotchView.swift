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
    @State private var showIdleExpandedContent = false
    
    /// Hover efekti
    @State private var isHovered = false
    
    /// Görsel kutu durumu — içerik animasyonundan bağımsız, gecikmeli güncellenir
    @State private var shapeState: NotchState = .idle
    
    /// Fiziksel çentik yüksekliği — içerikler bunun altından başlamalı
    private let physicalNotchHeight: CGFloat = 38
    
    var body: some View {
        let isInteractive = viewModel.currentState == .idleExpanded
            || viewModel.currentState == .mediaPlayerActive
        let safeZonePadding: CGFloat = isInteractive ? 40 : 0
        

        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                // Kapsül arka planı (player'da RoundedRectangle)
                notchBackground
                
                // Expanded medya içeriği (bildirim)
                if viewModel.currentState == .mediaExpanded, showExpandedContent {
                    expandedMediaView
                        .transition(.opacity)
                        .frame(
                            width: viewModel.notchWidth(for: shapeState) - 24,
                            height: viewModel.notchHeight(for: shapeState) - physicalNotchHeight - 6,
                            alignment: .top
                        )
                        .padding(.top, physicalNotchHeight + 4)
                }
                
                // Collapsed mini indicators
                if viewModel.currentState == .mediaCollapsed, showCollapsedIndicators {
                    collapsedMediaView
                        .transition(.opacity)
                        .frame(
                            width: viewModel.notchWidth(for: shapeState) - 16,
                            height: viewModel.notchHeight(for: shapeState),
                            alignment: .center
                        )
                }
                
                // Pausing indicators
                if viewModel.currentState == .mediaPausing, showPausingIndicators {
                    pausingMediaView
                        .transition(.opacity)
                        .frame(
                            width: viewModel.notchWidth(for: shapeState) - 16,
                            height: viewModel.notchHeight(for: shapeState),
                            alignment: .center
                        )
                }
                
                // Full Media Player
                if viewModel.currentState == .mediaPlayerActive, showPlayerContent {
                    mediaPlayerView
                        .transition(.opacity)
                        .frame(
                            width: viewModel.notchWidth(for: shapeState) - 28,
                            height: viewModel.notchHeight(for: shapeState) - physicalNotchHeight - 6,
                            alignment: .center
                        )
                        .padding(.top, physicalNotchHeight + 4)
                }
                
                // Idle Expanded (Son çalan hayaleti)
                if viewModel.currentState == .idleExpanded, showIdleExpandedContent {
                    idleExpandedView
                        .transition(.opacity)
                        .frame(
                            width: viewModel.notchWidth(for: shapeState) - 24,
                            height: viewModel.notchHeight(for: shapeState) - physicalNotchHeight - 6,
                            alignment: .top
                        )
                        .padding(.top, physicalNotchHeight + 4)
                }
            }
            // Görünmez Ölü Bölge (Safe Zone) — neredeyse görünmez ama hit-testable arka plan
            .padding(.horizontal, safeZonePadding)
            .padding(.bottom, safeZonePadding)
            // Üstte padding yok — çentik ekranın üst kenarına yapışık kalmalı
            .background(Color.white.opacity(0.001)) // macOS hit-test için katı piksel gerekli
            .animation(
                .spring(response: 0.4, dampingFraction: 0.6),
                value: shapeState
            )
            .animation(
                .spring(response: 0.35, dampingFraction: 0.7),
                value: isHovered
            )
            .onChange(of: viewModel.currentState) { newState in
                handleStateTransition(newState)
            }
            .onHover { hovering in
                isHovered = hovering
                viewModel.handleHoverChange(hovering)
            }
            .onTapGesture {
                handleNotchTap()
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.clear)
    }
    
    // MARK: - Notch Background (Fiziksel Çentik Maskeleme)
    
    // MARK: - Notch Background (Fiziksel Çentik Maskeleme)
    
    @ViewBuilder
    private var notchBackground: some View {
        let isCollapsedState = (shapeState == .idle
                                || shapeState == .mediaCollapsed
                                || shapeState == .mediaPausing)
        
        let hoverW: CGFloat = (isCollapsedState && isHovered) ? 12 : 0
        let hoverH: CGFloat = (isCollapsedState && isHovered) ? 6 : 0
        
        let w = viewModel.notchWidth(for: shapeState) + hoverW
        let h = viewModel.notchHeight(for: shapeState) + hoverH
        
        // Dış Radius = İç Radius (12) + Padding (6)
        let cr = (isCollapsedState && isHovered) ? CGFloat(18) : viewModel.notchCornerRadius(for: shapeState)
        let fr = (isCollapsedState && isHovered) ? CGFloat(8) : viewModel.notchFlareRadius(for: shapeState)
        
        ZStack(alignment: .top) {
            // 1) Alt köşeleri yuvarlatılmış ana dikdörtgen
            RoundedRectangle(cornerRadius: cr, style: .continuous)
                .fill(Color.red) 
            
            // 2) Üst köşelerin kıvrımını yok eden düz dikdörtgen maske
            Rectangle()
                .fill(Color.red)
                .frame(height: cr)
        }
        .frame(width: w, height: h)
        // 3) Ekran kenarıyla birleşen dış kavisler (flare)
        .overlay(alignment: .topLeading) {
            TopFlare(flareRadius: fr, corner: .left)
                .fill(Color.red)
                .frame(width: fr, height: fr)
                .offset(x: -fr, y: 0)
        }
        .overlay(alignment: .topTrailing) {
            TopFlare(flareRadius: fr, corner: .right)
                .fill(Color.red)
                .frame(width: fr, height: fr)
                .offset(x: fr, y: 0)
        }
        .compositingGroup()
        .shadow(
            color: .black.opacity(isHovered ? 0.3 : 0),
            radius: 8, x: 0, y: 4
        )
    }
    
    // MARK: - State Transition Handler
    
    /// Görsel alanı karşılaştırarak büyüme/küçülme yönünü belirler
    private func isShrinking(from oldState: NotchState, to newState: NotchState) -> Bool {
        let oldArea = viewModel.notchWidth(for: oldState) * viewModel.notchHeight(for: oldState)
        let newArea = viewModel.notchWidth(for: newState) * viewModel.notchHeight(for: newState)
        return newArea < oldArea
    }
    
    /// Tüm içerik flag'lerini anlık kapatır
    private func hideAllContent(animation: Animation = .easeOut(duration: 0.1)) {
        withAnimation(animation) {
            showExpandedContent = false
            showCollapsedIndicators = false
            showPausingIndicators = false
            showPlayerContent = false
            showIdleExpandedContent = false
        }
    }
    
    /// Hedef state'e uygun içerik flag'ini açar
    private func showContent(for state: NotchState, delay: TimeInterval) {
        switch state {
        case .mediaExpanded:
            withAnimation(.easeIn(duration: 0.25).delay(delay)) {
                showExpandedContent = true
            }
        case .mediaCollapsed:
            withAnimation(.easeIn(duration: 0.2).delay(delay)) {
                showCollapsedIndicators = true
            }
        case .mediaPausing:
            withAnimation(.easeIn(duration: 0.2).delay(delay)) {
                showPausingIndicators = true
            }
        case .mediaPlayerActive:
            withAnimation(.easeIn(duration: 0.3).delay(delay)) {
                showPlayerContent = true
            }
        case .idleExpanded:
            withAnimation(.easeIn(duration: 0.25).delay(delay)) {
                showIdleExpandedContent = true
            }
        default:
            break // idle, progress, notification → içerik yok
        }
    }
    
    private func handleStateTransition(_ newState: NotchState) {
        let oldState = shapeState
        
        if isShrinking(from: oldState, to: newState) {
            // ── Küçülme: Önce içerik kaybolsun, sonra kutu küçülsün ──
            hideAllContent(animation: .easeOut(duration: 0.2))
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                shapeState = newState
                // Küçülme sonrası yeni state'in içeriği varsa göster
                showContent(for: newState, delay: 0.2)
            }
        } else {
            // ── Büyüme: Önce kutu büyüsün, sonra içerik gelsin ──
            hideAllContent(animation: .easeOut(duration: 0.1))
            shapeState = newState
            showContent(for: newState, delay: 0.2)
        }
    }
    
    // MARK: - Notch Tap Handler
    
    private func handleNotchTap() {
        switch viewModel.currentState {
        case .idle:
            viewModel.toggleIdleExpanded()
        case .idleExpanded:
            viewModel.toggleIdleExpanded()
        case .mediaPlayerActive:
            viewModel.closeMediaPlayer()
        default:
            break // Diğer state'lerde tap, kendi iç butonları tarafından yönetilir
        }
    }
    
    // MARK: - Idle Expanded View (Son Çalanın Hayaleti)
    
    private var idleExpandedView: some View {
        Group {
            if let lastMedia = viewModel.lastKnownMedia {
                HStack(spacing: 10) {
                    // Mini albüm kapağı
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.gray.opacity(0.4), Color.gray.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 30, height: 30)
                        .overlay(
                            Image(systemName: "music.note")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white.opacity(0.5))
                        )
                    
                    // Şarkı adı + Sanatçı
                    VStack(alignment: .leading, spacing: 1) {
                        Text(lastMedia.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white.opacity(0.8))
                            .lineLimit(1)
                        
                        Text(lastMedia.artist)
                            .font(.system(size: 9, weight: .regular))
                            .foregroundColor(.white.opacity(0.4))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Play butonu
                    Button(action: { viewModel.playFromIdleExpanded() }) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .frame(width: 24, height: 24)
                }
                .padding(.horizontal, 4)
            } else {
                // Hiç medya çalınmamış
                Text("Nothing here right now.")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.35))
                    .frame(maxWidth: .infinity)
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
        .padding(.top, 6)
        .frame(maxHeight: .infinity, alignment: .center)
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
        .padding(.top, 6)
        .frame(maxHeight: .infinity, alignment: .center)
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.openMediaPlayer()
        }
    }
    
    // MARK: - Full Media Player View (Kontrol Merkezi Tarzı)
    
    private var mediaPlayerView: some View {
        VStack(spacing: 14) {
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
        .padding(.top, 4)
        .padding(.bottom, 12)
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

// MARK: - Top Flare Shape (Dış Kavis)

/// Ekran kenarı ile çentik arasındaki pürüzsüz içbükey kavisi çizer.
/// Sol veya sağ köşeye göre aynalanmış versiyon üretir.
enum FlareCorner {
    case left, right
}

struct TopFlare: Shape {
    let flareRadius: CGFloat
    let corner: FlareCorner
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        // Çentiğin üst köşesinden ekran kenarına doğru içbükey (concave) dolgu.
        // Sadece küçük bir üçgen-kavis çizer — dikdörtgen DEĞİL.
        //
        // Sol flare düzeni (SwiftUI koordinatları, Y aşağı):
        //   Başlangıç: sağ üst (çentik kenarı, ekran üst çizgisi)
        //   Düz çizgi: sağ alt (çentik kenarının devamı, aşağı)
        //   Kavisli eğri: sol üst'e (ekran kenarı), kontrol noktası sol alt'ta → içe çeker
        
        switch corner {
        case .left:
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))    // Sağ üst (Çentiğe değen köşe)
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY)) // Sağ alt (Çentik kenarı boyunca)
            path.addQuadCurve(
                to: CGPoint(x: rect.minX, y: rect.minY),          // Sol üst (Ekran kenarı)
                control: CGPoint(x: rect.maxX, y: rect.minY)      // Sağ üst → kavisi içe çeker (concave)
            )
            path.closeSubpath()
            
        case .right:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))    // Sol üst (Çentiğe değen köşe)
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY)) // Sol alt (Çentik kenarı boyunca)
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY),          // Sağ üst (Ekran kenarı)
                control: CGPoint(x: rect.minX, y: rect.minY)      // Sol üst → kavisi içe çeker (concave)
            )
            path.closeSubpath()
        }
        
        return path
    }
}

#Preview {
    NotchView()
        .frame(width: 500, height: 300)
        .background(Color.gray.opacity(0.2))
}
