import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
#if os(iOS)
import AVKit
#endif
#if os(macOS)
import AppKit
#endif

// MARK: - Transferable for Drag & Drop
struct ClipTransferable: Transferable, Codable {
    let clipId: UUID
    
    static var transferRepresentation: some TransferRepresentation {
        // Use a built-in content type to avoid declaring a custom UTI in Info.plist
        CodableRepresentation(for: ClipTransferable.self, contentType: .data)
    }
}

// File-scoped snapping helper so subviews can use it
private func snapTimeGlobal(_ t: CMTime, project: VideoProject?, currentTime: CMTime, threshold: Double = 0.1) -> CMTime {
    guard let clips = project?.clips else { return t }
    let times = clips.flatMap { [ $0.startTime, $0.endTime ] } + [currentTime]
    let target = t.seconds
    var best: CMTime = t
    var bestDiff = threshold
    for x in times {
        let d = abs(x.seconds - target)
        if d < bestDiff { bestDiff = d; best = x }
    }
    return best
}

struct TimelineView: View {
    @EnvironmentObject var appState: AppState
    @State private var currentTime: CMTime = .zero
    @State private var isPlaying = false
    @State private var selectedClip: EditableClip?
    @State private var showingClipEditor = false
    @State private var showDeleteConfirm = false
    @State private var selectionRange: CMTimeRange?
    
    var body: some View {
        VStack(spacing: 0) {
            // Video Player
            VideoPlayerView(
                currentTime: $currentTime,
                isPlaying: $isPlaying,
                project: appState.currentProject
            )
            .frame(height: 320)
            .frame(maxWidth: .infinity)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            
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
                totalDuration: appState.currentProject?.totalDuration ?? .zero,
                currentTime: $currentTime,
                selectedClip: $selectedClip,
                selectionRange: $selectionRange
            )
            .frame(height: 200)
            
            // Range edit toolbar
            if selectionRange != nil {
                RangeEditToolbar(
                    onTrimToRange: trimSelectedClipToRange,
                    onRippleDelete: rippleDeleteSelectedRange,
                    onClear: { selectionRange = nil }
                )
                .padding(.horizontal)
            }
            
            // Clip Properties + quick edit bar
            if let selectedClip = selectedClip {
                ClipPropertiesPanel(clipId: selectedClip.id)
                    .padding()

                EditToolbar(
                    onSplit: splitAtPlayhead,
                    onTrimStart: trimStartToPlayhead,
                    onTrimEnd: trimEndToPlayhead,
                    onDuplicate: duplicateSelected,
                    onDelete: { showDeleteConfirm = true },
                    onMoveLeft: moveSelectedLeft,
                    onMoveRight: moveSelectedRight
                )
                .padding(.horizontal)
                .confirmationDialog("Delete clip?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                    Button("Delete", role: .destructive) { deleteSelected() }
                    Button("Cancel", role: .cancel) {}
                }
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
        // Quick edit actions toolbar visibility handled inside the body where a clip is selected
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

// MARK: - Range Edit Toolbar
struct RangeEditToolbar: View {
    let onTrimToRange: () -> Void
    let onRippleDelete: () -> Void
    let onClear: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Button(action: onTrimToRange) { Label("Trim to Range", systemImage: "scissors") }
            Button(role: .destructive, action: onRippleDelete) { Label("Ripple Delete", systemImage: "delete.left") }
            Button(action: onClear) { Label("Clear", systemImage: "xmark") }
        }
        .buttonStyle(.bordered)
        .padding(8)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - IG-like Edit Toolbar
struct EditToolbar: View {
    let onSplit: () -> Void
    let onTrimStart: () -> Void
    let onTrimEnd: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    let onMoveLeft: () -> Void
    let onMoveRight: () -> Void
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                Button(action: onSplit) { Label("Split", systemImage: "scissors") }
                Button(action: onTrimStart) { Label("Trim Start", systemImage: "arrow.uturn.backward") }
                Button(action: onTrimEnd) { Label("Trim End", systemImage: "arrow.uturn.forward") }
                Button(action: onDuplicate) { Label("Duplicate", systemImage: "plus.square.on.square") }
                Button(action: onMoveLeft) { Label("Move Left", systemImage: "arrow.left.to.line") }
                Button(action: onMoveRight) { Label("Move Right", systemImage: "arrow.right.to.line") }
                Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
            }
            .buttonStyle(.bordered)
            .padding(8)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - Editing actions
extension TimelineView {
    private func splitAtPlayhead() {
        guard var project = appState.currentProject,
              let clip = selectedClip,
              let idx = project.clips.firstIndex(where: { $0.id == clip.id }) else { return }
        let t = currentTime
        guard t > clip.startTime && t < clip.endTime else { return }
        var first = clip
        first.endTime = t
        var second = clip
        second.startTime = t
        second.id = UUID()
        project.clips.remove(at: idx)
        project.clips.insert(contentsOf: [first, second], at: idx)
        selectedClip = second
        appState.currentProject = project
    }
    
    private func duplicateSelected() {
        guard var project = appState.currentProject,
              let clip = selectedClip,
              let idx = project.clips.firstIndex(where: { $0.id == clip.id }) else { return }
        var copy = clip
        copy.id = UUID()
        project.clips.insert(copy, at: idx + 1)
        selectedClip = copy
        appState.currentProject = project
    }
    
    private func deleteSelected() {
        guard var project = appState.currentProject,
              let clip = selectedClip,
              let idx = project.clips.firstIndex(where: { $0.id == clip.id }) else { return }
        project.clips.remove(at: idx)
        selectedClip = nil
        appState.currentProject = project
    }
    
    private func moveSelectedLeft() {
        guard var project = appState.currentProject,
              let clip = selectedClip,
              let idx = project.clips.firstIndex(where: { $0.id == clip.id }),
              idx > 0 else { return }
        project.clips.swapAt(idx, idx - 1)
        appState.currentProject = project
    }
    
    private func moveSelectedRight() {
        guard var project = appState.currentProject,
              let clip = selectedClip,
              let idx = project.clips.firstIndex(where: { $0.id == clip.id }),
              idx < project.clips.count - 1 else { return }
        project.clips.swapAt(idx, idx + 1)
        appState.currentProject = project
    }
}

extension TimelineView {
    private func trimSelectedClipToRange() {
        guard var project = appState.currentProject,
              let range = selectionRange,
              let clip = selectedClip,
              let idx = project.clips.firstIndex(where: { $0.id == clip.id }) else { return }
        let start = snapTimeGlobal(range.start, project: project, currentTime: currentTime)
        let end = snapTimeGlobal(range.start + range.duration, project: project, currentTime: currentTime)
        if start > project.clips[idx].startTime { project.clips[idx].startTime = start }
        if end < project.clips[idx].endTime { project.clips[idx].endTime = end }
        selectionRange = nil
        appState.currentProject = project
    }
    
    private func rippleDeleteSelectedRange() {
        guard var project = appState.currentProject,
              let range = selectionRange else { return }
        
        // Remove content inside range from overlapping clips and close the gap
        var newClips: [EditableClip] = []
        for clip in project.clips {
            // If clip entirely before or after range, keep and shift if needed
            if clip.endTime <= range.start {
                newClips.append(clip)
                continue
            }
            if clip.startTime >= range.end {
                var shifted = clip
                shifted.startTime = CMTimeSubtract(shifted.startTime, range.duration)
                shifted.endTime = CMTimeSubtract(shifted.endTime, range.duration)
                newClips.append(shifted)
                continue
            }
            // Overlap: may produce 0, 1 or 2 clips
            if clip.startTime < range.start {
                var left = clip
                left.endTime = range.start
                newClips.append(left)
            }
            if clip.endTime > range.end {
                var right = clip
                right.startTime = range.end
                // shift right segment left by deleted duration
                right.startTime = CMTimeSubtract(right.startTime, range.duration)
                right.endTime = CMTimeSubtract(right.endTime, range.duration)
                right.id = UUID()
                newClips.append(right)
            }
        }
        project.clips = newClips
        selectionRange = nil
        appState.currentProject = project
    }
}

#if os(iOS)
// MARK: - Video Player View (iOS)
struct VideoPlayerView: View {
    @Binding var currentTime: CMTime
    @Binding var isPlaying: Bool
    let project: VideoProject?

    @State private var player = AVPlayer()
    @State private var timeObserver: Any?

    var body: some View {
        Group {
            if let project, project.clips.isEmpty == false {
                VideoPlayer(player: player)
                    .background(Color.black)
                    .onAppear { rebuildComposition(with: project) }
                    .onChange(of: isPlaying) { _, playing in playing ? player.play() : player.pause() }
                    .onChange(of: currentTime) { _, t in player.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero) }
                    .onChange(of: project.clips) { _, _ in rebuildComposition(with: project) }
            } else {
                ZStack {
                    Color.black
                    VStack(spacing: 8) {
                        Image(systemName: "video")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("Import a video to preview")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .onDisappear {
            if let obs = timeObserver { player.removeTimeObserver(obs) }
            timeObserver = nil
            player.pause()
        }
    }

    private func rebuildComposition(with project: VideoProject) {
        Task {
            let composition = AVMutableComposition()
            let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
            let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            var cursor: CMTime = .zero

            for clip in project.clips {
                let asset = AVURLAsset(url: clip.videoURL)
                if let v = try? await asset.loadTracks(withMediaType: .video).first {
                    try? videoTrack?.insertTimeRange(CMTimeRange(start: clip.startTime, duration: clip.duration), of: v, at: cursor)
                }
                if let a = try? await asset.loadTracks(withMediaType: .audio).first {
                    try? audioTrack?.insertTimeRange(CMTimeRange(start: clip.startTime, duration: clip.duration), of: a, at: cursor)
                }
                cursor = CMTimeAdd(cursor, clip.duration)
            }

            await MainActor.run {
                let item = AVPlayerItem(asset: composition)
                player.replaceCurrentItem(with: item)

                if let obs = timeObserver { player.removeTimeObserver(obs) }
                timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { t in
                    currentTime = t
                }

                if isPlaying { player.play() }
            }
        }
    }
}
#endif

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
        playerLayer.videoGravity = .resizeAspect
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
        if isPlaying { context.coordinator.player?.play() } else { context.coordinator.player?.pause() }
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
            Task { @MainActor in
                let composition = AVMutableComposition()
                let videoTrack = composition.addMutableTrack(
                    withMediaType: .video,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                )
                let audioTrack = composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                )
                var current: CMTime = .zero
                for clip in project.clips {
                    let asset = AVURLAsset(url: clip.videoURL)
                    if let v = try? await asset.loadTracks(withMediaType: .video).first {
                        try? videoTrack?.insertTimeRange(
                            CMTimeRange(start: clip.startTime, duration: clip.duration),
                            of: v,
                            at: current
                        )
                    }
                    if let a = try? await asset.loadTracks(withMediaType: .audio).first {
                        try? audioTrack?.insertTimeRange(
                            CMTimeRange(start: clip.startTime, duration: clip.duration),
                            of: a,
                            at: current
                        )
                    }
                    current = CMTimeAdd(current, clip.duration)
                }
                let item = AVPlayerItem(asset: composition)
                player?.replaceCurrentItem(with: item)
            }
        }
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
            
            // Frame-by-frame Controls (Final Cut style)
            HStack(spacing: 16) {
                Button { currentTime = .zero } label: {
                    Image(systemName: "backward.end")
                }
                Button { step(by: -1) } label: {
                    Image(systemName: "backward.frame")
                }
                Button { isPlaying.toggle() } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                }
                Button { step(by: +1) } label: {
                    Image(systemName: "forward.frame")
                }
                Button { currentTime = totalDuration } label: {
                    Image(systemName: "forward.end")
                }
                Divider().frame(height: 16)
                Text(timeString(from: currentTime))
                    .monospacedDigit()
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("30 fps")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.bordered)
            
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

    // MARK: - Frame stepping helpers
    private func frameDuration() -> CMTime {
        // Default to 30 fps; adjust when metadata detection is added
        return CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600)
    }

    private func step(by frames: Int) {
        // Pause before nudging a single frame, like Final Cut
        isPlaying = false
        let delta = CMTimeMultiply(frameDuration(), multiplier: Int32(frames))
        var target = CMTimeAdd(currentTime, delta)
        if CMTimeCompare(target, .zero) < 0 { target = .zero }
        if CMTimeCompare(target, totalDuration) > 0 { target = totalDuration }
        currentTime = target
    }
}

// MARK: - Timeline Track View
struct TimelineTrackView: View {
    @EnvironmentObject var appState: AppState
    let project: VideoProject?
    let totalDuration: CMTime
    @Binding var currentTime: CMTime
    @Binding var selectedClip: EditableClip?
    @Binding var selectionRange: CMTimeRange?
    
    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width - 32
            ZStack(alignment: .topLeading) {
                timelineScrollView(width: width)
                    .background(Color.secondary.opacity(0.1))
                
                selectionOverlay(width: width, geo: geo)
            }
            .contentShape(Rectangle())
            .highPriorityGesture(timelineDragGesture(width: width))
        }
    }
    
    @ViewBuilder
    private func timelineScrollView(width: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                                        ForEach(project?.clips ?? [], id: \.id) { clip in
                            TimelineClipView(
                                clip: clip,
                                isSelected: selectedClip?.id == clip.id
                            ) {
                                selectedClip = clip
                            }
                            .frame(width: 60)
                            .draggable(ClipTransferable(clipId: clip.id))
                        }
            }
            .padding(.horizontal)
            .dropDestination(for: ClipTransferable.self) { items, location in
                handleDrop(items: items, location: location)
            }
        }
    }
    
    private func handleDrop(items: [ClipTransferable], location: CGPoint) -> Bool {
        guard var proj = appState.currentProject else { return false }
        guard let draggingItem = items.first, let from = proj.clips.firstIndex(where: { $0.id == draggingItem.clipId }) else { return false }
        let widthPerClip: CGFloat = 60
        let x = location.x - 16
        var to = Int(x / widthPerClip)
        to = max(0, min(to, max(0, proj.clips.count - 1)))
        if from != to {
            let moving = proj.clips.remove(at: from)
            proj.clips.insert(moving, at: to)
            appState.currentProject = proj
        }
        return true
    }
    
    @ViewBuilder
    private func selectionOverlay(width: CGFloat, geo: GeometryProxy) -> some View {
        if let range = selectionRange, totalDuration.seconds > 0 {
            let startSeconds = range.start.seconds
            let endSeconds = (range.start + range.duration).seconds
            let startX = CGFloat(startSeconds / totalDuration.seconds) * width + 16
            let endX = CGFloat(endSeconds / totalDuration.seconds) * width + 16
            Rectangle()
                .fill(Color.accentColor.opacity(0.15))
                .frame(width: max(0, endX - startX), height: geo.size.height)
                .position(x: startX + max(0, endX - startX)/2, y: geo.size.height/2)
                .allowsHitTesting(false)
        }
    }
    
    private func timelineDragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                handleDragChange(value: value, width: width)
            }
            .onEnded { _ in
                handleDragEnd()
            }
    }
    
    private func handleDragChange(value: DragGesture.Value, width: CGFloat) {
        guard totalDuration.seconds > 0 else { return }
        let localX = max(0, min(value.location.x - 16, width))
        let seconds = Double(localX / width) * totalDuration.seconds
        let t = CMTime(seconds: seconds, preferredTimescale: 600)
        if selectionRange == nil {
            let snapped = snapTimeGlobal(t, project: project, currentTime: currentTime)
            selectionRange = CMTimeRange(start: snapped, duration: .zero)
        } else {
            let snapped = snapTimeGlobal(t, project: project, currentTime: currentTime)
            let start = selectionRange!.start
            if snapped < start {
                selectionRange = CMTimeRange(start: snapped, end: start)
            } else {
                selectionRange = CMTimeRange(start: start, end: snapped)
            }
        }
    }
    
    private func handleDragEnd() {
        if let range = selectionRange, range.duration.seconds < 0.05 { 
            selectionRange = nil 
        }
    }
}

// Snapping helpers
extension TimelineView {
    private func trimStartToPlayhead() {
        guard var project = appState.currentProject,
              let clip = selectedClip,
              let idx = project.clips.firstIndex(where: { $0.id == clip.id }) else { return }
        let t = snapTimeGlobal(currentTime, project: project, currentTime: currentTime)
        if t < project.clips[idx].endTime { project.clips[idx].startTime = t }
        appState.currentProject = project
    }
    
    private func trimEndToPlayhead() {
        guard var project = appState.currentProject,
              let clip = selectedClip,
              let idx = project.clips.firstIndex(where: { $0.id == clip.id }) else { return }
        let t = snapTimeGlobal(currentTime, project: project, currentTime: currentTime)
        if t > project.clips[idx].startTime { project.clips[idx].endTime = t }
        appState.currentProject = project
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

// MARK: - Clip Properties Panel (editable)
struct ClipPropertiesPanel: View {
    @EnvironmentObject var appState: AppState
    let clipId: UUID
    
    @State private var volume: Float = 1.0
    @State private var speed: Float = 1.0
    @State private var durationSeconds: Double = 0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Clip Properties")
                .font(.headline)
            
            HStack {
                Text("Duration:")
                Spacer()
                Text(String(format: "%.1fs", durationSeconds))
            }
            
            HStack {
                Text("Volume:")
                Spacer()
                Slider(value: Binding(get: { Double(volume) }, set: { volume = Float($0); applyChanges() }), in: 0...1)
                    .frame(width: 160)
            }
            
            HStack {
                Text("Speed:")
                Spacer()
                Slider(value: Binding(get: { Double(speed) }, set: { speed = Float($0); applyChanges() }), in: 0.5...2.0)
                    .frame(width: 160)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
        .onAppear(perform: loadFromState)
        .onChange(of: appState.currentProject?.clips) { _, _ in loadFromState() }
    }
    
    private func loadFromState() {
        guard let idx = appState.currentProject?.clips.firstIndex(where: { $0.id == clipId }),
              let clip = appState.currentProject?.clips[idx] else { return }
        volume = clip.volume
        speed = clip.speed
        durationSeconds = clip.duration.seconds
    }
    
    private func applyChanges() {
        guard var project = appState.currentProject,
              let idx = project.clips.firstIndex(where: { $0.id == clipId }) else { return }
        project.clips[idx].volume = volume
        project.clips[idx].speed = speed
        appState.currentProject = project
        NotificationCenter.default.post(name: .storycutUpdateClip, object: nil, userInfo: [
            "clipId": clipId,
            "start": project.clips[idx].startTime.seconds,
            "end": project.clips[idx].endTime.seconds,
            "volume": volume,
            "speed": speed
        ])
    }
}

#Preview {
    TimelineView()
        .environmentObject(AppState())
} 