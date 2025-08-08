import SwiftUI
import Speech
import AVFoundation

struct SubtitleEditorView: View {
    @EnvironmentObject var appState: AppState
    @State private var subtitles: [SubtitleLine] = []
    @State private var isTranscribing = false
    @State private var selectedSubtitle: SubtitleLine?
    @State private var showingSubtitleEditor = false
    @State private var transcriptionProgress: Double = 0.0
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Text("Subtitles")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("AI transcription and manual editing")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            .padding(.top)
            
            // Transcription Controls
            VStack(spacing: 16) {
                Button(action: startTranscription) {
                    HStack {
                        Image(systemName: isTranscribing ? "stop.fill" : "mic.fill")
                        Text(isTranscribing ? "Stop Transcription" : "Start AI Transcription")
                    }
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(isTranscribing ? Color.red : Color.accentColor)
                    .cornerRadius(12)
                }
                .disabled(appState.currentProject?.clips.isEmpty ?? true)
                
                if isTranscribing {
                    ProgressView(value: transcriptionProgress)
                        .progressViewStyle(LinearProgressViewStyle())
                        .padding(.horizontal)
                }
            }
            .padding()
            
            // Subtitles List
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(subtitles) { subtitle in
                        SubtitleLineView(
                            subtitle: subtitle,
                            isSelected: selectedSubtitle?.id == subtitle.id
                        ) {
                            selectedSubtitle = subtitle
                            showingSubtitleEditor = true
                        }
                    }
                }
                .padding()
            }
            
            Spacer()
        }
        .sheet(isPresented: $showingSubtitleEditor) {
            if let subtitle = selectedSubtitle {
                SubtitleEditorSheet(subtitle: subtitle)
            }
        }
        .onAppear {
            loadSubtitles()
        }
    }
    
    private func loadSubtitles() {
        subtitles = appState.currentProject?.subtitles ?? []
    }
    
    private func startTranscription() {
        if isTranscribing {
            stopTranscription()
        } else {
            performTranscription()
        }
    }
    
    private func performTranscription() {
        guard let project = appState.currentProject,
              !project.clips.isEmpty else { return }
        
        isTranscribing = true
        transcriptionProgress = 0.0
        
        // Use the first clip for transcription demo
        let firstClip = project.clips[0]
        
        Task {
            do {
                let transcribedSubtitles = try await transcribeVideo(url: firstClip.videoURL)
                
                await MainActor.run {
                    subtitles = transcribedSubtitles
                    appState.currentProject?.subtitles = transcribedSubtitles
                    isTranscribing = false
                    transcriptionProgress = 1.0
                }
            } catch {
                await MainActor.run {
                    isTranscribing = false
                    print("Transcription failed: \(error)")
                }
            }
        }
    }
    
    private func stopTranscription() {
        isTranscribing = false
        transcriptionProgress = 0.0
    }
    
    private func transcribeVideo(url: URL) async throws -> [SubtitleLine] {
        // Mock transcription for demo
        // In a real implementation, you would use SFSpeechRecognizer
        try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
        
        return [
            SubtitleLine(
                text: "Hello, welcome to StoryCut!",
                startTime: CMTime(seconds: 0, preferredTimescale: 600),
                endTime: CMTime(seconds: 3, preferredTimescale: 600),
                style: SubtitleStyle()
            ),
            SubtitleLine(
                text: "This is an amazing video editing app.",
                startTime: CMTime(seconds: 3, preferredTimescale: 600),
                endTime: CMTime(seconds: 6, preferredTimescale: 600),
                style: SubtitleStyle()
            ),
            SubtitleLine(
                text: "Perfect for creating social media content.",
                startTime: CMTime(seconds: 6, preferredTimescale: 600),
                endTime: CMTime(seconds: 9, preferredTimescale: 600),
                style: SubtitleStyle()
            )
        ]
    }
}

// MARK: - Subtitle Line View
struct SubtitleLineView: View {
    let subtitle: SubtitleLine
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                Text(subtitle.text)
                    .font(.body)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                
                HStack {
                    Text(timeString(from: subtitle.startTime))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("-")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(timeString(from: subtitle.endTime))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    // Style preview
                    HStack(spacing: 4) {
                        Circle()
                            .fill(subtitle.style.fontColor)
                            .frame(width: 12, height: 12)
                        
                        Text("\(Int(subtitle.style.fontSize))pt")
                            .font(.caption2)
                            .foregroundColor(.secondary)
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
    
    private func timeString(from time: CMTime) -> String {
        let seconds = Int(time.seconds)
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

// MARK: - Subtitle Editor Sheet
struct SubtitleEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let subtitle: SubtitleLine
    @State private var editedText: String
    @State private var startTime: Double
    @State private var endTime: Double
    @State private var fontSize: Double
    @State private var fontColor: Color
    
    init(subtitle: SubtitleLine) {
        self.subtitle = subtitle
        self._editedText = State(initialValue: subtitle.text)
        self._startTime = State(initialValue: subtitle.startTime.seconds)
        self._endTime = State(initialValue: subtitle.endTime.seconds)
        self._fontSize = State(initialValue: subtitle.style.fontSize)
        self._fontColor = State(initialValue: subtitle.style.fontColor)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Text") {
                    TextField("Subtitle text", text: $editedText, axis: .vertical)
                        .lineLimit(3...6)
                }
                
                Section("Timing") {
                    HStack {
                        Text("Start Time:")
                        Spacer()
                        Text(String(format: "%.1fs", startTime))
                    }
                    
                    Slider(value: $startTime, in: 0...endTime)
                    
                    HStack {
                        Text("End Time:")
                        Spacer()
                        Text(String(format: "%.1fs", endTime))
                    }
                    
                    Slider(value: $endTime, in: startTime...60)
                }
                
                Section("Style") {
                    HStack {
                        Text("Font Size:")
                        Spacer()
                        Text("\(Int(fontSize))pt")
                    }
                    
                    Slider(value: $fontSize, in: 12...48)
                    
                    ColorPicker("Font Color", selection: $fontColor)
                }
            }
            .navigationTitle("Edit Subtitle")
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
        // Update the subtitle with new values
        // In a real implementation, you would update the project's subtitles array
        print("Saving subtitle changes...")
    }
}

#Preview {
    SubtitleEditorView()
        .environmentObject(AppState())
} 