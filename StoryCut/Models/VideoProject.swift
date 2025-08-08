import Foundation
import AVFoundation
import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Video Project
struct VideoProject: Identifiable, Codable {
    let id = UUID()
    var name: String
    var clips: [EditableClip]
    var audioTracks: [AudioTrack]
    var subtitles: [SubtitleLine]
    var exportSettings: ExportSettings
    var createdAt: Date
    var modifiedAt: Date
    
    init(name: String = "Untitled Project") {
        self.name = name
        self.clips = []
        self.audioTracks = []
        self.subtitles = []
        self.exportSettings = ExportSettings()
        self.createdAt = Date()
        self.modifiedAt = Date()
    }
    
    var totalDuration: CMTime {
        clips.reduce(CMTime.zero) { total, clip in
            CMTimeAdd(total, clip.duration)
        }
    }
}

// MARK: - Editable Clip
struct EditableClip: Identifiable, Codable, Equatable {
    var id = UUID()
    var videoURL: URL
    var startTime: CMTime
    var endTime: CMTime
    var audioOffset: CMTime // For L/J cuts
    var volume: Float
    var speed: Float
    var filters: [VideoFilter]
    
    var duration: CMTime {
        CMTimeSubtract(endTime, startTime)
    }
    
    init(videoURL: URL, startTime: CMTime = .zero, endTime: CMTime? = nil) {
        self.videoURL = videoURL
        self.startTime = startTime
        self.endTime = endTime ?? CMTime(seconds: 10, preferredTimescale: 600)
        self.audioOffset = .zero
        self.volume = 1.0
        self.speed = 1.0
        self.filters = []
    }
    
    static func == (lhs: EditableClip, rhs: EditableClip) -> Bool {
        return lhs.id == rhs.id &&
               lhs.videoURL == rhs.videoURL &&
               CMTimeCompare(lhs.startTime, rhs.startTime) == 0 &&
               CMTimeCompare(lhs.endTime, rhs.endTime) == 0 &&
               CMTimeCompare(lhs.audioOffset, rhs.audioOffset) == 0 &&
               lhs.volume == rhs.volume &&
               lhs.speed == rhs.speed &&
               lhs.filters == rhs.filters
    }
}

// MARK: - Audio Track
struct AudioTrack: Identifiable, Codable {
    var id = UUID()
    var audioURL: URL
    var startTime: CMTime
    var endTime: CMTime
    var volume: Float
    var isMuted: Bool
    
    var duration: CMTime {
        CMTimeSubtract(endTime, startTime)
    }
}

// MARK: - Subtitle Line
struct SubtitleLine: Identifiable, Codable {
    var id = UUID()
    var text: String
    var startTime: CMTime
    var endTime: CMTime
    var style: SubtitleStyle
    
    var duration: CMTime {
        CMTimeSubtract(endTime, startTime)
    }
}

struct SubtitleStyle: Codable {
    var fontSize: CGFloat = 24
    var fontColorName: String = "white"
    var backgroundColorName: String = "black"
    var fontFamily: String = "SF Pro"
    var alignmentString: String = "center"
    
    var fontColor: Color {
        Color(fontColorName)
    }
    
    var backgroundColor: Color {
        Color(backgroundColorName).opacity(0.7)
    }
    
    var alignment: TextAlignment {
        switch alignmentString {
        case "leading": return .leading
        case "trailing": return .trailing
        default: return .center
        }
    }
}

// MARK: - Video Filter
struct VideoFilter: Identifiable, Codable, Equatable {
    var id = UUID()
    var type: FilterType
    var intensity: Float
    
    enum FilterType: String, CaseIterable, Codable, Equatable {
        case brightness = "Brightness"
        case contrast = "Contrast"
        case saturation = "Saturation"
        case blur = "Blur"
        case sharpen = "Sharpen"
    }
}

// MARK: - Export Settings
struct ExportSettings: Codable {
    var preset: ExportPreset = .tikTok
    var quality: ExportQuality = .high
    var includeWatermark: Bool = false
    var watermarkText: String = "StoryCut"
    var autoGenerateThumbnail: Bool = true
    var thumbnailTime: CMTime = .zero
}

// MARK: - CMTime Codable Extension
// Intentionally omitted here to avoid duplicate conformance when StoryCut is embedded.