import SwiftUI
import AVFoundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct ExportSummaryView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    #if os(macOS)
    @State private var thumbnail: NSImage?
    #else
    @State private var thumbnail: UIImage?
    #endif
    @State private var isExporting = false
    @State private var exportProgress: Double = 0.0
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Video Preview
                    VStack(spacing: 12) {
                        Text("Preview")
                            .font(.headline)
                        
                        #if os(macOS)
                        if let thumbnail = thumbnail {
                            Image(nsImage: thumbnail)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 200)
                                .cornerRadius(12)
                        } else {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.secondary.opacity(0.1))
                                .frame(height: 200)
                                .overlay(
                                    Image(systemName: "video")
                                        .font(.largeTitle)
                                        .foregroundColor(.secondary)
                                )
                        }
                        #else
                        if let thumbnail = thumbnail {
                            Image(uiImage: thumbnail)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 200)
                                .cornerRadius(12)
                        } else {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.secondary.opacity(0.1))
                                .frame(height: 200)
                                .overlay(
                                    Image(systemName: "video")
                                        .font(.largeTitle)
                                        .foregroundColor(.secondary)
                                )
                        }
                        #endif
                    }
                    .padding()
                    
                    // Project Info
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Project Details")
                            .font(.headline)
                        
                        VStack(spacing: 12) {
                            InfoRow(title: "Project Name", value: appState.currentProject?.name ?? "Untitled")
                            InfoRow(title: "Duration", value: formatDuration(appState.currentProject?.totalDuration))
                            InfoRow(title: "Clips", value: "\(appState.currentProject?.clips.count ?? 0)")
                            InfoRow(title: "Audio Tracks", value: "\(appState.currentProject?.audioTracks.count ?? 0)")
                            InfoRow(title: "Subtitles", value: "\(appState.currentProject?.subtitles.count ?? 0)")
                        }
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    
                    // Export Settings
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Export Settings")
                            .font(.headline)
                        
                        VStack(spacing: 12) {
                            InfoRow(title: "Platform", value: appState.exportPreset.rawValue)
                            InfoRow(title: "Quality", value: appState.exportQuality.rawValue)
                            InfoRow(title: "Resolution", value: "\(Int(appState.exportPreset.resolution.width))x\(Int(appState.exportPreset.resolution.height))")
                            InfoRow(title: "Aspect Ratio", value: "\(Int(appState.exportPreset.aspectRatio.width)):\(Int(appState.exportPreset.aspectRatio.height))")
                            InfoRow(title: "Frame Rate", value: "\(appState.exportPreset.frameRate) fps")
                        }
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    
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
                    .disabled(isExporting)
                    .padding()
                    
                    if isExporting {
                        ProgressView(value: exportProgress)
                            .progressViewStyle(LinearProgressViewStyle())
                            .padding(.horizontal)
                    }
                }
            }
            .navigationTitle("Export Summary")
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
                #else
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                #endif
            }
        }
        .onAppear {
            generateThumbnail()
        }
    }
    
    private func generateThumbnail() {
        guard let project = appState.currentProject,
              let firstClip = project.clips.first else { return }
        
        Task {
            let asset = AVURLAsset(url: firstClip.videoURL)
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
            
            do {
                let result = try await imageGenerator.image(at: .zero)
                let cgImage = result.image
                await MainActor.run {
                    #if os(macOS)
                    thumbnail = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                    #else
                    thumbnail = UIImage(cgImage: cgImage)
                    #endif
                }
            } catch {
                print("Failed to generate thumbnail: \(error)")
            }
        }
    }
    
    private func formatDuration(_ duration: CMTime?) -> String {
        guard let duration = duration else { return "0:00" }
        let seconds = Int(duration.seconds)
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
    
    private func startExport() {
        isExporting = true
        exportProgress = 0.0
        
        // Simulate export process
        Task {
            for i in 1...10 {
                try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                await MainActor.run {
                    exportProgress = Double(i) / 10.0
                }
            }
            
            await MainActor.run {
                isExporting = false
                dismiss()
            }
        }
    }
}

// MARK: - Info Row
struct InfoRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .fontWeight(.medium)
        }
    }
}

#Preview {
    ExportSummaryView()
        .environmentObject(AppState())
} 