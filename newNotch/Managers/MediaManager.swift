//
//  MediaManager.swift
//  newNotch
//
//  Created by Emre Can Akisik on 19/03/2026.
//

import Foundation
import Combine
import AppKit

// MARK: - MediaSource

/// Medya kaynağı tipi — önceliklendirme için
/// Spesifik uygulama kaynakları daha yüksek öncelikli (AppleScript/JS kontrolü mümkün)
/// mediaRemote sadece fallback (kontrol sınırlı)
enum MediaSource: Int, Comparable {
    case mock = 0
    case mediaRemote = 1    // Sistem fallback — sadece Now Playing okur
    case browserTab = 2
    case appleMusic = 3
    case spotify = 4        // En yüksek — tam AppleScript kontrolü
    
    static func < (lhs: MediaSource, rhs: MediaSource) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

// MARK: - MediaInfo

struct MediaInfo: Identifiable, Equatable {
    var title: String
    var artist: String
    var isPlaying: Bool
    var source: MediaSource
    
    /// Kompozit kimlik: kaynak + başlık üzerinden eşsizlik
    var id: String { "\(source.rawValue)_\(title)" }
    
    static func == (lhs: MediaInfo, rhs: MediaInfo) -> Bool {
        lhs.source == rhs.source && lhs.title == rhs.title
    }
}

// MARK: - MediaManager

class MediaManager: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var mediaInfo: MediaInfo?
    @Published var lastKnownMedia: MediaInfo?
    @Published var activeMediaList: [MediaInfo] = []
    
    // MARK: - Private Properties
    
    private var pollTimer: Timer?
    private let pollInterval: TimeInterval = 2.0
    
    /// Tek Şeritli Yol — tüm medya sorguları bu seri kuyrukta çalışır
    private let pollQueue = DispatchQueue(label: "com.newNotch.mediaPollQueue", qos: .userInitiated)
    
    /// Trafik Polisi — önceki tarama bitmeden yenisi başlamasın
    private var isFetching = false
    
    /// MediaRemote function pointers
    private var MRMediaRemoteGetNowPlayingInfo: (@convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void)?
    private var MRMediaRemoteGetNowPlayingApplicationIsPlaying: (@convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void)?
    private var mediaRemoteLoaded = false
    
    /// Mock modu
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
    
    /// Uygulama adı → Bundle ID eşleştirmesi (çalışıyor mu kontrolü için)
    private let appBundleIDs: [String: String] = [
        "Spotify":          "com.spotify.client",
        "Music":            "com.apple.Music",
        "Google Chrome":    "com.google.Chrome",
        "Brave Browser":    "com.brave.Browser",
        "Microsoft Edge":   "com.microsoft.edgemac",
        "Arc":              "company.thebrowser.Browser",
        "Opera":            "com.operasoftware.Opera",
        "Safari":           "com.apple.Safari"
    ]
    
    // MARK: - MediaRemote Keys (Private API)
    
    private let kMRMediaRemoteNowPlayingInfoTitle = "kMRMediaRemoteNowPlayingInfoTitle"
    private let kMRMediaRemoteNowPlayingInfoArtist = "kMRMediaRemoteNowPlayingInfoArtist"
    private let kMRMediaRemoteNowPlayingInfoAlbum = "kMRMediaRemoteNowPlayingInfoAlbum"
    private let kMRMediaRemoteNowPlayingInfoPlaybackRate = "kMRMediaRemoteNowPlayingInfoPlaybackRate"
    
    // MARK: - Init
    
    init() {
        loadMediaRemoteFramework()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.startPolling()
        }
    }
    
    deinit {
        stopPolling()
    }
    
    // MARK: - MediaRemote Framework Loading
    
    private func loadMediaRemoteFramework() {
        let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
        
        guard let handle = dlopen(path, RTLD_NOW) else {
            print("[MediaManager] MediaRemote.framework yüklenemedi, fallback kullanılacak")
            return
        }
        
        if let sym = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") {
            MRMediaRemoteGetNowPlayingInfo = unsafeBitCast(
                sym,
                to: (@convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void).self
            )
        }
        
        if let sym = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying") {
            MRMediaRemoteGetNowPlayingApplicationIsPlaying = unsafeBitCast(
                sym,
                to: (@convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void).self
            )
        }
        
        mediaRemoteLoaded = (MRMediaRemoteGetNowPlayingInfo != nil)
        
        if mediaRemoteLoaded {
            print("[MediaManager] ✅ MediaRemote.framework başarıyla yüklendi")
        } else {
            print("[MediaManager] ⚠️ MediaRemote fonksiyonları bulunamadı, fallback kullanılacak")
        }
    }
    
    // MARK: - Polling
    
    func startPolling() {
        pollQueue.async { [weak self] in
            guard let self = self else { return }
            self.isFetching = true
            self.fetchNowPlaying()
            self.isFetching = false
        }
        
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.pollQueue.async {
                guard let self = self else { return }
                guard !self.isFetching else { return }
                self.isFetching = true
                defer { self.isFetching = false }
                self.fetchNowPlaying()
            }
        }
    }
    
    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
        mockTimer?.invalidate()
        mockTimer = nil
    }
    
    // MARK: - Play/Pause Toggle (Kaynak Bazlı)
    
    func togglePlayPause() {
        if useMockData {
            if var info = mediaInfo {
                info.isPlaying.toggle()
                let updated = info
                DispatchQueue.main.async { [weak self] in
                    self?.mediaInfo = updated
                }
            }
            return
        }
        
        pollQueue.async { [weak self] in
            guard let self = self else { return }
            let currentSource = self.mediaInfo?.source
            
            switch currentSource {
            case .spotify:
                if self.isAppRunning("Spotify") {
                    let script = """
                    if application "Spotify" is running then
                        tell application "Spotify" to playpause
                    end if
                    """
                    _ = self.runAppleScript(script)
                }
                
            case .appleMusic:
                if self.isAppRunning("Music") {
                    let script = """
                    if application "Music" is running then
                        tell application "Music" to playpause
                    end if
                    """
                    _ = self.runAppleScript(script)
                }
                
            case .browserTab:
                self.browserTogglePlayPause(targetTitle: self.mediaInfo?.title)
                
            default:
                self.sendMediaKeyEvent(keyType: 16)
            }
            
            self.pollQueue.asyncAfter(deadline: .now() + 0.5) {
                self.fetchNowPlaying()
            }
        }
    }
    
    // MARK: - Targeted Play/Pause (Hedef Bazlı — Mikser Paneli İçin)
    
    /// Belirli bir kaynak ve başlığa göre play/pause yapar
    func togglePlayPause(for source: MediaSource, title: String?) {
        pollQueue.async { [weak self] in
            guard let self = self else { return }
            
            switch source {
            case .spotify:
                if self.isAppRunning("Spotify") {
                    let script = """
                    if application "Spotify" is running then
                        tell application "Spotify" to playpause
                    end if
                    """
                    _ = self.runAppleScript(script)
                }
                
            case .appleMusic:
                if self.isAppRunning("Music") {
                    let script = """
                    if application "Music" is running then
                        tell application "Music" to playpause
                    end if
                    """
                    _ = self.runAppleScript(script)
                }
                
            case .browserTab:
                self.browserTogglePlayPause(targetTitle: title)
                
            default:
                self.sendMediaKeyEvent(keyType: 16)
            }
            
            self.pollQueue.asyncAfter(deadline: .now() + 0.5) {
                self.fetchNowPlaying()
            }
        }
    }
    
    // MARK: - Set Primary Media (Kullanıcı Seçimi)
    
    /// Mikser panelinden seçilen medyayı birincil medya olarak atar
    func setPrimaryMedia(_ media: MediaInfo) {
        DispatchQueue.main.async { [weak self] in
            self?.mediaInfo = media
            if media.source != .mock {
                self?.lastKnownMedia = media
            }
        }
    }
    
    // MARK: - Next / Previous Track (Kaynak Bazlı)
    
    func nextTrack() {
        if useMockData {
            advanceMockTrack()
            return
        }
        
        pollQueue.async { [weak self] in
            guard let self = self else { return }
            let currentSource = self.mediaInfo?.source
            
            switch currentSource {
            case .spotify:
                if self.isAppRunning("Spotify") {
                    let script = """
                    if application "Spotify" is running then
                        tell application "Spotify" to next track
                    end if
                    """
                    _ = self.runAppleScript(script)
                }
                
            case .appleMusic:
                if self.isAppRunning("Music") {
                    let script = """
                    if application "Music" is running then
                        tell application "Music" to next track
                    end if
                    """
                    _ = self.runAppleScript(script)
                }
                
            case .browserTab:
                // Browser'da next track yok — CGEvent fallback
                self.sendMediaKeyEvent(keyType: 17)
                
            default:
                self.sendMediaKeyEvent(keyType: 17)
            }
            
            self.pollQueue.asyncAfter(deadline: .now() + 0.8) {
                self.fetchNowPlaying()
            }
        }
    }
    
    func previousTrack() {
        if useMockData {
            mockIndex = (mockIndex - 1 + mockTracks.count) % mockTracks.count
            showMockTrack()
            return
        }
        
        pollQueue.async { [weak self] in
            guard let self = self else { return }
            let currentSource = self.mediaInfo?.source
            
            switch currentSource {
            case .spotify:
                if self.isAppRunning("Spotify") {
                    let script = """
                    if application "Spotify" is running then
                        tell application "Spotify" to previous track
                    end if
                    """
                    _ = self.runAppleScript(script)
                }
                
            case .appleMusic:
                if self.isAppRunning("Music") {
                    let script = """
                    if application "Music" is running then
                        tell application "Music" to previous track
                    end if
                    """
                    _ = self.runAppleScript(script)
                }
                
            case .browserTab:
                self.sendMediaKeyEvent(keyType: 18)
                
            default:
                self.sendMediaKeyEvent(keyType: 18)
            }
            
            self.pollQueue.asyncAfter(deadline: .now() + 0.8) {
                self.fetchNowPlaying()
            }
        }
    }
    
    // MARK: - Browser Play/Pause (JavaScript Injection — Target-Specific)
    
    /// targetTitle: Şu an gösterilen medyanın başlığı. Sadece başlığı eşleşen sekmeye müdahale eder.
    private func browserTogglePlayPause(targetTitle: String?) {
        let toggleJS = """
        (function() {
            var elems = document.querySelectorAll('video, audio');
            for (var i = 0; i < elems.length; i++) {
                if (elems[i].duration > 0) {
                    if (elems[i].paused) { elems[i].play(); } else { elems[i].pause(); }
                    return 'OK';
                }
            }
            return 'NO_MEDIA';
        })();
        """
        
        let escapedTitle = escapeForAppleScript(targetTitle ?? "")
        let hasTarget = !(targetTitle ?? "").isEmpty
        
        let chromiumBrowsers = ["Google Chrome", "Brave Browser", "Microsoft Edge", "Arc", "Opera"]
        
        for appName in chromiumBrowsers {
            guard isAppRunning(appName) else { continue }
            
            let titleCheck = hasTarget
                ? "if title of currentTab contains \"\(escapedTitle)\" then"
                : "if true then"  // targetTitle yoksa fallback: hepsine bak
            let titleEnd = "end if"
            
            let script = """
            if application "\(appName)" is running then
                tell application "\(appName)"
                    set windowCount to count of windows
                    repeat with w from 1 to windowCount
                        set tabCount to count of tabs of window w
                        repeat with t from 1 to tabCount
                            try
                                set currentTab to tab t of window w
                                \(titleCheck)
                                    set jsResult to execute currentTab javascript "\(toggleJS)"
                                    if jsResult is "OK" then return "DONE"
                                \(titleEnd)
                            end try
                        end repeat
                    end repeat
                end tell
            end if
            """
            if let result = runAppleScript(script), result == "DONE" { return }
        }
        
        // Safari
        if isAppRunning("Safari") {
            let titleCheck = hasTarget
                ? "if name of currentTab contains \"\(escapedTitle)\" then"
                : "if true then"
            let titleEnd = "end if"
            
            let script = """
            if application "Safari" is running then
                tell application "Safari"
                    set windowCount to count of windows
                    repeat with w from 1 to windowCount
                        set tabCount to count of tabs of window w
                        repeat with t from 1 to tabCount
                            try
                                set currentTab to tab t of window w
                                \(titleCheck)
                                    set jsResult to do JavaScript "\(toggleJS)" in currentTab
                                    if jsResult is "OK" then return "DONE"
                                \(titleEnd)
                            end try
                        end repeat
                    end repeat
                end tell
            end if
            """
            _ = runAppleScript(script)
        }
    }
    
    // MARK: - Skip Forward / Backward (Kaynak Bazlı)
    
    /// 10 saniye ileri sar
    func skipForward(seconds: Int = 10) {
        if useMockData { return }
        
        pollQueue.async { [weak self] in
            guard let self = self else { return }
            let currentSource = self.mediaInfo?.source
            
            switch currentSource {
            case .spotify:
                if self.isAppRunning("Spotify") {
                    let script = """
                    if application "Spotify" is running then
                        tell application "Spotify"
                            set player position to (player position + \(seconds))
                        end tell
                    end if
                    """
                    _ = self.runAppleScript(script)
                }
                
            case .appleMusic:
                if self.isAppRunning("Music") {
                    let script = """
                    if application "Music" is running then
                        tell application "Music"
                            set player position to (player position + \(seconds))
                        end tell
                    end if
                    """
                    _ = self.runAppleScript(script)
                }
                
            case .browserTab:
                self.browserSeek(seconds: seconds, targetTitle: self.mediaInfo?.title)
                
            default:
                // MediaRemote veya bilinmeyen kaynak — CGEvent Fast Forward
                self.sendMediaKeyEvent(keyType: 19)
            }
        }
    }
    
    /// 10 saniye geri sar
    func skipBackward(seconds: Int = 10) {
        if useMockData { return }
        
        pollQueue.async { [weak self] in
            guard let self = self else { return }
            let currentSource = self.mediaInfo?.source
            
            switch currentSource {
            case .spotify:
                if self.isAppRunning("Spotify") {
                    let script = """
                    if application "Spotify" is running then
                        tell application "Spotify"
                            set newPos to (player position - \(seconds))
                            if newPos < 0 then set newPos to 0
                            set player position to newPos
                        end tell
                    end if
                    """
                    _ = self.runAppleScript(script)
                }
                
            case .appleMusic:
                if self.isAppRunning("Music") {
                    let script = """
                    if application "Music" is running then
                        tell application "Music"
                            set newPos to (player position - \(seconds))
                            if newPos < 0 then set newPos to 0
                            set player position to newPos
                        end tell
                    end if
                    """
                    _ = self.runAppleScript(script)
                }
                
            case .browserTab:
                self.browserSeek(seconds: -seconds, targetTitle: self.mediaInfo?.title)
                
            default:
                self.sendMediaKeyEvent(keyType: 20)
            }
        }
    }
    
    // MARK: - Browser Seek (JavaScript Injection — Target-Specific)
    
    /// Tarayıcılardaki video/audio elementini seek eder — sadece targetTitle ile eşleşen sekmede
    private func browserSeek(seconds: Int, targetTitle: String?) {
        let seekJS = """
        (function() {
            var elems = document.querySelectorAll('video, audio');
            for (var i = 0; i < elems.length; i++) {
                if (elems[i].duration > 0) {
                    elems[i].currentTime += \(seconds);
                    return 'OK';
                }
            }
            return 'NO_MEDIA';
        })();
        """
        
        let escapedTitle = escapeForAppleScript(targetTitle ?? "")
        let hasTarget = !(targetTitle ?? "").isEmpty
        
        let chromiumBrowsers = ["Google Chrome", "Brave Browser", "Microsoft Edge", "Arc", "Opera"]
        
        for appName in chromiumBrowsers {
            guard isAppRunning(appName) else { continue }
            
            let titleCheck = hasTarget
                ? "if title of currentTab contains \"\(escapedTitle)\" then"
                : "if true then"
            let titleEnd = "end if"
            
            let script = """
            if application "\(appName)" is running then
                tell application "\(appName)"
                    set windowCount to count of windows
                    repeat with w from 1 to windowCount
                        set tabCount to count of tabs of window w
                        repeat with t from 1 to tabCount
                            try
                                set currentTab to tab t of window w
                                \(titleCheck)
                                    set jsResult to execute currentTab javascript "\(seekJS)"
                                    if jsResult is "OK" then return "DONE"
                                \(titleEnd)
                            end try
                        end repeat
                    end repeat
                end tell
            end if
            """
            if let result = runAppleScript(script), result == "DONE" { return }
        }
        
        // Safari
        if isAppRunning("Safari") {
            let titleCheck = hasTarget
                ? "if name of currentTab contains \"\(escapedTitle)\" then"
                : "if true then"
            let titleEnd = "end if"
            
            let script = """
            if application "Safari" is running then
                tell application "Safari"
                    set windowCount to count of windows
                    repeat with w from 1 to windowCount
                        set tabCount to count of tabs of window w
                        repeat with t from 1 to tabCount
                            try
                                set currentTab to tab t of window w
                                \(titleCheck)
                                    set jsResult to do JavaScript "\(seekJS)" in currentTab
                                    if jsResult is "OK" then return "DONE"
                                \(titleEnd)
                            end try
                        end repeat
                    end repeat
                end tell
            end if
            """
            _ = runAppleScript(script)
        }
    }
    
    // MARK: - CGEvent Media Key Simulation
    
    private func sendMediaKeyEvent(keyType: Int) {
        let NX_KEYTYPE = keyType
        
        let keyDown = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: 0xa00),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: (NX_KEYTYPE << 16) | (0xa << 8),
            data2: -1
        )
        
        let keyUp = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: 0xb00),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: (NX_KEYTYPE << 16) | (0xb << 8),
            data2: -1
        )
        
        if let downEvent = keyDown?.cgEvent {
            downEvent.post(tap: .cghidEventTap)
        }
        if let upEvent = keyUp?.cgEvent {
            upEvent.post(tap: .cghidEventTap)
        }
    }
    
    // MARK: - Fetch Now Playing (Son Çalan Kazanır — Active Override)
    
    private func fetchNowPlaying() {
        var candidates: [MediaInfo] = []
        
        // 1️⃣ MediaRemote (sistem seviyesi — global)
        if mediaRemoteLoaded {
            if let info = fetchFromMediaRemoteSync() {
                candidates.append(info)
            }
        }
        
        // 2️⃣ Spotify (native)
        if let info = fetchFromSpotify() {
            candidates.append(info)
        }
        
        // 3️⃣ Apple Music (native)
        if let info = fetchFromAppleMusic() {
            candidates.append(info)
        }
        
        // 4️⃣ Browser tabs (Chromium + Safari)
        let browserInfos = fetchFromBrowserTabs()
        candidates.append(contentsOf: browserInfos)
        
        // --- Çoklu Medya Listesini Güncelle ---
        // Playing veya paused olan eşsiz medyaları activeMediaList'e kaydet
        // mediaRemote, diğer kaynaklarla çoğu zaman duplikasyon yaratır → filtrele
        let activeCandidates = candidates.filter { $0.source != .mock && $0.source != .mediaRemote }
        var uniqueList: [MediaInfo] = []
        var seenKeys = Set<String>()
        for candidate in activeCandidates {
            let key = candidate.id
            if !seenKeys.contains(key) {
                seenKeys.insert(key)
                uniqueList.append(candidate)
            }
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.activeMediaList = uniqueList
        }
        
        // --- SON ÇALAN KAZANIR (Active Override) ---
        // Playing olanlar arasından en yüksek öncelikli kaynağı seç
        let playingCandidates = candidates.filter { $0.isPlaying }
        
        if let winner = playingCandidates.max(by: { $0.source < $1.source }) {
            // Çalan var → onu göster
            updateMediaInfo(winner)
            return
        }
        
        // Hiçbiri çalmıyor → en yüksek öncelikli paused kaynağı göster (eğer varsa)
        if let pausedWinner = candidates.max(by: { $0.source < $1.source }) {
            updateMediaInfo(pausedWinner)
            return
        }
        
        // Hiçbir kaynak bulunamadı → mock moda geç
        if !useMockData {
            useMockData = true
            DispatchQueue.main.async { [weak self] in
                self?.startMockMode()
            }
        }
    }
    
    private func updateMediaInfo(_ info: MediaInfo) {
        DispatchQueue.main.async { [weak self] in
            self?.useMockData = false
            self?.mockTimer?.invalidate()
            self?.mockTimer = nil
            self?.mediaInfo = info
            // Son bilinen medyayı sakla — idle expanded'da gösterilecek
            if info.source != .mock {
                self?.lastKnownMedia = info
            }
        }
    }
    
    // MARK: - MediaRemote (Private API — Senkron Wrapper)
    
    private func fetchFromMediaRemoteSync() -> MediaInfo? {
        guard let getInfo = MRMediaRemoteGetNowPlayingInfo else { return nil }
        
        let semaphore = DispatchSemaphore(value: 0)
        var fetchedInfo: MediaInfo?
        
        getInfo(DispatchQueue.global(qos: .userInitiated)) { [weak self] dict in
            guard let self = self else {
                semaphore.signal()
                return
            }
            
            let title = dict[self.kMRMediaRemoteNowPlayingInfoTitle] as? String
            let artist = dict[self.kMRMediaRemoteNowPlayingInfoArtist] as? String
            let playbackRate = dict[self.kMRMediaRemoteNowPlayingInfoPlaybackRate] as? Double
            
            if let title = title, !title.isEmpty {
                fetchedInfo = MediaInfo(
                    title: title,
                    artist: artist ?? "",
                    isPlaying: (playbackRate ?? 0) > 0,
                    source: .mediaRemote
                )
            }
            
            semaphore.signal()
        }
        
        let result = semaphore.wait(timeout: .now() + 0.5)
        return result == .success ? fetchedInfo : nil
    }
    
    // MARK: - Spotify AppleScript
    
    private func fetchFromSpotify() -> MediaInfo? {
        // 🛡️ Swift tarafında kontrol: Spotify açık mı?
        guard isAppRunning("Spotify") else { return nil }
        
        let script = """
        if application "Spotify" is running then
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
        else
            return "NOT_RUNNING"
        end if
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
            isPlaying: parts[2] == "PLAYING",
            source: .spotify
        )
    }
    
    // MARK: - Apple Music AppleScript
    
    private func fetchFromAppleMusic() -> MediaInfo? {
        // 🛡️ Swift tarafında kontrol: Music açık mı?
        guard isAppRunning("Music") else { return nil }
        
        let script = """
        if application "Music" is running then
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
        else
            return "NOT_RUNNING"
        end if
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
            isPlaying: parts[2] == "PLAYING",
            source: .appleMusic
        )
    }
    
    // MARK: - Browser Media Detection (JavaScript Injection)
    
    /// JavaScript kodu: Sayfadaki tüm video/audio elementlerini tarayıp oynatma durumunu döndürür
    private let mediaDetectionJS = "(function(){ var elems = document.querySelectorAll('video, audio'); for(var i=0; i<elems.length; i++){ if(!elems[i].paused && elems[i].duration > 0) return 'PLAYING'; } if(elems.length > 0) return 'PAUSED'; return 'NO_MEDIA'; })();"
    
    private func fetchFromBrowserTabs() -> [MediaInfo] {
        var results: [MediaInfo] = []
        
        let chromiumBrowsers = [
            "Google Chrome",
            "Brave Browser",
            "Microsoft Edge",
            "Arc",
            "Opera"
        ]
        
        // 🛡️ Sadece açık olan tarayıcıları sorgula
        for appName in chromiumBrowsers {
            guard isAppRunning(appName) else { continue }
            let infos = fetchFromChromiumBrowser(appName: appName)
            results.append(contentsOf: infos)
        }
        
        // Safari (farklı AppleScript API)
        if isAppRunning("Safari") {
            let infos = fetchFromSafari()
            results.append(contentsOf: infos)
        }
        
        return results
    }
    
    // MARK: - Chromium Browsers (Chrome, Brave, Edge, Arc, Opera)
    
    /// Tüm pencere ve sekmeleri gezerek JavaScript ile HTML5 media durumunu kontrol eder.
    /// Playing veya Paused olan tüm sekmelerin bilgilerini toplar ve döndürür.
    private func fetchFromChromiumBrowser(appName: String) -> [MediaInfo] {
        let script = """
        if application "\(appName)" is running then
            tell application "\(appName)"
                set windowCount to count of windows
                if windowCount is 0 then return "NO_MEDIA"
                
                set foundMedia to ""
                
                repeat with w from 1 to windowCount
                    set tabCount to count of tabs of window w
                    repeat with t from 1 to tabCount
                        set currentTab to tab t of window w
                        try
                            set jsResult to execute currentTab javascript "\(mediaDetectionJS)"
                            if jsResult is "PLAYING" then
                                set tabTitle to title of currentTab
                                set foundMedia to foundMedia & tabTitle & "|||PLAYING###"
                            else if jsResult is "PAUSED" then
                                set tabTitle to title of currentTab
                                set foundMedia to foundMedia & tabTitle & "|||PAUSED###"
                            end if
                        end try
                    end repeat
                end repeat
                
                if foundMedia is not "" then
                    return foundMedia
                else
                    return "NO_MEDIA"
                end if
            end tell
        else
            return "NOT_RUNNING"
        end if
        """
        
        guard let result = runAppleScript(script),
              !result.contains("NOT_RUNNING"),
              !result.contains("NO_MEDIA") else {
            return []
        }
        
        return parseBrowserJSResults(result)
    }
    
    // MARK: - Safari (Farklı AppleScript API — do JavaScript)
    
    private func fetchFromSafari() -> [MediaInfo] {
        let script = """
        if application "Safari" is running then
            tell application "Safari"
                set windowCount to count of windows
                if windowCount is 0 then return "NO_MEDIA"
                
                set foundMedia to ""
                
                repeat with w from 1 to windowCount
                    set tabCount to count of tabs of window w
                    repeat with t from 1 to tabCount
                        set currentTab to tab t of window w
                        try
                            set jsResult to do JavaScript "\(mediaDetectionJS)" in currentTab
                            if jsResult is "PLAYING" then
                                set tabTitle to name of currentTab
                                set foundMedia to foundMedia & tabTitle & "|||PLAYING###"
                            else if jsResult is "PAUSED" then
                                set tabTitle to name of currentTab
                                set foundMedia to foundMedia & tabTitle & "|||PAUSED###"
                            end if
                        end try
                    end repeat
                end repeat
                
                if foundMedia is not "" then
                    return foundMedia
                else
                    return "NO_MEDIA"
                end if
            end tell
        else
            return "NOT_RUNNING"
        end if
        """
        
        guard let result = runAppleScript(script),
              !result.contains("NOT_RUNNING"),
              !result.contains("NO_MEDIA") else {
            return []
        }
        
        return parseBrowserJSResults(result)
    }
    
    // MARK: - Browser Result Parser
    
    /// "Tab Title|||PLAYING###Tab 2|||PAUSED###" formatını parse eder ve diziye çevirir
    private func parseBrowserJSResults(_ result: String) -> [MediaInfo] {
        var mediaList: [MediaInfo] = []
        
        let tabResults = result.components(separatedBy: "###")
        
        for tabResult in tabResults {
            if tabResult.isEmpty { continue }
            
            let parts = tabResult.components(separatedBy: "|||")
            guard parts.count >= 2 else { continue }
            
            let rawTitle = parts[0]
            let state = parts[1]
            let isPlaying = (state == "PLAYING")
            
            // Tab başlığından şarkı/sanatçı bilgisini çıkar
            let parsed = parseMediaTitle(rawTitle)
            
            let info = MediaInfo(
                title: parsed.title,
                artist: parsed.artist,
                isPlaying: isPlaying,
                source: .browserTab
            )
            mediaList.append(info)
        }
        
        return mediaList
    }
    
    /// Tab başlığından şarkı adı ve sanatçı bilgisini ayıklar
    private func parseMediaTitle(_ title: String) -> (title: String, artist: String) {
        var cleanTitle = title
        
        // Sondaki platform isimlerini temizle
        let suffixes = [" - YouTube", " - YouTube Music", " | Spotify",
                       " — Spotify — Web Player", " - SoundCloud",
                       " | Apple Music", " - Deezer", " | TIDAL",
                       " - Vimeo", " | Bandcamp", " | Pandora"]
        for suffix in suffixes {
            if cleanTitle.hasSuffix(suffix) {
                cleanTitle = String(cleanTitle.dropLast(suffix.count))
                break
            }
        }
        
        // "Şarkı - Sanatçı" formatını ayır
        let separators = [" - ", " — ", " • ", " | "]
        for separator in separators {
            let parts = cleanTitle.components(separatedBy: separator)
            if parts.count >= 2 {
                return (
                    title: parts[0].trimmingCharacters(in: .whitespaces),
                    artist: parts[1].trimmingCharacters(in: .whitespaces)
                )
            }
        }
        
        // Ayıraç bulunamadı
        return (
            title: cleanTitle.trimmingCharacters(in: .whitespaces),
            artist: "Web"
        )
    }
    
    // MARK: - Mock Mode
    
    private func startMockMode() {
        showMockTrack()
        
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
                isPlaying: true,
                source: .mock
            )
        }
    }
    
    private func advanceMockTrack() {
        mockIndex = (mockIndex + 1) % mockTracks.count
        showMockTrack()
    }
    
    // MARK: - Running App Check (NSWorkspace)
    
    /// Uygulama adı ile bundle ID eşleştirmesi yaparak o an çalışıp çalışmadığını kontrol eder.
    /// Eğer bundle ID eşleştirmesi yoksa, process adı ile kontrol eder.
    private func isAppRunning(_ appName: String) -> Bool {
        let runningApps = NSWorkspace.shared.runningApplications
        
        // Önce bundle ID ile kontrol et (en güvenilir)
        if let bundleID = appBundleIDs[appName] {
            return runningApps.contains { $0.bundleIdentifier == bundleID }
        }
        
        // Bundle ID yoksa localizedName ile kontrol et
        return runningApps.contains { $0.localizedName == appName }
    }
    
    // MARK: - AppleScript String Escaping
    
    /// AppleScript string literal'lerini bozan karakterleri escape eder.
    /// `\` → `\\`, `"` → `\"` dönüşümü yapar.
    private func escapeForAppleScript(_ text: String) -> String {
        return text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
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
