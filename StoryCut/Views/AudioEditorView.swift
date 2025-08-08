import SwiftUI
import AVFoundation
#if os(macOS)
import AppKit
#endif

struct AudioEditorView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedAudioTrack: AudioTrack?
    @State private var showingAudioPicker = false
    @State private var audioOffset: Double = 0.0
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Text("Audio Editor")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Add music and adjust L/J cuts")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            .padding(.top)
            
            // Audio Tracks
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(appState.currentProject?.audioTracks ?? [], id: \.id) { track in
                        AudioTrackView(
                            track: track,
                            isSelected: selectedAudioTrack?.id == track.id
                        ) {
                            selectedAudioTrack = track
                        }
                    }
                    
                    // Add Audio Button
                    Button(action: { showingAudioPicker = true }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Add Audio Track")
                        }
                        .foregroundColor(.accentColor)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(12)
                    }
                }
                .padding()
            }
            
            // L/J Cut Controls
            if let selectedTrack = selectedAudioTrack {
                LJCutControlsView(
                    track: selectedTrack,
                    audioOffset: $audioOffset
                )
                .padding()
            }
            
            Spacer()
        }
        .sheet(isPresented: $showingAudioPicker) {
            AudioPickerView { audioURL in
                addAudioTrack(url: audioURL)
            }
        }
    }
    
    private func addAudioTrack(url: URL) {
        let track = AudioTrack(
            audioURL: url,
            startTime: .zero,
            endTime: CMTime(seconds: 30, preferredTimescale: 600),
            volume: 1.0,
            isMuted: false
        )
        appState.currentProject?.audioTracks.append(track)
    }
}

// MARK: - Audio Track View
struct AudioTrackView: View {
    let track: AudioTrack
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                // Waveform
                AudioWaveformView(audioURL: track.audioURL)
                    .frame(height: 60)
                
                // Track Info
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(track.audioURL.lastPathComponent)
                            .font(.headline)
                            .lineLimit(1)
                        
                        Text("Duration: \(String(format: "%.1fs", track.duration.seconds))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // Volume Control
                    VStack {
                        Image(systemName: track.isMuted ? "speaker.slash" : "speaker.wave.2")
                            .foregroundColor(track.isMuted ? .red : .green)
                        
                        Slider(value: .constant(track.volume), in: 0...1)
                            .frame(width: 60)
                    }
                }
            }
            .padding()
                            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.1))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#if os(macOS)
// MARK: - Audio Waveform View (macOS)
struct AudioWaveformView: NSViewRepresentable {
    let audioURL: URL
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let waveformLayer = CAShapeLayer()
        waveformLayer.fillColor = NSColor.systemBlue.cgColor
        view.layer?.addSublayer(waveformLayer)
        context.coordinator.waveformLayer = waveformLayer
        context.coordinator.generateWaveform()
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.waveformLayer?.frame = nsView.bounds
    }
    
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    
    class Coordinator: NSObject {
        var parent: AudioWaveformView
        var waveformLayer: CAShapeLayer?
        
        init(_ parent: AudioWaveformView) { self.parent = parent }
        
        func generateWaveform() {
            let path = NSBezierPath()
            let width = waveformLayer?.bounds.width ?? 200
            let height = waveformLayer?.bounds.height ?? 60
            let barWidth: CGFloat = 2
            let spacing: CGFloat = 1
            for i in 0..<Int(width / (barWidth + spacing)) {
                let x = CGFloat(i) * (barWidth + spacing)
                let barHeight = CGFloat.random(in: 5...height - 10)
                let y = (height - barHeight) / 2
                path.move(to: CGPoint(x: x, y: y))
                path.line(to: CGPoint(x: x, y: y + barHeight))
            }
            waveformLayer?.path = path.cgPath
        }
    }
}
#else
// MARK: - Audio Waveform View (iOS placeholder)
struct AudioWaveformView: View {
    let audioURL: URL
    
    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .center, spacing: 1) {
                let numberOfBars = Int(max(1, geometry.size.width / 3))
                ForEach(0..<numberOfBars, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.accentColor)
                        .frame(width: 2, height: CGFloat.random(in: 5...max(10, geometry.size.height - 10)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .background(Color.accentColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
#endif

// MARK: - L/J Cut Controls View
struct LJCutControlsView: View {
    let track: AudioTrack
    @Binding var audioOffset: Double
    
    var body: some View {
        VStack(spacing: 16) {
            Text("L/J Cut Controls")
                .font(.headline)
            
            VStack(spacing: 12) {
                HStack {
                    Text("Audio Offset:")
                    Spacer()
                    Text(String(format: "%.1fs", audioOffset))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Slider(value: $audioOffset, in: -5...5)
                    .accentColor(.accentColor)
                
                HStack(spacing: 20) {
                    Button("L-Cut") {
                        audioOffset = -2.0
                    }
                    .buttonStyle(.bordered)
                    
                    Button("J-Cut") {
                        audioOffset = 2.0
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Reset") {
                        audioOffset = 0.0
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
                            .background(Color.secondary.opacity(0.1))
            .cornerRadius(12)
        }
    }
}

// MARK: - Audio Picker View
struct AudioPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let onAudioSelected: (URL) -> Void
    
    var body: some View {
        NavigationView {
            VStack {
                Text("Audio Picker")
                    .font(.title2)
                    .padding()
                
                // Mock audio files - in real app, you'd access music library
                List {
                    ForEach(mockAudioFiles, id: \.self) { fileName in
                        Button(fileName) {
                            // Create a mock URL for demo
                            let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                            let audioURL = documentsDirectory.appendingPathComponent(fileName)
                            onAudioSelected(audioURL)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Select Audio")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                #else
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                #endif
            }
        }
    }
    
    private let mockAudioFiles = [
        "background_music_1.mp3",
        "background_music_2.mp3",
        "sound_effect_1.wav",
        "voice_over_1.m4a"
    ]
}

#Preview {
    AudioEditorView()
        .environmentObject(AppState())
} 