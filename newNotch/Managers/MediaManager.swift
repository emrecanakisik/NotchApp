//
//  MediaManager.swift
//  newNotch
//
//  Created by Emre Can Akisik on 19/03/2026.
//

import Foundation
import Combine
import AppKit

// MARK: - MediaInfo

struct MediaInfo {
    var title: String
    var artist: String
    var isPlaying: Bool
}

// MARK: - MediaManager

class MediaManager: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var mediaInfo: MediaInfo?
    
    // MARK: - Private Properties
    
    private var pollTimer: Timer?
    private let pollInterval: TimeInterval = 2.0
    
    /// Mock modu aktif mi? (AppleScript erişimi yoksa true yap)
    private var useMockData = false
    private var mockTimer: Timer?
    private var mockIndex = 0
    
    private let mockTracks: [(String, String)] = [
        ("Blinding Lights", "The Weeknd"),
        ("Bohemian Rhapsody", "Queen"),
        ("Starboy", "The Weeknd"),
        ("Levitating", "Dua Lipa"),
        ("As It Was", "Harry Styles")
    ]
    
    // MARK: - Init
    
    init() {
        // View çizimi tamamlansın diye polling'i geciktir
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.startPolling()
        }
    }
    
    deinit {
        stopPolling()
    }
    
    // MARK: - Polling
    
    func startPolling() {
        // İlk sorgulamayı arka planda yap
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.fetchNowPlaying()
        }
        
        // Periyodik sorgulama
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            DispatchQueue.global(qos: .userInitiated).async {
                self?.fetchNowPlaying()
            }
        }
    }
    
    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
        mockTimer?.invalidate()
        mockTimer = nil
    }
    
    // MARK: - Play/Pause Toggle
    
    func togglePlayPause() {
        if useMockData {
            // Mock: sadece isPlaying durumunu tersle
            if var info = mediaInfo {
                info.isPlaying.toggle()
                let updated = info
                DispatchQueue.main.async { [weak self] in
                    self?.mediaInfo = updated
                }
            }
            return
        }
        
        // Önce Spotify'ı dene, sonra Apple Music
        let spotifyScript = """
        tell application "System Events"
            if exists (processes where name is "Spotify") then
                tell application "Spotify" to playpause
                return true
            end if
        end tell
        return false
        """
        
        if let result = runAppleScript(spotifyScript), result != "false" {
            // Spotify bulundu, komut gönderildi
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.fetchNowPlaying()
            }
            return
        }
        
        let musicScript = """
        tell application "System Events"
            if exists (processes where name is "Music") then
                tell application "Music" to playpause
                return true
            end if
        end tell
        return false
        """
        
        _ = runAppleScript(musicScript)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.fetchNowPlaying()
        }
    }
    
    // MARK: - Fetch Now Playing
    
    private func fetchNowPlaying() {
        // Spotify'ı kontrol et
        if let info = fetchFromSpotify() {
            DispatchQueue.main.async { [weak self] in
                self?.useMockData = false
                self?.mediaInfo = info
            }
            return
        }
        
        // Apple Music'i kontrol et
        if let info = fetchFromAppleMusic() {
            DispatchQueue.main.async { [weak self] in
                self?.useMockData = false
                self?.mediaInfo = info
            }
            return
        }
        
        // Hiçbir müzik uygulaması aktif değilse → mock moda geç
        if !useMockData {
            useMockData = true
            DispatchQueue.main.async { [weak self] in
                self?.startMockMode()
            }
        }
    }
    
    // MARK: - Spotify AppleScript
    
    private func fetchFromSpotify() -> MediaInfo? {
        let script = """
        tell application "System Events"
            if not (exists (processes where name is "Spotify")) then
                return "NOT_RUNNING"
            end if
        end tell
        tell application "Spotify"
            if player state is playing then
                set trackName to name of current track
                set trackArtist to artist of current track
                return trackName & "|||" & trackArtist & "|||PLAYING"
            else if player state is paused then
                set trackName to name of current track
                set trackArtist to artist of current track
                return trackName & "|||" & trackArtist & "|||PAUSED"
            else
                return "NO_TRACK"
            end if
        end tell
        """
        
        guard let result = runAppleScript(script),
              result != "NOT_RUNNING",
              result != "NO_TRACK" else {
            return nil
        }
        
        let parts = result.components(separatedBy: "|||")
        guard parts.count == 3 else { return nil }
        
        return MediaInfo(
            title: parts[0],
            artist: parts[1],
            isPlaying: parts[2] == "PLAYING"
        )
    }
    
    // MARK: - Apple Music AppleScript
    
    private func fetchFromAppleMusic() -> MediaInfo? {
        let script = """
        tell application "System Events"
            if not (exists (processes where name is "Music")) then
                return "NOT_RUNNING"
            end if
        end tell
        tell application "Music"
            if player state is playing then
                set trackName to name of current track
                set trackArtist to artist of current track
                return trackName & "|||" & trackArtist & "|||PLAYING"
            else if player state is paused then
                set trackName to name of current track
                set trackArtist to artist of current track
                return trackName & "|||" & trackArtist & "|||PAUSED"
            else
                return "NO_TRACK"
            end if
        end tell
        """
        
        guard let result = runAppleScript(script),
              result != "NOT_RUNNING",
              result != "NO_TRACK" else {
            return nil
        }
        
        let parts = result.components(separatedBy: "|||")
        guard parts.count == 3 else { return nil }
        
        return MediaInfo(
            title: parts[0],
            artist: parts[1],
            isPlaying: parts[2] == "PLAYING"
        )
    }
    
    // MARK: - Mock Mode
    
    private func startMockMode() {
        // Hemen ilk mock veriyi göster
        showMockTrack()
        
        // Her 5 saniyede yeni mock şarkıya geç
        mockTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.advanceMockTrack()
        }
    }
    
    private func showMockTrack() {
        let track = mockTracks[mockIndex]
        DispatchQueue.main.async { [weak self] in
            self?.mediaInfo = MediaInfo(
                title: track.0,
                artist: track.1,
                isPlaying: true
            )
        }
    }
    
    private func advanceMockTrack() {
        mockIndex = (mockIndex + 1) % mockTracks.count
        showMockTrack()
    }
    
    // MARK: - AppleScript Runner
    
    private func runAppleScript(_ source: String) -> String? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if error != nil { return nil }
        return result.stringValue
    }
}
