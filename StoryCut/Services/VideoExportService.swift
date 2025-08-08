import Foundation
import AVFoundation
import AVKit
import Combine

class VideoExportService: ObservableObject {
    @Published var isExporting = false
    @Published var exportProgress: Double = 0.0
    
    /// Production export: builds a composition from a list of clips and writes an H.264 MP4 into Documents.
    /// The resulting URL is suitable for sharing/saving.
    func exportVideo(
        project: VideoProject,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        isExporting = true
        exportProgress = 0.0
        
        Task {
            do {
                let exportedURL = try await processProject(project: project)
                
                await MainActor.run {
                    self.isExporting = false
                    self.exportProgress = 1.0
                    completion(.success(exportedURL))
                }
            } catch {
                await MainActor.run {
                    self.isExporting = false
                    completion(.failure(error))
                }
            }
        }
    }
    
    private func processProject(project: VideoProject) async throws -> URL {
        guard project.clips.isEmpty == false else { throw VideoExportError.noVideoTrack }

        // Build composition from clips
        let composition = AVMutableComposition()
        let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        var cursor: CMTime = .zero
        for clip in project.clips {
            let asset = AVURLAsset(url: clip.videoURL)
            guard let srcTrack = try await asset.loadTracks(withMediaType: .video).first else { continue }
            let timeRange = CMTimeRange(start: clip.startTime, duration: clip.duration)
            try videoTrack?.insertTimeRange(timeRange, of: srcTrack, at: cursor)
            cursor = CMTimeAdd(cursor, clip.duration)
        }

        // Export to a file
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw VideoExportError.exportSessionCreationFailed
        }
        let outputURL = createOutputURL()
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true

        // Progress polling
        Task.detached { [weak self] in
            while exportSession.status == .waiting || exportSession.status == .exporting {
                let p = Double(exportSession.progress)
                await MainActor.run { self?.exportProgress = p }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }

        await exportSession.export()
        if exportSession.status == .completed { return outputURL }
        throw VideoExportError.exportFailed(exportSession.error)
    }
    
    // Removed per production export (we choose preset by quality later if needed)
    
    private func createVideoComposition(
        for composition: AVComposition,
        platform: SocialPlatform
    ) -> AVMutableVideoComposition {
        // Note: AVMutableVideoComposition is deprecated but still functional
        // In a production app, this should be updated to use AVVideoComposition.Configuration
        let videoComposition = AVMutableVideoComposition()
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        
        // Set render size based on platform
        let renderSize = getRenderSize(for: platform)
        videoComposition.renderSize = renderSize
        
        // Create instruction
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
        
        if let firstTrack = composition.tracks.first {
            let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: firstTrack)
            
            // Calculate transform for aspect ratio
            let transform = calculateTransform(for: platform, renderSize: renderSize)
            layerInstruction.setTransform(transform, at: .zero)
            
            instruction.layerInstructions = [layerInstruction]
        }
        
        videoComposition.instructions = [instruction]
        
        return videoComposition
    }
    
    private func getRenderSize(for platform: SocialPlatform) -> CGSize {
        switch platform {
        case .tikTok, .instagram:
            return CGSize(width: 1080, height: 1920) // 9:16
        case .youtube:
            return CGSize(width: 1920, height: 1080) // 16:9
        case .twitter, .facebook, .linkedin:
            return CGSize(width: 1080, height: 1080) // 1:1
        }
    }
    
    private func calculateTransform(for platform: SocialPlatform, renderSize: CGSize) -> CGAffineTransform {
        // This is a simplified transform calculation
        // In a real implementation, you would calculate the proper transform
        // based on the source video dimensions and target aspect ratio
        return CGAffineTransform.identity
    }
    
    private func createOutputURL() -> URL {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileName = "storycut_export_\(Int(Date().timeIntervalSince1970)).mp4"
        return documentsDirectory.appendingPathComponent(fileName)
    }
}

// MARK: - Video Export Error
enum VideoExportError: LocalizedError {
    case noVideoTrack
    case exportSessionCreationFailed
    case exportFailed(Error?)
    
    var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            return "No video track found in the selected file"
        case .exportSessionCreationFailed:
            return "Failed to create export session"
        case .exportFailed(let error):
            return "Export failed: \(error?.localizedDescription ?? "Unknown error")"
        }
    }
}

// MARK: - Social Media Integration
extension VideoExportService {
    func shareToSocialMedia(
        videoURL: URL,
        platform: SocialPlatform,
        completion: @escaping (Bool) -> Void
    ) {
        // In a real implementation, you would integrate with social media APIs
        // For now, we'll simulate the sharing process
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            completion(true)
        }
    }
    
    func generateHashtags(for platform: SocialPlatform) -> [String] {
        switch platform {
        case .tikTok:
            return ["#fyp", "#viral", "#trending", "#storycut"]
        case .instagram:
            return ["#reels", "#instagram", "#viral", "#storycut"]
        case .youtube:
            return ["#shorts", "#youtube", "#viral", "#storycut"]
        case .twitter:
            return ["#video", "#twitter", "#viral", "#storycut"]
        case .facebook:
            return ["#facebook", "#video", "#viral", "#storycut"]
        case .linkedin:
            return ["#linkedin", "#professional", "#content", "#storycut"]
        }
    }
    
    func generateCaption(for platform: SocialPlatform) -> String {
        switch platform {
        case .tikTok:
            return "Check out this amazing video! 🎬✨ #fyp #viral"
        case .instagram:
            return "Just created this with StoryCut! 📱✨ #reels #instagram"
        case .youtube:
            return "New video alert! 🎥🔥 #shorts #youtube"
        case .twitter:
            return "Just made this video with StoryCut! 📱✨ #video #twitter"
        case .facebook:
            return "Check out my latest video! 🎬✨ #facebook #video"
        case .linkedin:
            return "Professional content created with StoryCut 📱✨ #linkedin #content"
        }
    }
} 