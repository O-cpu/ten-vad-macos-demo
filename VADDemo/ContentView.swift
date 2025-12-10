//
//  ContentView.swift
//  VADDemo
//
//  TEN VAD macOS Demo - Voice Activity Detection Visualization
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var viewModel = VADViewModel()
    @State private var showFileImporter = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            headerSection
            
            Divider()
            
            // Configuration
            configurationSection
            
            Divider()
            
            // Visualization
            if viewModel.isProcessed {
                visualizationSection
            } else {
                placeholderSection
            }
            
            Divider()
            
            // Controls
            controlsSection
            
            // Status
            statusSection
        }
        .padding()
        .frame(minWidth: 800, minHeight: 600)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.audio, .mpeg4Audio, .mp3, .wav, .aiff],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    // Start accessing the security-scoped resource
                    if url.startAccessingSecurityScopedResource() {
                        viewModel.setAudioFile(url: url)
                        // Note: We should call stopAccessingSecurityScopedResource() when done
                        // but for simplicity we keep access for the session
                    } else {
                        viewModel.setAudioFile(url: url)
                    }
                }
            case .failure(let error):
                print("File selection error: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "waveform.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.blue)
                Text("TEN VAD Test")
                    .font(.largeTitle)
                    .bold()
            }
            Text("Voice Activity Detection Library Test")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Library Version: \(viewModel.libraryVersion)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
    
    // MARK: - Configuration Section
    
    private var configurationSection: some View {
        HStack(spacing: 40) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Threshold: \(String(format: "%.2f", viewModel.threshold))")
                    .font(.caption)
                Slider(value: $viewModel.threshold, in: 0.0...1.0)
                    .frame(width: 150)
                    .disabled(viewModel.isProcessing)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Hop Size: \(viewModel.hopSize) samples")
                    .font(.caption)
                Picker("", selection: $viewModel.hopSize) {
                    Text("160 (10ms)").tag(160)
                    Text("256 (16ms)").tag(256)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                .disabled(viewModel.isProcessing)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Audio File:")
                    .font(.caption)
                HStack(spacing: 8) {
                    Text(viewModel.currentFileName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 200, alignment: .leading)
                    
                    Button(action: {
                        showFileImporter = true
                    }) {
                        Image(systemName: "folder.badge.plus")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(viewModel.isProcessing)
                }
            }
        }
        .padding(.vertical, 8)
    }
    
    // MARK: - Visualization Section
    
    private var visualizationSection: some View {
        VStack(spacing: 12) {
            // Stats
            HStack(spacing: 40) {
                StatBox(title: "Duration", value: String(format: "%.2f sec", viewModel.audioDuration))
                StatBox(title: "Frames", value: "\(viewModel.dataPoints.count)")
                StatBox(title: "Speech", value: String(format: "%.1f%%", viewModel.speechPercentage))
            }
            
            // Chart with playback position
            VADChartWithPlayhead(
                dataPoints: viewModel.dataPoints,
                threshold: viewModel.threshold,
                playbackProgress: viewModel.playbackProgress,
                onSeek: { progress in
                    viewModel.seekTo(progress: progress)
                }
            )
            .frame(height: 280)
            
            // Playback time display
            HStack {
                Text(formatTime(viewModel.currentPlaybackTime))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatTime(viewModel.audioDuration))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 45)
            
            // Playback controls
            playbackControlsSection
            
            // Legend
            HStack(spacing: 20) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(.green)
                        .frame(width: 10, height: 10)
                    Text("Speech Detected")
                        .font(.caption)
                }
                HStack(spacing: 4) {
                    Circle()
                        .fill(.gray.opacity(0.5))
                        .frame(width: 10, height: 10)
                    Text("No Speech")
                        .font(.caption)
                }
                HStack(spacing: 4) {
                    Rectangle()
                        .fill(.orange)
                        .frame(width: 20, height: 2)
                    Text("Threshold (\(String(format: "%.2f", viewModel.threshold)))")
                        .font(.caption)
                }
                HStack(spacing: 4) {
                    Text("▲")
                        .font(.caption)
                        .foregroundStyle(.blue)
                    Text("Playback Position")
                        .font(.caption)
                }
            }
        }
    }
    
    // MARK: - Playback Controls Section
    
    private var playbackControlsSection: some View {
        HStack(spacing: 16) {
            // Stop button
            Button(action: {
                viewModel.stopPlayback()
            }) {
                Image(systemName: "stop.fill")
                    .font(.title2)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.bordered)
            .disabled(!viewModel.isProcessed)
            
            // Play/Pause button
            Button(action: {
                viewModel.togglePlayPause()
            }) {
                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title)
                    .frame(width: 60, height: 60)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.isProcessed)
        }
    }
    
    // MARK: - Placeholder Section
    
    private var placeholderSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("No audio processed yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Click 'Process Audio' to analyze the file")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Controls Section
    
    private var controlsSection: some View {
        HStack(spacing: 20) {
            Button(action: {
                showFileImporter = true
            }) {
                HStack {
                    Image(systemName: "folder")
                    Text("Open File")
                }
                .frame(width: 110)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isProcessing)
            
            Button(action: {
                Task {
                    await viewModel.processCurrentFile()
                }
            }) {
                HStack {
                    if viewModel.isProcessing {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "waveform.badge.magnifyingglass")
                    }
                    Text("Process Audio")
                }
                .frame(width: 140)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isProcessing || viewModel.currentAudioURL == nil)
            
            Button(action: {
                viewModel.reset()
            }) {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Reset")
                }
                .frame(width: 100)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isProcessing)
        }
    }
    
    // MARK: - Status Section
    
    private var statusSection: some View {
        HStack {
            if viewModel.isProcessing {
                ProgressView()
                    .scaleEffect(0.7)
            }
            Text(viewModel.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(height: 20)
    }
    
    // MARK: - Helpers
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let milliseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%02d:%02d.%02d", minutes, seconds, milliseconds)
    }
}

// MARK: - Supporting Views

struct StatBox: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2)
                .bold()
        }
        .frame(width: 100)
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}

/// Aggregated data point for display
struct AggregatedDataPoint: Identifiable {
    let id = UUID()
    let avgProbability: Float
    let speechRatio: Float  // Ratio of speech frames in this bucket
    let isSpeech: Bool      // true if majority is speech
}

struct VADChartWithPlayhead: View {
    let dataPoints: [VADDataPoint]
    let threshold: Float
    let playbackProgress: Double
    let onSeek: (Double) -> Void
    
    // Minimum bar width in pixels
    private let minBarWidth: CGFloat = 2
    private let barSpacing: CGFloat = 1
    private let yAxisWidth: CGFloat = 35
    private let rightPadding: CGFloat = 10
    private let verticalPadding: CGFloat = 20
    private let playheadAreaHeight: CGFloat = 25
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Chart area
                ZStack {
                    // Background
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.05))
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    
                    // Chart content
                    if !dataPoints.isEmpty {
                        chartContent(in: geometry)
                    }
                }
                .frame(height: geometry.size.height - playheadAreaHeight)
                
                // Playhead indicator area
                playheadIndicator(in: geometry)
                    .frame(height: playheadAreaHeight)
            }
        }
    }
    
    /// Aggregate data points to fit within the available width
    private func aggregateDataPoints(forWidth width: CGFloat) -> [AggregatedDataPoint] {
        guard !dataPoints.isEmpty else { return [] }
        
        // Calculate how many bars we can fit
        let maxBars = Int(width / (minBarWidth + barSpacing))
        let numBars = min(maxBars, dataPoints.count)
        
        guard numBars > 0 else { return [] }
        
        // How many data points per bar
        let pointsPerBar = Double(dataPoints.count) / Double(numBars)
        
        var aggregated: [AggregatedDataPoint] = []
        
        for i in 0..<numBars {
            let startIdx = Int(Double(i) * pointsPerBar)
            let endIdx = min(Int(Double(i + 1) * pointsPerBar), dataPoints.count)
            
            guard startIdx < endIdx else { continue }
            
            let slice = dataPoints[startIdx..<endIdx]
            let avgProb = slice.map { $0.probability }.reduce(0, +) / Float(slice.count)
            let speechCount = slice.filter { $0.isSpeech }.count
            let speechRatio = Float(speechCount) / Float(slice.count)
            
            aggregated.append(AggregatedDataPoint(
                avgProbability: avgProb,
                speechRatio: speechRatio,
                isSpeech: speechRatio >= 0.5
            ))
        }
        
        return aggregated
    }
    
    private func chartContent(in geometry: GeometryProxy) -> some View {
        let chartWidth = geometry.size.width - yAxisWidth - rightPadding
        let chartHeight = geometry.size.height - playheadAreaHeight - (verticalPadding * 2)
        let aggregatedData = aggregateDataPoints(forWidth: chartWidth)
        
        return HStack(alignment: .top, spacing: 0) {
            // Y-axis labels
            VStack {
                Text("1.0")
                    .font(.caption2)
                Spacer()
                Text("0.5")
                    .font(.caption2)
                Spacer()
                Text("0.0")
                    .font(.caption2)
            }
            .frame(width: yAxisWidth)
            .foregroundStyle(.secondary)
            .padding(.vertical, verticalPadding)
            
            // Chart area with playhead line
            ZStack(alignment: .bottomLeading) {
                // Bars using Canvas for better performance
                Canvas { context, size in
                    let height = size.height
                    let totalWidth = size.width
                    let actualBarWidth = aggregatedData.isEmpty ? minBarWidth : (totalWidth / CGFloat(aggregatedData.count))
                    
                    for (index, point) in aggregatedData.enumerated() {
                        let barHeight = CGFloat(point.avgProbability) * height
                        let x = CGFloat(index) * actualBarWidth
                        let y = height - barHeight
                        
                        let rect = CGRect(x: x, y: y, width: actualBarWidth - barSpacing, height: barHeight)
                        
                        // Color based on speech ratio
                        let color: Color = point.isSpeech ? .green : .gray.opacity(0.4)
                        context.fill(Path(rect), with: .color(color))
                    }
                    
                    // Draw threshold line
                    let thresholdY = height - CGFloat(threshold) * height
                    var thresholdPath = Path()
                    thresholdPath.move(to: CGPoint(x: 0, y: thresholdY))
                    thresholdPath.addLine(to: CGPoint(x: totalWidth, y: thresholdY))
                    context.stroke(thresholdPath, with: .color(.orange), lineWidth: 2)
                    
                    // Draw playhead line
                    let playheadX = CGFloat(playbackProgress) * totalWidth
                    var playheadPath = Path()
                    playheadPath.move(to: CGPoint(x: playheadX, y: 0))
                    playheadPath.addLine(to: CGPoint(x: playheadX, y: height))
                    context.stroke(playheadPath, with: .color(.blue), lineWidth: 2)
                }
                .frame(width: chartWidth, height: chartHeight)
            }
            .padding(.vertical, verticalPadding)
            .padding(.trailing, rightPadding)
        }
    }
    
    private func playheadIndicator(in geometry: GeometryProxy) -> some View {
        let chartWidth = geometry.size.width - yAxisWidth - rightPadding
        
        return HStack(spacing: 0) {
            Spacer()
                .frame(width: yAxisWidth)
            
            // Clickable area for seeking
            GeometryReader { indicatorGeometry in
                ZStack(alignment: .leading) {
                    // Track background
                    Rectangle()
                        .fill(Color.gray.opacity(0.1))
                    
                    // Playhead triangle indicator
                    let playheadX = CGFloat(playbackProgress) * indicatorGeometry.size.width
                    
                    Text("▲")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.blue)
                        .position(x: playheadX, y: indicatorGeometry.size.height / 2)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let progress = max(0, min(1, value.location.x / indicatorGeometry.size.width))
                            onSeek(progress)
                        }
                )
            }
            .frame(width: chartWidth)
            
            Spacer()
                .frame(width: rightPadding)
        }
    }
}

#Preview {
    ContentView()
}
