import SwiftUI
import AVFoundation
#if os(macOS)
import AppKit
#endif

struct TimelineView: View {
    @EnvironmentObject var appState: AppState
    @State private var currentTime: CMTime = .zero
    @State private var isPlaying = false
    @State private var selectedClip: EditableClip?
    @State private var showingClipEditor = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Video Player
            VideoPlayerView(
                currentTime: $currentTime,
                isPlaying: $isPlaying,
                project: appState.currentProject
            )
            .frame(height: 300)
            
            // Timeline Controls
            TimelineControlsView(
                currentTime: $currentTime,
                isPlaying: $isPlaying,
                totalDuration: appState.currentProject?.totalDuration ?? .zero
            )
            .padding()
            
            // Timeline
            TimelineTrackView(
                project: appState.currentProject,
                currentTime: $currentTime,
                selectedClip: $selectedClip
            )
            .frame(height: 200)
            
            // Clip Properties
            if let selectedClip = selectedClip {
                ClipPropertiesView(clip: selectedClip)
                    .padding()
            }
        }
        .sheet(isPresented: $showingClipEditor) {
            if let clip = selectedClip {
                ClipEditorView(clip: clip)
            }
        }
        .onChange(of: selectedClip) { oldValue, newValue in
            showingClipEditor = newValue != nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .storycutUpdateClip)) { notification in
            guard var project = appState.currentProject,
                  let id = notification.userInfo?["clipId"] as? UUID,
                  let index = project.clips.firstIndex(where: { $0.id == id }) else { return }
            if let start = notification.userInfo?["start"] as? Double {
                project.clips[index].startTime = CMTime(seconds: start, preferredTimescale: 600)
            }
            if let end = notification.userInfo?["end"] as? Double {
                project.clips[index].endTime = CMTime(seconds: end, preferredTimescale: 600)
            }
            if let vol = notification.userInfo?["volume"] as? Float {
                project.clips[index].volume = vol
            }
            if let sp = notification.userInfo?["speed"] as? Float {
                project.clips[index].speed = sp
            }
            appState.currentProject = project
        }
    }
}

#if os(macOS)
// MARK: - Video Player View (macOS)
struct VideoPlayerView: NSViewRepresentable {
    @Binding var currentTime: CMTime
    @Binding var isPlaying: Bool
    let project: VideoProject?
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        let playerLayer = AVPlayerLayer()
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.frame = view.bounds
        view.layer?.addSublayer(playerLayer)
        context.coordinator.playerLayer = playerLayer
        context.coordinator.setupPlayer()
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.playerLayer?.frame = nsView.bounds
        if let project = project, !project.clips.isEmpty {
            context.coordinator.updateComposition(with: project)
        }
    }
    
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    
    class Coordinator: NSObject {
        var parent: VideoPlayerView
        var playerLayer: AVPlayerLayer?
        var player: AVPlayer?
        var timeObserver: Any?
        
        init(_ parent: VideoPlayerView) { self.parent = parent }
        
        func setupPlayer() {
            player = AVPlayer()
            playerLayer?.player = player
            timeObserver = player?.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
                queue: .main
            ) { [weak self] time in
                self?.parent.currentTime = time
            }
        }
        
        func updateComposition(with project: VideoProject) {
            Task {
                await MainActor.run {
                    let composition = AVMutableComposition()
                    let videoTrack = composition.addMutableTrack(
                        withMediaType: .video,
                        preferredTrackID: kCMPersistentTrackID_Invalid
                    )
                    var currentTime = CMTime.zero
                    Task {
                        for clip in project.clips {
                            let asset = AVURLAsset(url: clip.videoURL)
                            let assetTrack = try? await asset.loadTracks(withMediaType: .video).first
                            if let assetTrack = assetTrack {
                                try? videoTrack?.insertTimeRange(
                                    CMTimeRange(start: clip.startTime, duration: clip.duration),
                                    of: assetTrack,
                                    at: currentTime
                                )
                            }
                            currentTime = CMTimeAdd(currentTime, clip.duration)
                        }
                        await MainActor.run {
                            let playerItem = AVPlayerItem(asset: composition)
                            player?.replaceCurrentItem(with: playerItem)
                        }
                    }
                }
            }
        }
    }
}
#else
// MARK: - Video Player View (iOS)
import AVKit
struct VideoPlayerView: View {
    @Binding var currentTime: CMTime
    @Binding var isPlaying: Bool
    let project: VideoProject?
    
    @State private var player: AVPlayer = AVPlayer()
    @State private var timeObserver: Any?
    
    var body: some View {
        Group {
            if project?.clips.isEmpty == false {
                VideoPlayer(player: player)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.1))
                    .overlay(Image(systemName: "video").foregroundColor(.secondary))
            }
        }
        .onAppear { rebuildPlayerItem() }
        .onChange(of: project?.clips) { _, _ in rebuildPlayerItem() }
        .onChange(of: isPlaying) { _, playing in
            if playing { player.play() } else { player.pause() }
        }
        .onChange(of: currentTime) { _, newValue in
            let target = newValue
            player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        }
        .onDisappear {
            if let obs = timeObserver { player.removeTimeObserver(obs) }
            timeObserver = nil
            player.pause()
        }
    }
    
    private func rebuildPlayerItem() {
        guard let project else { return }
        let composition = AVMutableComposition()
        let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        var cursor: CMTime = .zero
        for clip in project.clips {
            let asset = AVURLAsset(url: clip.videoURL)
            if let src = try? awaitTrack(asset: asset) {
                let range = CMTimeRange(start: clip.startTime, duration: clip.duration)
                try? videoTrack?.insertTimeRange(range, of: src, at: cursor)
                cursor = CMTimeAdd(cursor, clip.duration)
            }
        }
        let item = AVPlayerItem(asset: composition)
        player.replaceCurrentItem(with: item)
        if timeObserver != nil { player.removeTimeObserver(timeObserver!) ; timeObserver = nil }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { time in
            currentTime = time
        }
        if isPlaying { player.play() }
    }
    
    private func awaitTrack(asset: AVURLAsset) -> AVAssetTrack? {
        var result: AVAssetTrack?
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            let track = try? await asset.loadTracks(withMediaType: .video).first
            result = track
            semaphore.signal()
        }
        semaphore.wait()
        return result
    }
}
#endif

// MARK: - Timeline Controls View
struct TimelineControlsView: View {
    @Binding var currentTime: CMTime
    @Binding var isPlaying: Bool
    let totalDuration: CMTime
    
    var body: some View {
        VStack(spacing: 16) {
            // Playback Controls
            HStack(spacing: 20) {
                Button(action: skipBackward) {
                    Image(systemName: "gobackward.15")
                        .font(.title2)
                }
                
                Button(action: togglePlayback) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title)
                        .foregroundColor(.accentColor)
                }
                
                Button(action: skipForward) {
                    Image(systemName: "goforward.15")
                        .font(.title2)
                }
            }
            
            // Time Slider
            VStack(spacing: 8) {
                HStack {
                    Text(timeString(from: currentTime))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text(timeString(from: totalDuration))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Slider(
                    value: Binding(
                        get: { currentTime.seconds },
                        set: { currentTime = CMTime(seconds: $0, preferredTimescale: 600) }
                    ),
                    in: 0...totalDuration.seconds
                )
                .accentColor(.accentColor)
            }
        }
    }
    
    private func togglePlayback() {
        isPlaying.toggle()
    }
    
    private func skipBackward() {
        let newTime = CMTimeSubtract(currentTime, CMTime(seconds: 15, preferredTimescale: 600))
        currentTime = CMTimeMaximum(newTime, .zero)
    }
    
    private func skipForward() {
        let newTime = CMTimeAdd(currentTime, CMTime(seconds: 15, preferredTimescale: 600))
        currentTime = CMTimeMinimum(newTime, totalDuration)
    }
    
    private func timeString(from time: CMTime) -> String {
        let seconds = Int(time.seconds)
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

// MARK: - Timeline Track View
struct TimelineTrackView: View {
    let project: VideoProject?
    @Binding var currentTime: CMTime
    @Binding var selectedClip: EditableClip?
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(project?.clips ?? [], id: \.id) { clip in
                    TimelineClipView(
                        clip: clip,
                        isSelected: selectedClip?.id == clip.id
                    ) {
                        selectedClip = clip
                    }
                }
            }
            .padding(.horizontal)
        }
        .background(Color.secondary.opacity(0.1))
    }
}

// MARK: - Timeline Clip View
struct TimelineClipView: View {
    let clip: EditableClip
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(isSelected ? Color.accentColor : Color.blue)
                    .frame(width: 60, height: 80)
                    .overlay(
                        Image(systemName: "video")
                            .foregroundColor(.white)
                    )
                
                Text(clip.videoURL.lastPathComponent)
                    .font(.caption2)
                    .lineLimit(1)
                    .frame(width: 60)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Clip Properties View
struct ClipPropertiesView: View {
    let clip: EditableClip
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Clip Properties")
                .font(.headline)
            
            HStack {
                Text("Duration:")
                Spacer()
                Text(String(format: "%.1fs", clip.duration.seconds))
            }
            
            HStack {
                Text("Volume:")
                Spacer()
                Slider(value: .constant(clip.volume), in: 0...1)
                    .frame(width: 100)
            }
            
            HStack {
                Text("Speed:")
                Spacer()
                Slider(value: .constant(clip.speed), in: 0.5...2.0)
                    .frame(width: 100)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }
}

#Preview {
    TimelineView()
        .environmentObject(AppState())
} 