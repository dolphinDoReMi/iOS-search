import SwiftUI
import AVFoundation
import Speech
import Combine

@MainActor
class AppState: ObservableObject {
    @Published var microphonePermission: Bool = false
    @Published var speechPermission: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    @Published var currentProject: VideoProject?
    @Published var isEditing: Bool = false
    @Published var selectedTab: EditorTab = .single
    
    // Export settings
    @Published var exportPreset: ExportPreset = .tikTok
    @Published var exportQuality: ExportQuality = .high
    
    // UI State
    @Published var showingPermissionAlert = false
    @Published var showingExportSheet = false
    
    enum EditorTab: String, CaseIterable {
        case single = "Create"
    }
}

// MARK: - Persistence (stubbed)
extension AppState {
    func persistCurrentProject() {
        // Placeholder persistence to keep UI responsive; integrate real storage later
        // e.g., JSON encode to Documents directory
    }
}

// MARK: - Notifications
extension Notification.Name {
    static let storycutUpdateClip = Notification.Name("storycut.updateClip")
}

// MARK: - Export Presets
enum ExportPreset: String, CaseIterable, Codable {
    case tikTok = "TikTok"
    case reels = "Instagram Reels"
    case shorts = "YouTube Shorts"
    case custom = "Custom"
    
    var aspectRatio: CGSize {
        switch self {
        case .tikTok, .reels, .shorts:
            return CGSize(width: 9, height: 16)
        case .custom:
            return CGSize(width: 16, height: 9) // Default to landscape
        }
    }
    
    var resolution: CGSize {
        switch self {
        case .tikTok:
            return CGSize(width: 1080, height: 1920)
        case .reels:
            return CGSize(width: 1080, height: 1920)
        case .shorts:
            return CGSize(width: 1080, height: 1920)
        case .custom:
            return CGSize(width: 1920, height: 1080)
        }
    }
    
    var frameRate: Int {
        return 30
    }
    
    var codec: String {
        return "H.264"
    }

    var maxDurationSeconds: Int? {
        switch self {
        case .tikTok: return 60
        case .reels: return 90
        case .shorts: return 60
        case .custom: return nil
        }
    }
}

enum ExportQuality: String, CaseIterable, Codable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    
    var bitrate: Int {
        switch self {
        case .low: return 1000000
        case .medium: return 2000000
        case .high: return 4000000
        }
    }
} 