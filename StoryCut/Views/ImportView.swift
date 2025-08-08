import SwiftUI
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct ImportView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var showingImagePicker = false
    // Removed per request: music picker and Files importer
    @State private var importedVideos: [URL] = []
    // Removed per request: imported audio
    @State private var showingError = false
    @State private var errorMessage = ""
    // Removed per request: quick social export entry
    @State private var showCameraUnavailable = false
    @State private var isDownloadingSample = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.accentColor)
                    
                    Text("Create Your Story")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Import videos, photos, and music to start editing")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 40)
                
                // Import Options
                VStack(spacing: 16) {
                    ImportOptionCard(
                        title: "Import Videos",
                        subtitle: "Select from your photo library",
                        icon: "video.fill",
                        color: .blue
                    ) {
                        showingImagePicker = true
                    }
                    
                    ImportOptionCard(
                        title: "Import from Social Link",
                        subtitle: "Paste TikTok/Reels/Shorts URL",
                        icon: "link",
                        color: .orange
                    ) {
                        presentSocialLinkPrompt()
                    }

                }
                
                // Imported Content Preview
                if !importedVideos.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Imported Content")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(importedVideos, id: \.self) { videoURL in
                                    VideoThumbnailView(videoURL: videoURL)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                
                // Create Project Button
                if !importedVideos.isEmpty {
                    Button(action: createProject) {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("Start Editing")
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                }
                
                Spacer(minLength: 100)
            }
        }
        .photosPicker(isPresented: $showingImagePicker, selection: $selectedItems, matching: .videos)
        // Removed: Files and Music importers per request
        .onChange(of: selectedItems) { oldValue, newValue in
            Task {
                await processSelectedVideos(newValue)
            }
        }
        .alert("Import Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        // Removed: quick social export sheet
        // Removed camera alert; replaced with link import
    }
    
    private func processSelectedVideos(_ items: [PhotosPickerItem]) async {
        for item in items {
            do {
                // Prefer URL (file-based) to avoid large memory copies
                if let tempURL = try? await item.loadTransferable(type: URL.self) {
                    let saved = try await copyIntoDocuments(originalURL: tempURL)
                    await MainActor.run { importedVideos.append(saved) }
                    continue
                }

                // Fallback to Data if URL not available
                if let data = try? await item.loadTransferable(type: Data.self) {
                    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                    let dest = docs.appendingPathComponent("video_\(Int(Date().timeIntervalSince1970)).mp4")
                    try data.write(to: dest)
                    await MainActor.run { importedVideos.append(dest) }
                    continue
                }

                throw NSError(domain: "StoryCut", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unsupported selection"]) 
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to import video: \(error.localizedDescription)"
                    showingError = true
                }
            }
        }
    }
    
    private func createProject() {
        let project = VideoProject(name: "New Project")
        appState.currentProject = project
        
        // Add imported videos as clips
        for videoURL in importedVideos {
            let clip = EditableClip(videoURL: videoURL)
            appState.currentProject?.clips.append(clip)
        }
        
        // Stay in a single unified screen; no tab switch needed
    }

    // Removed: sample downloader per request

    // MARK: - Utilities
    private func copyIntoDocuments(originalURL: URL) async throws -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        var destination = docs.appendingPathComponent(originalURL.lastPathComponent)
        
        // Ensure unique filename
        if FileManager.default.fileExists(atPath: destination.path) {
            let name = destination.deletingPathExtension().lastPathComponent
            let ext = destination.pathExtension
            destination = docs.appendingPathComponent("\(name)_\(Int(Date().timeIntervalSince1970)).\(ext.isEmpty ? "mov" : ext)")
        }

        // Handle security-scoped URLs (from file picker)
        if originalURL.startAccessingSecurityScopedResource() {
            defer { originalURL.stopAccessingSecurityScopedResource() }
            
            // Handle iCloud files
            if let rv = try? originalURL.resourceValues(forKeys: [.isUbiquitousItemKey]),
               rv.isUbiquitousItem == true {
                try FileManager.default.startDownloadingUbiquitousItem(at: originalURL)
                // Wait for download (with timeout)
                let start = Date()
                while Date().timeIntervalSince(start) < 10 {
                    if let rv2 = try? originalURL.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]),
                       rv2.ubiquitousItemDownloadingStatus == .current {
                        break
                    }
                    try await Task.sleep(nanoseconds: 200_000_000) // 0.2s
                }
            }
            
            // Copy the file
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: originalURL, to: destination)
            return destination
        }
        
        // Handle non-security-scoped URLs (e.g., from Photos)
        if let data = try? Data(contentsOf: originalURL) {
            try data.write(to: destination)
            return destination
        }
        
        throw NSError(domain: "StoryCut", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to access file"])
    }

    // MARK: - Social Link Import
    private func presentSocialLinkPrompt() {
        #if os(iOS)
        let alert = UIAlertController(title: "Import from Link", message: "Paste a TikTok/Reels/Shorts URL", preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "https://..." }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Import", style: .default) { _ in
            if let text = alert.textFields?.first?.text, let url = URL(string: text) { Task { await handleSocialLink(url) } }
        })
        
        // Use modern UIWindowScene API instead of deprecated UIApplication.shared.windows
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            window.rootViewController?.present(alert, animated: true)
        }
        #endif
    }

    private func handleSocialLink(_ url: URL) async {
        do {
            // Simple direct download. For real-world TikTok/IG links, a server-side resolver is needed.
            let (tempURL, _) = try await URLSession.shared.download(from: url)
            let saved = try await copyIntoDocuments(originalURL: tempURL)
            await MainActor.run { importedVideos.append(saved) }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to import link: \(error.localizedDescription)"
                showingError = true
            }
        }
    }
}

// MARK: - Quick Action Card
struct QuickActionCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let isProminent: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                    .frame(width: 40, height: 40)
                    .background(color.opacity(0.1))
                    .cornerRadius(10)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
                            .background(isProminent ? Color.green.opacity(0.1) : Color.secondary.opacity(0.1))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isProminent ? Color.green : Color.secondary.opacity(0.3), lineWidth: isProminent ? 2 : 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.horizontal)
    }
}

// MARK: - Import Option Card
struct ImportOptionCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                    .frame(width: 40, height: 40)
                    .background(color.opacity(0.1))
                    .cornerRadius(10)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
                            .background(Color.secondary.opacity(0.1))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.horizontal)
    }
}

// MARK: - Video Thumbnail View
struct VideoThumbnailView: View {
    let videoURL: URL
    #if os(macOS)
    @State private var thumbnail: NSImage?
    #else
    @State private var thumbnail: UIImage?
    #endif
    
    var body: some View {
        VStack {
            #if os(macOS)
            if let thumbnail = thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 120)
                    .cornerRadius(8)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: 80, height: 120)
                    .overlay(
                        Image(systemName: "video")
                            .foregroundColor(.secondary)
                    )
            }
            #else
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 120)
                    .cornerRadius(8)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: 80, height: 120)
                    .overlay(
                        Image(systemName: "video")
                            .foregroundColor(.secondary)
                    )
            }
            #endif
            
            Text(videoURL.lastPathComponent)
                .font(.caption2)
                .lineLimit(1)
                .frame(width: 80)
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
    ImportView()
        .environmentObject(AppState())
} 