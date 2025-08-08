import SwiftUI
import AVFoundation
#if os(macOS)
import AppKit
#endif

struct ClipEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let clip: EditableClip
    @State private var startTime: Double
    @State private var endTime: Double
    @State private var volume: Float
    @State private var speed: Float
    @State private var selectedFilter: VideoFilter.FilterType?
    @State private var filterIntensity: Float = 0.5
    
    init(clip: EditableClip) {
        self.clip = clip
        self._startTime = State(initialValue: clip.startTime.seconds)
        self._endTime = State(initialValue: clip.endTime.seconds)
        self._volume = State(initialValue: clip.volume)
        self._speed = State(initialValue: clip.speed)
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Video Preview
                    VideoPreviewView(videoURL: clip.videoURL)
                        .frame(height: 200)
                        .cornerRadius(12)
                    
                    // Trim Controls
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Trim")
                            .font(.headline)
                        
                        VStack(spacing: 12) {
                            HStack {
                                Text("Start Time:")
                                Spacer()
                                Text(String(format: "%.1fs", startTime))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Slider(value: $startTime, in: 0...endTime)
                            
                            HStack {
                                Text("End Time:")
                                Spacer()
                                Text(String(format: "%.1fs", endTime))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Slider(value: $endTime, in: startTime...60)
                        }
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(12)
                    
                    // Audio Controls
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Audio")
                            .font(.headline)
                        
                        VStack(spacing: 12) {
                            HStack {
                                Text("Volume:")
                                Spacer()
                                Text(String(format: "%.0f%%", volume * 100))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Slider(value: $volume, in: 0...1)
                        }
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(12)
                    
                    // Speed Controls
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Speed")
                            .font(.headline)
                        
                        VStack(spacing: 12) {
                            HStack {
                                Text("Playback Speed:")
                                Spacer()
                                Text(String(format: "%.1fx", speed))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Slider(value: $speed, in: 0.5...2.0)
                            
                            HStack(spacing: 20) {
                                Button("0.5x") { speed = 0.5 }
                                    .buttonStyle(.bordered)
                                
                                Button("1.0x") { speed = 1.0 }
                                    .buttonStyle(.bordered)
                                
                                Button("1.5x") { speed = 1.5 }
                                    .buttonStyle(.bordered)
                                
                                Button("2.0x") { speed = 2.0 }
                                    .buttonStyle(.bordered)
                            }
                        }
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(12)
                    
                    // Filters
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Filters")
                            .font(.headline)
                        
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 12) {
                            ForEach(VideoFilter.FilterType.allCases, id: \.self) { filter in
                                FilterCard(
                                    filter: filter,
                                    isSelected: selectedFilter == filter
                                ) {
                                    selectedFilter = filter
                                }
                            }
                        }
                        
                        if let selectedFilter = selectedFilter {
                            VStack(spacing: 12) {
                                HStack {
                                    Text("Intensity:")
                                    Spacer()
                                    Text(String(format: "%.0f%%", filterIntensity * 100))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Slider(value: $filterIntensity, in: 0...1)
                            }
                            .padding()
                            .background(Color.accentColor.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(12)
                }
                .padding()
            }
            .navigationTitle("Edit Clip")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveChanges()
                        dismiss()
                    }
                }
                #else
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                        dismiss()
                    }
                }
                #endif
            }
        }
    }
    
    private func saveChanges() {
        // Persist updates back to the clip by mutating via Notification
        NotificationCenter.default.post(name: .storycutUpdateClip,
                                        object: nil,
                                        userInfo: [
                                            "clipId": clip.id,
                                            "start": startTime,
                                            "end": endTime,
                                            "volume": volume,
                                            "speed": speed
                                        ])
    }
}

#if os(macOS)
// MARK: - Video Preview View (macOS)
struct VideoPreviewView: NSViewRepresentable {
    let videoURL: URL
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        let playerLayer = AVPlayerLayer()
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.frame = view.bounds
        view.layer?.addSublayer(playerLayer)
        let player = AVPlayer(url: videoURL)
        playerLayer.player = player
        player.play()
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if let playerLayer = nsView.layer?.sublayers?.first as? AVPlayerLayer {
            playerLayer.frame = nsView.bounds
        }
    }
}
#else
// MARK: - Video Preview View (iOS)
import AVKit
struct VideoPreviewView: View {
    let videoURL: URL
    var body: some View {
        VideoPlayer(player: AVPlayer(url: videoURL))
            .onAppear { }
    }
}
#endif

// MARK: - Filter Card
struct FilterCard: View {
    let filter: VideoFilter.FilterType
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                Image(systemName: iconName(for: filter))
                    .font(.title2)
                    .foregroundColor(isSelected ? .white : .accentColor)
                
                Text(filter.rawValue)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(isSelected ? .white : .primary)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.1))
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func iconName(for filter: VideoFilter.FilterType) -> String {
        switch filter {
        case .brightness:
            return "sun.max"
        case .contrast:
            return "circle.lefthalf.filled"
        case .saturation:
            return "drop"
        case .blur:
            return "camera.filters"
        case .sharpen:
            return "camera.aperture"
        }
    }
}

#Preview {
    ClipEditorView(clip: EditableClip(videoURL: URL(fileURLWithPath: "/mock/video.mov")))
} 