import SwiftUI
import PhotosUI
import AVFoundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct SocialMediaExportView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var exportService = VideoExportService()
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var selectedVideo: URL?
    @State private var selectedPlatform: SocialPlatform = .tikTok
    @State private var showingSuccess = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var generatedCaption = ""
    @State private var generatedHashtags: [String] = []
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "square.and.arrow.up.circle.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.green)
                        
                        Text("Quick Export to Social Media")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Select a video and export directly to your favorite platform")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top)
                    
                    // Video Selection
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Select Video")
                            .font(.headline)
                        
                        PhotosPicker(selection: $selectedItems, matching: .videos) {
                            HStack {
                                Image(systemName: "video.fill")
                                    .foregroundColor(.accentColor)
                                Text("Choose Video from Photos")
                                    .fontWeight(.medium)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(12)
                        }
                        
                        if let selectedVideo = selectedVideo {
                            VideoPreviewCard(videoURL: selectedVideo)
                        }
                    }
                    .padding()
                    
                    // Platform Selection
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Choose Platform")
                            .font(.headline)
                        
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 12) {
                            ForEach(SocialPlatform.allCases, id: \.self) { platform in
                                PlatformCard(
                                    platform: platform,
                                    isSelected: selectedPlatform == platform
                                ) {
                                    selectedPlatform = platform
                                    generateContent(for: platform)
                                }
                            }
                        }
                    }
                    .padding()
                    
                    // Export Settings
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Export Settings")
                            .font(.headline)
                        
                        VStack(spacing: 12) {
                            HStack {
                                Text("Quality:")
                                Spacer()
                                Text("High")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            HStack {
                                Text("Aspect Ratio:")
                                Spacer()
                                Text(selectedPlatform.aspectRatio)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            HStack {
                                Text("Duration:")
                                Spacer()
                                Text("Auto-trim to \(selectedPlatform.maxDuration)s")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(12)
                    }
                    .padding()
                    
                    // Generated Content
                    if !generatedCaption.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Generated Content")
                                .font(.headline)
                            
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Caption:")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                
                                Text(generatedCaption)
                                    .font(.body)
                                    .padding()
                                    .background(Color.secondary.opacity(0.1))
                                    .cornerRadius(8)
                                
                                if !generatedHashtags.isEmpty {
                                    Text("Hashtags:")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    
                                    LazyVGrid(columns: [
                                        GridItem(.adaptive(minimum: 80))
                                    ], spacing: 8) {
                                        ForEach(generatedHashtags, id: \.self) { hashtag in
                                            Text(hashtag)
                                                .font(.caption)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(Color.accentColor.opacity(0.1))
                                                .cornerRadius(6)
                                        }
                                    }
                                }
                            }
                            .padding()
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(12)
                        }
                        .padding()
                    }
                    
                    // Export Button
                    Button(action: startExport) {
                        HStack {
                            if exportService.isExporting {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "square.and.arrow.up")
                            }
                            
                            Text(exportService.isExporting ? "Exporting..." : "Export to \(selectedPlatform.displayName)")
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(exportService.isExporting ? Color.gray : Color.green)
                        .cornerRadius(12)
                    }
                    .disabled(exportService.isExporting || selectedVideo == nil)
                    .padding()
                    
                    if exportService.isExporting {
                        ProgressView(value: exportService.exportProgress)
                            .progressViewStyle(LinearProgressViewStyle())
                            .padding(.horizontal)
                    }
                    
                    Spacer(minLength: 100)
                }
            }
            .navigationTitle("Social Export")
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
        .onChange(of: selectedItems) { oldValue, newValue in
            Task {
                await processSelectedVideo(newValue)
            }
        }
        .alert("Export Complete", isPresented: $showingSuccess) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text("Your video has been exported successfully to \(selectedPlatform.displayName)!")
        }
        .alert("Export Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func processSelectedVideo(_ items: [PhotosPickerItem]) async {
        guard let item = items.first else { return }
        do {
            if let url = try await item.loadTransferable(type: URL.self) {
                await MainActor.run {
                    selectedVideo = url
                    generateContent(for: selectedPlatform)
                }
                return
            }
            if let data = try await item.loadTransferable(type: Data.self) {
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                let dest = docs.appendingPathComponent("social_export_\(Date().timeIntervalSince1970).mov")
                try data.write(to: dest)
                await MainActor.run {
                    selectedVideo = dest
                    generateContent(for: selectedPlatform)
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to import video: \(error.localizedDescription)"
                showingError = true
            }
        }
    }
    
    private func generateContent(for platform: SocialPlatform) {
        generatedCaption = exportService.generateCaption(for: platform)
        generatedHashtags = exportService.generateHashtags(for: platform)
    }
    
    private func startExport() {
        guard let videoURL = selectedVideo else { return }
        
        // Build a minimal project with a single clip for export
        var project = VideoProject(name: "Social Export")
        project.clips = [EditableClip(videoURL: videoURL)]
        // Map social platform to ExportPreset
        let preset: ExportPreset
        switch selectedPlatform {
        case .tikTok: preset = .tikTok
        case .instagram: preset = .reels
        case .youtube: preset = .shorts
        default: preset = .custom
        }
        exportService.exportVideo(project: project, preset: preset, quality: .high) { result in
            switch result {
            case .success(let exportedURL):
                // Share to social media
                exportService.shareToSocialMedia(videoURL: exportedURL, platform: selectedPlatform) { success in
                    DispatchQueue.main.async {
                        if success {
                            showingSuccess = true
                        } else {
                            errorMessage = "Failed to share to \(selectedPlatform.displayName)"
                            showingError = true
                        }
                    }
                }
                
            case .failure(let error):
                DispatchQueue.main.async {
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
        }
    }
}

// SocialPlatform enum moved to Models/SocialPlatform.swift to avoid redeclaration

// MARK: - Platform Card
struct PlatformCard: View {
    let platform: SocialPlatform
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                Image(systemName: platform.iconName)
                    .font(.title2)
                    .foregroundColor(isSelected ? .white : platform.color)
                
                Text(platform.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(isSelected ? .white : .primary)
                
                Text(platform.aspectRatio)
                    .font(.caption2)
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(isSelected ? platform.color : Color.secondary.opacity(0.1))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Video Preview Card
struct VideoPreviewCard: View {
    let videoURL: URL
    #if os(macOS)
    @State private var thumbnail: NSImage?
    #else
    @State private var thumbnail: UIImage?
    #endif
    
    var body: some View {
        VStack(spacing: 8) {
            #if os(macOS)
            if let thumbnail = thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 120)
                    .cornerRadius(8)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(height: 120)
                    .overlay(
                        Image(systemName: "video")
                            .font(.title)
                            .foregroundColor(.secondary)
                    )
            }
            #else
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 120)
                    .cornerRadius(8)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(height: 120)
                    .overlay(
                        Image(systemName: "video")
                            .font(.title)
                            .foregroundColor(.secondary)
                    )
            }
            #endif
            
            Text(videoURL.lastPathComponent)
                .font(.caption)
                .lineLimit(1)
        }
        .onAppear {
            generateThumbnail()
        }
    }
    
    private func generateThumbnail() {
        Task {
            let asset = AVURLAsset(url: videoURL)
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
}

#Preview {
    SocialMediaExportView()
} 