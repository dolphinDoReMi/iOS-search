#if canImport(FoundationModels)
import Foundation
import FoundationModels
import AVFoundation
import Combine

// MARK: - IG Reels AI Analyzer
@MainActor
class IGReelsAIAnalyzer: ObservableObject {
    @Published var isAnalyzing = false
    @Published var analysisResult: IGReelsAnalysis?
    @Published var errorMessage: String?
    
    private let session = LanguageModelSession()
    
    // MARK: - Content Analysis
    func analyzeContent(for project: VideoProject) async {
        isAnalyzing = true
        errorMessage = nil
        
        do {
            let analysis = try await performContentAnalysis(project: project)
            analysisResult = analysis
        } catch {
            errorMessage = "Analysis failed: \(error.localizedDescription)"
        }
        
        isAnalyzing = false
    }
    
    private func performContentAnalysis(project: VideoProject) async throws -> IGReelsAnalysis {
        let totalDuration = project.totalDuration.seconds
        let clipCount = project.clips.count
        let hasAudio = !project.audioTracks.isEmpty
        let hasSubtitles = !project.subtitles.isEmpty
        
        let result = try await session.respond(
            generating: IGReelsAnalysis.self,
            includeSchemaInPrompt: true
        ) {
            "Analyze this Instagram Reels video project for optimal engagement:"
            
            "Project Details:"
            "- Total Duration: \(String(format: "%.1f", totalDuration)) seconds"
            "- Number of Clips: \(clipCount)"
            "- Has Audio: \(hasAudio)"
            "- Has Subtitles: \(hasSubtitles)"
            "- Export Preset: Instagram Reels (9:16, 1080x1920, 30fps)"
            
            "Please provide:"
            "1. Engagement score prediction (0-1)"
            "2. Recommended hashtags (5-10 trending)"
            "3. Suggested caption"
            "4. Content optimization tips"
            "5. Best posting time recommendation"
            "6. Audio/music suggestions"
            "7. Visual enhancement recommendations"
            
            "Focus on Instagram Reels best practices and current trends."
        }
        
        return result.content
    }
    
    // MARK: - Caption Generation
    func generateCaption(for project: VideoProject) async throws -> String {
        let prompt = """
        Generate an engaging Instagram Reels caption for a \(String(format: "%.1f", project.totalDuration.seconds))-second video.
        
        Requirements:
        - Keep under 2200 characters
        - Include relevant emojis
        - Add call-to-action
        - Use trending hashtags
        - Make it shareable and engaging
        
        Generate a compelling caption that will drive engagement.
        """
        
        let response = try await session.respond(to: Prompt(prompt))
        return response.content
    }
    
    // MARK: - Hashtag Recommendations
    func generateHashtags(for project: VideoProject) async throws -> [String] {
        let prompt = """
        Generate 10 trending Instagram hashtags for a Reels video.
        
        Requirements:
        - Mix of trending and niche hashtags
        - Relevant to video content
        - Engagement-focused
        - Under 30 characters each
        - Include some viral/trending tags
        
        Return only the hashtag names, separated by commas.
        """
        
        let response = try await session.respond(to: Prompt(prompt))
        let hashtagsString = response.content
        return hashtagsString
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
    
    // MARK: - Optimization Suggestions
    func getOptimizationSuggestions(for project: VideoProject) async throws -> IGReelsOptimizationSuggestions {
        let result = try await session.respond(
            generating: IGReelsOptimizationSuggestions.self,
            includeSchemaInPrompt: true
        ) {
            "Analyze this Instagram Reels project and provide optimization suggestions:"
            
            "Project: \(project.name)"
            "Duration: \(String(format: "%.1f", project.totalDuration.seconds))s"
            "Clips: \(project.clips.count)"
            
            "Provide specific suggestions for:"
            "1. Visual improvements"
            "2. Audio enhancements"
            "3. Pacing adjustments"
            "4. Engagement optimization"
            "5. Trending elements to add"
        }
        
        return result.content
    }
}

// MARK: - IG Reels Analysis Models
@Generable
struct IGReelsAnalysis {
    @Guide(description: "Predicted engagement score from 0.0 to 1.0")
    let engagementScore: Float
    
    @Guide(description: "List of 5-10 trending hashtags for Instagram Reels")
    let recommendedHashtags: [String]
    
    @Guide(description: "Engaging caption under 2200 characters with emojis")
    let suggestedCaption: String
    
    @Guide(description: "3-5 specific optimization tips")
    let optimizationTips: [String]
    
    @Guide(description: "Best posting time (e.g., '6-8 PM EST')")
    let bestPostingTime: String
    
    @Guide(description: "Music genre or style recommendations")
    let musicSuggestions: [String]
    
    @Guide(description: "Visual enhancement recommendations")
    let visualEnhancements: [String]
    
    @Guide(description: "Content category or niche")
    let contentCategory: String
    
    @Guide(description: "Estimated reach potential (low/medium/high)")
    let reachPotential: String
}

@Generable
struct IGReelsOptimizationSuggestions {
    @Guide(description: "Visual improvement suggestions")
    let visualImprovements: [String]
    
    @Guide(description: "Audio enhancement recommendations")
    let audioEnhancements: [String]
    
    @Guide(description: "Pacing and timing adjustments")
    let pacingAdjustments: [String]
    
    @Guide(description: "Engagement optimization tips")
    let engagementOptimizations: [String]
    
    @Guide(description: "Trending elements to incorporate")
    let trendingElements: [String]
    
    @Guide(description: "Overall optimization score 0-100")
    let optimizationScore: Int
}

// MARK: - IG Reels Content Categories
enum IGReelsCategory: String, CaseIterable {
    case entertainment = "Entertainment"
    case education = "Education"
    case lifestyle = "Lifestyle"
    case fitness = "Fitness"
    case food = "Food"
    case travel = "Travel"
    case fashion = "Fashion"
    case beauty = "Beauty"
    case comedy = "Comedy"
    case dance = "Dance"
    case music = "Music"
    case gaming = "Gaming"
    case business = "Business"
    case technology = "Technology"
    case art = "Art"
    case sports = "Sports"
    case pets = "Pets"
    case diy = "DIY"
    case health = "Health"
    case news = "News"
    
    var trendingHashtags: [String] {
        switch self {
        case .entertainment:
            return ["#entertainment", "#viral", "#trending", "#funny", "#comedy"]
        case .education:
            return ["#education", "#learning", "#knowledge", "#tips", "#howto"]
        case .lifestyle:
            return ["#lifestyle", "#daily", "#routine", "#life", "#inspiration"]
        case .fitness:
            return ["#fitness", "#workout", "#gym", "#health", "#motivation"]
        case .food:
            return ["#food", "#cooking", "#recipe", "#delicious", "#foodie"]
        case .travel:
            return ["#travel", "#adventure", "#explore", "#wanderlust", "#vacation"]
        case .fashion:
            return ["#fashion", "#style", "#outfit", "#trending", "#ootd"]
        case .beauty:
            return ["#beauty", "#makeup", "#skincare", "#glow", "#aesthetic"]
        case .comedy:
            return ["#comedy", "#funny", "#humor", "#laugh", "#viral"]
        case .dance:
            return ["#dance", "#choreography", "#movement", "#rhythm", "#performance"]
        case .music:
            return ["#music", "#song", "#artist", "#melody", "#rhythm"]
        case .gaming:
            return ["#gaming", "#gamer", "#gameplay", "#esports", "#streamer"]
        case .business:
            return ["#business", "#entrepreneur", "#success", "#motivation", "#tips"]
        case .technology:
            return ["#tech", "#technology", "#innovation", "#gadgets", "#future"]
        case .art:
            return ["#art", "#creative", "#artist", "#design", "#inspiration"]
        case .sports:
            return ["#sports", "#athlete", "#training", "#competition", "#motivation"]
        case .pets:
            return ["#pets", "#animals", "#cute", "#adorable", "#petlife"]
        case .diy:
            return ["#diy", "#crafts", "#creative", "#handmade", "#project"]
        case .health:
            return ["#health", "#wellness", "#selfcare", "#mindfulness", "#healing"]
        case .news:
            return ["#news", "#currentevents", "#update", "#information", "#awareness"]
        }
    }
}
#endif
