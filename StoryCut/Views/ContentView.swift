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
    @State private var showingSocialExport = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Main content area
                TabView(selection: $appState.selectedTab) {
                    ImportView()
                        .tag(AppState.EditorTab.importMedia)
                    
                    TimelineView()
                        .tag(AppState.EditorTab.timeline)
                    
                    AudioEditorView()
                        .tag(AppState.EditorTab.audio)
                    
                    SubtitleEditorView()
                        .tag(AppState.EditorTab.subtitles)
                    
                    ExportView()
                        .tag(AppState.EditorTab.export)
                }
                #if os(iOS)
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                #else
                .tabViewStyle(DefaultTabViewStyle())
                #endif
                
                // Custom tab bar
                CustomTabBar()
                    .background(.ultraThinMaterial)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("StoryCut")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
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
                        // Quick Social Export Button
                        Button(action: { showingSocialExport = true }) {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(.green)
                        }
                        .disabled(appState.currentProject?.clips.isEmpty ?? true)
                        
                        // Full Export Button
                        if appState.currentProject != nil {
                            Button("Export") {
                                appState.showingExportSheet = true
                            }
                            .disabled(appState.currentProject?.clips.isEmpty ?? true)
                        }
                    }
                }
                #else
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 12) {
                        // Quick Social Export Button
                        Button(action: { showingSocialExport = true }) {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(.green)
                        }
                        .disabled(appState.currentProject?.clips.isEmpty ?? true)
                        
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
        .sheet(isPresented: $showingSocialExport) {
            SocialMediaExportView()
        }
    }
}

// MARK: - Custom Tab Bar
struct CustomTabBar: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppState.EditorTab.allCases, id: \.self) { tab in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        appState.selectedTab = tab
                    }
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: iconName(for: tab))
                            .font(.system(size: 20, weight: .medium))
                        
                        Text(tab.rawValue)
                            .font(.caption2)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(appState.selectedTab == tab ? .accentColor : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
            }
        }
                        .background(Color.secondary.opacity(0.1))
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color.secondary.opacity(0.3)),
            alignment: .top
        )
    }
    
    private func iconName(for tab: AppState.EditorTab) -> String {
        switch tab {
        case .importMedia:
            return "plus.circle"
        case .timeline:
            return "film"
        case .audio:
            return "waveform"
        case .subtitles:
            return "text.bubble"
        case .export:
            return "square.and.arrow.up"
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
} 