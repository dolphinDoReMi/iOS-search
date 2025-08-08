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
        preset: ExportPreset? = nil,
        quality: ExportQuality? = nil,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        isExporting = true
        exportProgress = 0.0
        
        Task {
            do {
                let exportedURL = try await processProject(project: project, preset: preset, quality: quality)
                
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
    
    private func processProject(project: VideoProject, preset: ExportPreset?, quality: ExportQuality?) async throws -> URL {
        guard project.clips.isEmpty == false else { throw VideoExportError.noVideoTrack }

        // Build composition from clips
        let composition = AVMutableComposition()
        let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        var cursor: CMTime = .zero
        
        // Create audio mix for volume control
        let audioMix = AVMutableAudioMix()
        var audioParams: [AVMutableAudioMixInputParameters] = []
        
        // Capture source dimensions from the first clip for sizing transforms
        var sourceNaturalSize: CGSize = .zero
        var sourcePreferredTransform: CGAffineTransform = .identity

        for (index, clip) in project.clips.enumerated() {
            let asset = AVURLAsset(url: clip.videoURL)
            
            // Load video track
            if let srcTrack = try await asset.loadTracks(withMediaType: .video).first {
                if index == 0 {
                    sourceNaturalSize = try await srcTrack.load(.naturalSize)
                    sourcePreferredTransform = try await srcTrack.load(.preferredTransform)
                }
                let timeRange = CMTimeRange(start: clip.startTime, duration: clip.duration)
                try videoTrack?.insertTimeRange(timeRange, of: srcTrack, at: cursor)
            }
            
            // Load audio track
            if let srcAudioTrack = try await asset.loadTracks(withMediaType: .audio).first {
                let timeRange = CMTimeRange(start: clip.startTime, duration: clip.duration)
                try audioTrack?.insertTimeRange(timeRange, of: srcAudioTrack, at: cursor)
                
                // Set volume for this segment
                let params = AVMutableAudioMixInputParameters(track: audioTrack)
                params.setVolume(clip.volume, at: cursor)
                params.setVolumeRamp(fromStartVolume: clip.volume, toEndVolume: clip.volume, timeRange: timeRange)
                audioParams.append(params)
            }
            
            cursor = CMTimeAdd(cursor, clip.duration)
        }
        
        // Apply audio mix if we have parameters
        if !audioParams.isEmpty {
            audioMix.inputParameters = audioParams
        }

        // Set up export session
        // Choose export preset by desired quality if provided
        let exportPresetName: String
        switch quality ?? .high {
        case .high:
            exportPresetName = AVAssetExportPresetHighestQuality
        case .medium:
            exportPresetName = AVAssetExportPreset1280x720
        case .low:
            exportPresetName = AVAssetExportPreset640x480
        }

        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: exportPresetName
        ) else {
            throw VideoExportError.exportSessionCreationFailed
        }
        
        // Create output URL in Documents
        let outputURL = createOutputURL()
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        
        // Configure export
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        exportSession.audioMix = audioMix // Apply our audio mix
        
        // If a platform preset is provided, enforce duration limit and output geometry
        if let preset = preset {
            // Limit duration without changing speed
            if let limit = preset.maxDurationSeconds {
                let maxDuration = CMTime(seconds: Double(limit), preferredTimescale: 600)
                if composition.duration > maxDuration {
                    exportSession.timeRange = CMTimeRange(start: .zero, duration: maxDuration)
                }
            }

            // Apply video composition with target render size and frame rate
            let targetSize = preset.resolution
            let frameDuration = CMTime(value: 1, timescale: CMTimeScale(preset.frameRate))
            
            let videoComposition = AVMutableVideoComposition()
            videoComposition.renderSize = targetSize
            videoComposition.frameDuration = frameDuration
            
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
            if let compVideoTrack = videoTrack {
                let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compVideoTrack)
                
                // Compute aspect-fit transform from source to target
                let srcSize = CGSize(width: abs(sourceNaturalSize.width), height: abs(sourceNaturalSize.height))
                let scaleX = targetSize.width / max(srcSize.width, 1)
                let scaleY = targetSize.height / max(srcSize.height, 1)
                let scale = min(scaleX, scaleY) // aspect fit
                let scaledSize = CGSize(width: srcSize.width * scale, height: srcSize.height * scale)
                let translateX = (targetSize.width - scaledSize.width) / 2.0
                let translateY = (targetSize.height - scaledSize.height) / 2.0
                
                var transform = sourcePreferredTransform
                transform = transform.concatenating(CGAffineTransform(scaleX: scale, y: scale))
                transform = transform.concatenating(CGAffineTransform(translationX: translateX, y: translateY))
                
                layerInstruction.setTransform(transform, at: .zero)
                instruction.layerInstructions = [layerInstruction]
            }
            videoComposition.instructions = [instruction]
            exportSession.videoComposition = videoComposition
        }
        
        // Progress polling with more frequent updates
        Task.detached { [weak self] in
            while exportSession.status == .waiting || exportSession.status == .exporting {
                let p = Double(exportSession.progress)
                await MainActor.run { self?.exportProgress = p }
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s for smoother updates
            }
        }
        
        // Perform export
        await exportSession.export()
        
        switch exportSession.status {
        case .completed:
            print("Export completed successfully. File saved to: \(outputURL.path)")
            return outputURL
        case .failed:
            throw VideoExportError.exportFailed(exportSession.error)
        case .cancelled:
            throw VideoExportError.exportFailed(NSError(domain: "StoryCut", code: -1, userInfo: [NSLocalizedDescriptionKey: "Export was cancelled"]))
        default:
            throw VideoExportError.exportFailed(NSError(domain: "StoryCut", code: -1, userInfo: [NSLocalizedDescriptionKey: "Export ended in unexpected state: \(exportSession.status)"]))
        }

        // Close async function
    }
    
    // Removed per production export (we choose preset by quality later if needed)
    
    func createOutputURL() -> URL {
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
}

// MARK: - Social Media Helpers
extension VideoExportService {
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