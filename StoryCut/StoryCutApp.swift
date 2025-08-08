import SwiftUI
import AVFoundation
import AVFAudio
import Speech
import PhotosUI

@main
struct StoryCutApp: App {
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .onAppear {
                    setupAudioSession()
                    requestPermissions()
                }
        }
    }
    
    private func setupAudioSession() {
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
        #else
        // macOS doesn't use AVAudioSession
        print("Audio session setup skipped on macOS")
        #endif
    }
    
    private func requestPermissions() {
        #if os(iOS)
        // Request microphone permission for audio recording (iOS 17+ API with fallback)
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission { granted in
                DispatchQueue.main.async {
                    appState.microphonePermission = granted
                }
            }
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                DispatchQueue.main.async {
                    appState.microphonePermission = granted
                }
            }
        }
        #else
        // On macOS, assume microphone permission is granted
        appState.microphonePermission = true
        #endif
        
        // Request speech recognition permission
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                appState.speechPermission = status
            }
        }
    }
} 