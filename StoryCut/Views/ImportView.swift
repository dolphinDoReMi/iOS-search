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
    @State private var showingMusicPicker = false
    @State private var showingFileImporter = false
    @State private var importedVideos: [URL] = []
    @State private var importedAudio: [URL] = []
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingSocialExport = false
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
                
                // Quick Actions
                VStack(spacing: 16) {
                    // Quick Export to Social Media
                    QuickActionCard(
                        title: "Quick Export to Social Media",
                        subtitle: "Select a video and export directly",
                        icon: "square.and.arrow.up",
                        color: .green,
                        isProminent: true
                    ) {
                        showingSocialExport = true
                    }
                    
                    // Import Options
                    ImportOptionCard(
                        title: "Import Videos",
                        subtitle: "Select from your photo library",
                        icon: "video.fill",
                        color: .blue
                    ) {
                        showingImagePicker = true
                    }
                    
                    ImportOptionCard(
                        title: "Import from Files",
                        subtitle: "Browse videos in Files",
                        icon: "folder",
                        color: .teal
                    ) {
                        showingFileImporter = true
                    }
                    
                    ImportOptionCard(
                        title: "Add Music",
                        subtitle: "Import background music",
                        icon: "music.note",
                        color: .purple
                    ) {
                        showingMusicPicker = true
                    }
                    
                    ImportOptionCard(
                        title: "Record Video",
                        subtitle: "Capture new footage",
                        icon: "camera.fill",
                        color: .orange
                    ) {
                        #if os(iOS)
                        if UIImagePickerController.isSourceTypeAvailable(.camera) == false {
                            showCameraUnavailable = true
                        } else {
                            showCameraUnavailable = true // Simulator placeholder; guide to device
                        }
                        #endif
                    }

                    // Load a sample clip (for Simulator/dev machines without Photos content)
                    Button(action: loadSampleClip) {
                        HStack(spacing: 16) {
                            Image(systemName: "arrow.down.circle")
                                .font(.title2)
                                .foregroundColor(.blue)
                                .frame(width: 40, height: 40)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(10)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(isDownloadingSample ? "Downloading sample…" : "Load Sample Video")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Text("Adds a short demo clip to get started")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            if isDownloadingSample {
                                ProgressView()
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(12)
                    }
                    .buttonStyle(PlainButtonStyle())
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
        .task {
            // Prefetch authorization to ensure prompt is surfaced early in flow
            let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            if status == .limited {
                // Optional: present limited-library picker if needed in future
            }
        }
        .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [UTType.movie, UTType.video]) { result in
            switch result {
            case .success(let url):
                // Security-scoped access on iOS/macOS when needed
                let accessGranted = url.startAccessingSecurityScopedResource()
                defer { if accessGranted { url.stopAccessingSecurityScopedResource() } }
                importedVideos.append(url)
            case .failure(let error):
                errorMessage = "Failed to import from Files: \(error.localizedDescription)"
                showingError = true
            }
        }
        .fileImporter(isPresented: $showingMusicPicker, allowedContentTypes: [UTType.audio]) { result in
            switch result {
            case .success(let url):
                let accessGranted = url.startAccessingSecurityScopedResource()
                defer { if accessGranted { url.stopAccessingSecurityScopedResource() } }
                importedAudio.append(url)
            case .failure(let error):
                errorMessage = "Failed to import audio: \(error.localizedDescription)"
                showingError = true
            }
        }
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
        .sheet(isPresented: $showingSocialExport) {
            SocialMediaExportView()
        }
        .alert("Camera Unavailable", isPresented: $showCameraUnavailable) {
            Button("OK") { }
        } message: {
            Text("Camera recording is not available in the simulator. Please run on a real device.")
        }
    }
    
    private func processSelectedVideos(_ items: [PhotosPickerItem]) async {
        for item in items {
            do {
                if let url = try await item.loadTransferable(type: URL.self) {
                    await MainActor.run { importedVideos.append(url) }
                    continue
                }
                if let data = try await item.loadTransferable(type: Data.self) {
                    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                    let dest = docs.appendingPathComponent("video_\(Date().timeIntervalSince1970).mov")
                    try data.write(to: dest)
                    await MainActor.run { importedVideos.append(dest) }
                }
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
        
        // Switch to timeline view
        withAnimation {
            appState.selectedTab = .timeline
        }
    }

    private func loadSampleClip() {
        guard !isDownloadingSample else { return }
        isDownloadingSample = true
        Task {
            defer { isDownloadingSample = false }
            do {
                // Small public domain sample video
                let url = URL(string: "https://sample-videos.com/video321/mp4/240/big_buck_bunny_240p_1mb.mp4")!
                let (tempURL, _) = try await URLSession.shared.download(from: url)
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                let dest = docs.appendingPathComponent("sample_\(Int(Date().timeIntervalSince1970)).mp4")
                try FileManager.default.moveItem(at: tempURL, to: dest)
                await MainActor.run {
                    importedVideos.append(dest)
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to download sample: \(error.localizedDescription)"
                    showingError = true
                }
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