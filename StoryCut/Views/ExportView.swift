import SwiftUI
import AVFoundation

struct ExportView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedPreset: ExportPreset = .tikTok
    @State private var selectedQuality: ExportQuality = .high
    @State private var includeWatermark = false
    @State private var watermarkText = "StoryCut"
    @State private var isExporting = false
    @State private var exportProgress: Double = 0.0
    @State private var showingExportSuccess = false
    @State private var exportedURL: URL?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Text("Export")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Choose your export settings")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .padding(.top)
                
                // Export Presets + Resolution + FPS
                VStack(alignment: .leading, spacing: 16) {
                    Text("Export Preset")
                        .font(.headline)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(ExportPreset.allCases, id: \.self) { preset in
                                ExportPresetCard(
                                    preset: preset,
                                    isSelected: selectedPreset == preset
                                ) {
                                    selectedPreset = preset
                                }
                                .frame(width: 140)
                            }
                        }
                    }

                    // Social platform chooser & resolution/fps summary
                    HStack(spacing: 12) {
                        Picker("Platform", selection: $selectedPreset) {
                            Text("TikTok").tag(ExportPreset.tikTok)
                            Text("Reels").tag(ExportPreset.reels)
                            Text("Shorts").tag(ExportPreset.shorts)
                            Text("Custom").tag(ExportPreset.custom)
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.top, 4)
                    
                    HStack {
                        Label("\(Int(selectedPreset.resolution.width))x\(Int(selectedPreset.resolution.height))", systemImage: "rectangle.compress.vertical")
                        Spacer()
                        Label("\(selectedPreset.frameRate) fps", systemImage: "speedometer")
                    }
                }
                .padding()
                
                // Quality Settings
                VStack(alignment: .leading, spacing: 16) {
                    Text("Quality")
                        .font(.headline)
                    
                    VStack(spacing: 12) {
                        ForEach(ExportQuality.allCases, id: \.self) { quality in
                            Button(action: { selectedQuality = quality }) {
                                HStack {
                                    Image(systemName: selectedQuality == quality ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(selectedQuality == quality ? .accentColor : .secondary)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(quality.rawValue)
                                            .font(.body)
                                            .foregroundColor(.primary)
                                        
                                        Text("\(quality.bitrate / 1_000_000) Mbps")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                }
                                .padding()
                                .background(selectedQuality == quality ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.1))
                                .cornerRadius(8)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
                .padding()
                
                // Advanced Settings
                VStack(alignment: .leading, spacing: 16) {
                    Text("Advanced Settings")
                        .font(.headline)
                    
                    VStack(spacing: 12) {
                        Toggle("Include Watermark", isOn: $includeWatermark)
                        
                        if includeWatermark {
                            TextField("Watermark Text", text: $watermarkText)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                        
                        HStack {
                            Text("Aspect Ratio:")
                            Spacer()
                            Text("\(Int(selectedPreset.aspectRatio.width)):\(Int(selectedPreset.aspectRatio.height))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Resolution:")
                            Spacer()
                            Text("\(Int(selectedPreset.resolution.width))x\(Int(selectedPreset.resolution.height))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Frame Rate:")
                            Spacer()
                            Text("\(selectedPreset.frameRate) fps")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(12)
                }
                .padding()
                
                // Export Button
                Button(action: startExport) {
                    HStack {
                        if isExporting {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                        }
                        
                        Text(isExporting ? "Exporting..." : "Export Video")
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isExporting ? Color.gray : Color.accentColor)
                    .cornerRadius(12)
                }
                .disabled(isExporting || appState.currentProject?.clips.isEmpty ?? true)
                .padding()
                
                if isExporting {
                    ProgressView(value: exportProgress)
                        .progressViewStyle(LinearProgressViewStyle())
                        .padding(.horizontal)
                }

                if let url = exportedURL {
                    VStack(spacing: 12) {
                        Text("Export Location:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(url.path)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        #if os(iOS)
                        ShareLink(item: url) {
                            Label("Share Exported Video", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 4)
                        #endif
                    }
                    .padding(.horizontal)
                }
                
                Spacer(minLength: 100)
            }
        }
        .alert("Export Complete", isPresented: $showingExportSuccess) {
            Button("OK") { }
        } message: {
            Text("Your video has been exported successfully!")
        }
    }
    
    private func startExport() {
        guard let project = appState.currentProject, project.clips.isEmpty == false else { return }
        isExporting = true
        exportProgress = 0.0
        let service = VideoExportService()
        // Simple polling to reflect progress (avoid Combine plumbing here)
        service.exportVideo(project: project, preset: appState.exportPreset, quality: appState.exportQuality) { result in
            DispatchQueue.main.async {
                self.isExporting = false
                switch result {
                case .success(let url):
                    self.exportedURL = url
                    self.showingExportSuccess = true
                case .failure(let error):
                    print("Export failed: \(error)")
                }
            }
        }
    }
}

// MARK: - Export Preset Card
struct ExportPresetCard: View {
    let preset: ExportPreset
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                Image(systemName: iconName(for: preset))
                    .font(.title2)
                    .foregroundColor(isSelected ? .white : .accentColor)
                
                Text(preset.rawValue)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(isSelected ? .white : .primary)
                
                Text("\(Int(preset.aspectRatio.width)):\(Int(preset.aspectRatio.height))")
                    .font(.caption2)
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.1))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func iconName(for preset: ExportPreset) -> String {
        switch preset {
        case .tikTok:
            return "music.note"
        case .reels:
            return "camera"
        case .shorts:
            return "play.rectangle"
        case .custom:
            return "slider.horizontal.3"
        }
    }
}

#Preview {
    ExportView()
        .environmentObject(AppState())
} 