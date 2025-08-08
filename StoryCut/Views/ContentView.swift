import SwiftUI
import AVFoundation
#if os(macOS)
import AppKit
#endif
#if os(iOS)
import UIKit
#endif

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var editPrompt: String = ""
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Single unified screen
                UnifiedEditorView()
                    .background(.clear)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("StoryCut")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .navigationBarLeading) {
                    if appState.currentProject != nil {
                        Button("Save") { appState.persistCurrentProject() }
                        .foregroundColor(.accentColor)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        TextField("Describe your edit (e.g., 'trim to 15s, add fade')", text: $editPrompt)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 200)
                    }
                }
                #else
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 12) {
                        TextField("Describe your edit (e.g., 'trim to 15s, add fade')", text: $editPrompt)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 260)
                        
                        // Full Export Button
                        if appState.currentProject != nil {
                            Button("Export") {
                                appState.showingExportSheet = true
                            }
                            .disabled(appState.currentProject?.clips.isEmpty ?? true)
                        }
                    }
                }
                #endif
            }
        }
        .alert("Permissions Required", isPresented: $appState.showingPermissionAlert) {
            Button("Settings") {
                #if os(iOS)
                if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsUrl)
                }
                #else
                // On macOS, open System Preferences
                if let settingsUrl = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                    NSWorkspace.shared.open(settingsUrl)
                }
                #endif
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("StoryCut needs access to your photos, microphone, and speech recognition to function properly.")
        }
        .sheet(isPresented: $appState.showingExportSheet) {
            ExportSummaryView()
        }
    }
}

// Unified single-screen editor
struct UnifiedEditorView: View {
    @EnvironmentObject var appState: AppState
    @State private var lastExportURL: URL?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 1) Import section (always visible)
                ImportView()
                    .fixedSize(horizontal: false, vertical: true)

                Divider().opacity(0.2)

                // 2) Timeline + player
                TimelineView()
                    .frame(maxWidth: .infinity)

                // 3) Export presets and action
                ExportView()
                    .environmentObject(appState)

                if let url = lastExportURL {
                    VStack(spacing: 8) {
                        Text("Exported:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(url.lastPathComponent)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        #if os(iOS)
                        ShareLink(item: url) {
                            Label("Share / Save", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.bordered)
                        #endif
                    }
                }
            }
            .padding(.bottom, 24)
        }
    }
    
    private func quickExport() {
        guard let project = appState.currentProject, project.clips.isEmpty == false else { return }
        let service = VideoExportService()
        let preset = appState.exportPreset
        let quality = appState.exportQuality
        service.exportVideo(project: project, preset: preset, quality: quality) { result in
            switch result {
            case .success(let url):
                DispatchQueue.main.async { self.lastExportURL = url }
            case .failure(let error):
                print("Quick export failed: \(error)")
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
} 