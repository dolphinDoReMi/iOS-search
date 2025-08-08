import SwiftUI

// MARK: - Social Platform
enum SocialPlatform: String, CaseIterable {
    case tikTok = "TikTok"
    case instagram = "Instagram"
    case youtube = "YouTube"
    case twitter = "Twitter"
    case facebook = "Facebook"
    case linkedin = "LinkedIn"
    
    var displayName: String {
        switch self {
        case .tikTok: return "TikTok"
        case .instagram: return "Instagram"
        case .youtube: return "YouTube"
        case .twitter: return "Twitter"
        case .facebook: return "Facebook"
        case .linkedin: return "LinkedIn"
        }
    }
    
    var aspectRatio: String {
        switch self {
        case .tikTok, .instagram:
            return "9:16"
        case .youtube:
            return "16:9"
        case .twitter, .facebook, .linkedin:
            return "1:1"
        }
    }
    
    var maxDuration: Int {
        switch self {
        case .tikTok: return 60
        case .instagram: return 90
        case .youtube: return 60
        case .twitter: return 140
        case .facebook: return 240
        case .linkedin: return 600
        }
    }
    
    var iconName: String {
        switch self {
        case .tikTok: return "music.note"
        case .instagram: return "camera"
        case .youtube: return "play.rectangle"
        case .twitter: return "bird"
        case .facebook: return "f.square"
        case .linkedin: return "l.square"
        }
    }
    
    var color: Color {
        switch self {
        case .tikTok: return .black
        case .instagram: return .purple
        case .youtube: return .red
        case .twitter: return .blue
        case .facebook: return .blue
        case .linkedin: return .blue
        }
    }
} 