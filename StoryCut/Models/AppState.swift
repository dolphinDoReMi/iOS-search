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
    
    // Shared language input for edit intent
    @Published var editPrompt: String = ""
    
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
        switch self {
        case .reels:
            return 30 // Instagram Reels optimized
        default:
            return 30
        }
    }
    
    var codec: String {
        return "H.264"
    }

    var maxDurationSeconds: Int? {
        switch self {
        case .tikTok: return 60
        case .reels: return 90 // Instagram Reels max duration
        case .shorts: return 60
        case .custom: return nil
        }
    }
    
    // IG Reels specific settings
    var recommendedBitrate: Int {
        switch self {
        case .reels:
            return 5000000 // 5 Mbps for high quality IG Reels
        default:
            return 4000000
        }
    }
    
    var audioCodec: String {
        return "AAC"
    }
    
    var audioSampleRate: Int {
        return 48000
    }
    
    var audioChannels: Int {
        return 2
    }
    
    // IG Reels optimization settings
    var igOptimizations: IGReelsOptimizations {
        switch self {
        case .reels:
            return IGReelsOptimizations(
                enableAutoEnhancement: true,
                enableSmartCropping: true,
                enableAudioNormalization: true,
                enableMotionStabilization: true,
                recommendedHashtags: true,
                autoGenerateCaption: true
            )
        default:
            return IGReelsOptimizations()
        }
    }
}

// MARK: - IG Reels Optimizations
struct IGReelsOptimizations: Codable {
    var enableAutoEnhancement: Bool = false
    var enableSmartCropping: Bool = false
    var enableAudioNormalization: Bool = false
    var enableMotionStabilization: Bool = false
    var recommendedHashtags: Bool = false
    var autoGenerateCaption: Bool = false
    var targetEngagementScore: Float = 0.8
    var preferredMusicGenre: String = "trending"
    var autoAddTransitions: Bool = true
    var optimizeForDiscovery: Bool = true
}

enum ExportQuality: String, CaseIterable, Codable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case ultra = "Ultra" // For IG Reels
    
    var bitrate: Int {
        switch self {
        case .low: return 1000000
        case .medium: return 2000000
        case .high: return 4000000
        case .ultra: return 5000000 // IG Reels optimized
        }
    }
    
    var description: String {
        switch self {
        case .low: return "Fast export, smaller file"
        case .medium: return "Good balance"
        case .high: return "High quality"
        case .ultra: return "IG Reels optimized"
        }
    }
} 