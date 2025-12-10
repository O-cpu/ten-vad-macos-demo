//
//  VADViewModel.swift
//  VADDemo
//
//  ViewModel for managing VAD state and processing
//

import Foundation
import SwiftUI
import AVFoundation

/// Represents a single VAD result for visualization
struct VADDataPoint: Identifiable {
    let id = UUID()
    let timestamp: TimeInterval
    let probability: Float
    let isSpeech: Bool
}

@MainActor
final class VADViewModel: ObservableObject {
    @Published var isProcessing = false
    @Published var isProcessed = false
    @Published var statusMessage = "Select an audio file to analyze"
    @Published var dataPoints: [VADDataPoint] = []
    @Published var audioDuration: TimeInterval = 0
    @Published var speechPercentage: Double = 0
    @Published var libraryVersion: String = ""
    
    // VAD configuration
    @Published var threshold: Float = 0.5
    @Published var hopSize: Int = 256
    
    // Playback state
    @Published var isPlaying = false
    @Published var currentPlaybackTime: TimeInterval = 0
    @Published var playbackProgress: Double = 0  // 0.0 to 1.0
    
    private var vad: TenVAD?
    private var audioPlayer: AVAudioPlayer?
    private var playbackTimer: Timer?
    
    /// Currently loaded audio file URL
    @Published var currentAudioURL: URL?
    @Published var currentFileName: String = "No file selected"
    
    init() {
        libraryVersion = TenVAD.version
    }
    
    /// Set a new audio file URL
    func setAudioFile(url: URL) {
        currentAudioURL = url
        currentFileName = url.lastPathComponent
        // Reset state when new file is selected
        reset()
        statusMessage = "File selected: \(url.lastPathComponent)"
    }
    
    /// Process the currently selected audio file
    func processCurrentFile() async {
        guard let url = currentAudioURL else {
            statusMessage = "No audio file selected"
            return
        }
        await processAudioFile(at: url)
    }
    
    /// Process an audio file at the given URL
    func processAudioFile(at url: URL) async {
        isProcessing = true
        dataPoints = []
        statusMessage = "Loading audio file..."
        
        // Stop any existing playback
        stopPlayback()
        
        do {
            // Initialize VAD
            guard let vad = TenVAD(hopSize: hopSize, threshold: threshold) else {
                statusMessage = "Failed to initialize TEN VAD"
                isProcessing = false
                return
            }
            self.vad = vad
            
            // Load and convert audio
            statusMessage = "Converting audio to 16kHz..."
            let result = try await AudioFileProcessor.loadAudioFile(from: url)
            audioDuration = result.duration
            
            // Process through VAD
            statusMessage = "Running VAD analysis..."
            let vadResults = vad.processBuffer(samples: result.samples)
            
            // Convert to data points with timestamps
            let frameDuration = Double(hopSize) / 16000.0 // seconds per frame
            var points: [VADDataPoint] = []
            var speechFrames = 0
            
            for (index, vadResult) in vadResults.enumerated() {
                let timestamp = Double(index) * frameDuration
                points.append(VADDataPoint(
                    timestamp: timestamp,
                    probability: vadResult.probability,
                    isSpeech: vadResult.isSpeech
                ))
                if vadResult.isSpeech {
                    speechFrames += 1
                }
            }
            
            dataPoints = points
            speechPercentage = vadResults.isEmpty ? 0 : Double(speechFrames) / Double(vadResults.count) * 100
            
            // Prepare audio player
            try prepareAudioPlayer(url: url)
            
            statusMessage = "Processed \(vadResults.count) frames"
            isProcessed = true
            
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }
        
        isProcessing = false
    }
    
    // MARK: - Audio Playback
    
    private func prepareAudioPlayer(url: URL) throws {
        audioPlayer = try AVAudioPlayer(contentsOf: url)
        audioPlayer?.prepareToPlay()
    }
    
    func togglePlayPause() {
        if isPlaying {
            pausePlayback()
        } else {
            startPlayback()
        }
    }
    
    func startPlayback() {
        guard let player = audioPlayer else { return }
        
        player.play()
        isPlaying = true
        
        // Start timer to update playback position
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updatePlaybackPosition()
            }
        }
    }
    
    func pausePlayback() {
        audioPlayer?.pause()
        isPlaying = false
        playbackTimer?.invalidate()
        playbackTimer = nil
    }
    
    func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        isPlaying = false
        currentPlaybackTime = 0
        playbackProgress = 0
        playbackTimer?.invalidate()
        playbackTimer = nil
    }
    
    func seekTo(progress: Double) {
        guard let player = audioPlayer else { return }
        let newTime = progress * audioDuration
        player.currentTime = newTime
        updatePlaybackPosition()
    }
    
    private func updatePlaybackPosition() {
        guard let player = audioPlayer else { return }
        
        currentPlaybackTime = player.currentTime
        playbackProgress = audioDuration > 0 ? currentPlaybackTime / audioDuration : 0
        
        // Check if playback finished
        if !player.isPlaying && isPlaying {
            isPlaying = false
            playbackTimer?.invalidate()
            playbackTimer = nil
            
            // Reset to beginning
            currentPlaybackTime = 0
            playbackProgress = 0
            player.currentTime = 0
        }
    }
    
    /// Reset the view to initial state
    func reset() {
        stopPlayback()
        audioPlayer = nil
        dataPoints = []
        isProcessed = false
        statusMessage = "Ready to process audio"
        audioDuration = 0
        speechPercentage = 0
    }
}
