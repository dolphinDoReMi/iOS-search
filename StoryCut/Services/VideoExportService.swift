import Foundation
import AVFoundation
import AVKit
import Combine

@MainActor
class VideoExportService: ObservableObject {
    @Published var isExporting = false
    @Published var exportProgress: Double = 0.0
    
    nonisolated(unsafe) private var progressTimer: Timer?
    
    /// Production export: builds a composition from a list of clips and writes an H.264 MP4 into Documents.
    func exportVideo(
        project: VideoProject,
        preset: ExportPreset? = nil,
        quality: ExportQuality? = nil,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        isExporting = true
        exportProgress = 0.0
        
        Task { @MainActor in
            do {
                let exportedURL = try await processProject(project: project, preset: preset, quality: quality)
                self.isExporting = false
                self.exportProgress = 1.0
                completion(.success(exportedURL))
            } catch {
                self.isExporting = false
                completion(.failure(error))
            }
        }
    }
    
    @available(iOS 18.0, macOS 15.0, *)
    private func observeStates(_ session: AVAssetExportSession) async {
        for await state in session.states(updateInterval: 0.1) {
            switch state {
            case .exporting(progress: let p):
                exportProgress = p.fractionCompleted
            default:
                break
            }
        }
    }
    
    private func startProgressTimer(for session: AVAssetExportSession) {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(timeInterval: 0.1, target: self, selector: #selector(updateProgress(_:)), userInfo: session, repeats: true)
        RunLoop.main.add(progressTimer!, forMode: .common)
    }
    
    @objc private func updateProgress(_ timer: Timer) {
        guard let session = timer.userInfo as? AVAssetExportSession else { return }
        Task { @MainActor in
            self.exportProgress = Double(session.progress)
        }
    }
    
    private func processProject(project: VideoProject, preset: ExportPreset?, quality: ExportQuality?) async throws -> URL {
        guard project.clips.isEmpty == false else { throw VideoExportError.noVideoTrack }

        // Build composition
        let composition = AVMutableComposition()
        let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        var cursor: CMTime = .zero
        let audioMix = AVMutableAudioMix()
        let audioParams = AVMutableAudioMixInputParameters()
        // Set to composition audio track ID
        audioParams.trackID = audioTrack?.trackID ?? kCMPersistentTrackID_Invalid
        var sourceNaturalSize: CGSize = .zero
        var sourcePreferredTransform: CGAffineTransform = .identity

        for (index, clip) in project.clips.enumerated() {
            let asset = AVURLAsset(url: clip.videoURL)
            if let srcTrack = try await asset.loadTracks(withMediaType: .video).first {
                if index == 0 {
                    sourceNaturalSize = try await srcTrack.load(.naturalSize)
                    sourcePreferredTransform = try await srcTrack.load(.preferredTransform)
                }
                let timeRange = CMTimeRange(start: clip.startTime, duration: clip.duration)
                try videoTrack?.insertTimeRange(timeRange, of: srcTrack, at: cursor)
            }
            if let srcAudioTrack = try await asset.loadTracks(withMediaType: .audio).first {
                let timeRange = CMTimeRange(start: clip.startTime, duration: clip.duration)
                try audioTrack?.insertTimeRange(timeRange, of: srcAudioTrack, at: cursor)
                audioParams.setVolume(clip.volume, at: cursor)
                audioParams.setVolumeRamp(fromStartVolume: clip.volume, toEndVolume: clip.volume, timeRange: timeRange)
            }
            cursor = CMTimeAdd(cursor, clip.duration)
        }
        audioMix.inputParameters = [audioParams]

        // Choose export preset
        let exportPresetName: String
        switch quality ?? .high {
        case .ultra, .high: exportPresetName = AVAssetExportPresetHighestQuality
        case .medium: exportPresetName = AVAssetExportPreset1280x720
        case .low: exportPresetName = AVAssetExportPreset640x480
        }

        guard let exportSession = AVAssetExportSession(asset: composition, presetName: exportPresetName) else {
            throw VideoExportError.exportSessionCreationFailed
        }

        let outputURL = createOutputURL()
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        exportSession.audioMix = audioMix

        if let preset = preset {
            if let limit = preset.maxDurationSeconds {
                let maxDuration = CMTime(seconds: Double(limit), preferredTimescale: 600)
                if composition.duration > maxDuration {
                    exportSession.timeRange = CMTimeRange(start: .zero, duration: maxDuration)
                }
            }
            let targetSize = preset.resolution
            let frameDuration = CMTime(value: 1, timescale: CMTimeScale(preset.frameRate))
            
            // Use legacy approach since AVVideoComposition.Construction API might not be fully available
            let videoComposition = AVMutableVideoComposition()
            videoComposition.renderSize = targetSize
            videoComposition.frameDuration = frameDuration
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
            if let compVideoTrack = videoTrack {
                let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compVideoTrack)
                let srcSize = CGSize(width: abs(sourceNaturalSize.width), height: abs(sourceNaturalSize.height))
                let scaleX = targetSize.width / max(srcSize.width, 1)
                let scaleY = targetSize.height / max(srcSize.height, 1)
                let scale = min(scaleX, scaleY)
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

        // Modern export API (iOS 18/macOS 15+)
        if #available(iOS 18.0, macOS 15.0, *) {
            async let observer: Void = observeStates(exportSession)
            do {
                try await exportSession.export(to: outputURL, as: .mp4)
                _ = await observer
                return outputURL
            } catch {
                _ = await observer
                throw VideoExportError.exportFailed(error)
            }
        } else {
            // Legacy path for older OS versions
            startProgressTimer(for: exportSession)
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                // Capture session in a way that avoids Sendable issues
                let session = exportSession
                session.exportAsynchronously { [weak self] in
                    Task { @MainActor in
                        self?.progressTimer?.invalidate()
                        let status = session.status
                        let error = session.error
                        
                        switch status {
                        case .completed:
                            continuation.resume()
                        case .failed, .cancelled:
                            if let error = error {
                                continuation.resume(throwing: error)
                            } else {
                                continuation.resume(throwing: NSError(domain: "StoryCut", code: -1, userInfo: [NSLocalizedDescriptionKey: "Export failed"]))
                            }
                        default:
                            continuation.resume(throwing: NSError(domain: "StoryCut", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unexpected export status: \(status.rawValue)"]))
                        }
                    }
                }
            }
        }
        return outputURL
    }
    
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