//
//  AudioFileProcessor.swift
//  VADDemo
//
//  Loads and processes audio files for VAD testing
//

import Foundation
import AVFoundation

/// Handles loading and resampling audio files for VAD processing
final class AudioFileProcessor {
    
    /// The target sample rate required by TEN VAD
    static let targetSampleRate: Double = 16_000
    
    /// Result from processing an audio file
    struct ProcessingResult {
        let samples: [Int16]
        let duration: TimeInterval
        let originalSampleRate: Double
    }
    
    /// Load an audio file and convert to 16kHz mono Int16 samples
    /// - Parameter url: URL to the audio file
    /// - Returns: ProcessingResult containing the samples
    static func loadAudioFile(from url: URL) async throws -> ProcessingResult {
        let audioFile = try AVAudioFile(forReading: url)
        let originalFormat = audioFile.processingFormat
        let originalSampleRate = originalFormat.sampleRate
        let frameCount = AVAudioFrameCount(audioFile.length)
        
        print("Loading audio file: \(url.lastPathComponent)")
        print("Original format: \(originalFormat.sampleRate) Hz, \(originalFormat.channelCount) channels")
        print("Frame count: \(frameCount)")
        
        // Read the audio file into a buffer
        guard let buffer = AVAudioPCMBuffer(pcmFormat: originalFormat, frameCapacity: frameCount) else {
            throw AudioProcessorError.bufferCreationFailed
        }
        try audioFile.read(into: buffer)
        
        // Convert to 16kHz mono
        let samples = try resampleToMono16kHz(buffer: buffer)
        
        let duration = Double(audioFile.length) / originalSampleRate
        
        print("Converted to: \(samples.count) samples at 16kHz")
        print("Duration: \(String(format: "%.2f", duration)) seconds")
        
        return ProcessingResult(
            samples: samples,
            duration: duration,
            originalSampleRate: originalSampleRate
        )
    }
    
    /// Resample audio buffer to 16kHz mono Int16
    private static func resampleToMono16kHz(buffer: AVAudioPCMBuffer) throws -> [Int16] {
        let inputFormat = buffer.format
        
        // Create target format: 16kHz, mono, Float32
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioProcessorError.formatCreationFailed
        }
        
        // Create converter
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AudioProcessorError.converterCreationFailed
        }
        
        // Calculate output frame count based on sample rate ratio
        let ratio = targetSampleRate / inputFormat.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCount) else {
            throw AudioProcessorError.bufferCreationFailed
        }
        
        // Perform conversion
        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        
        converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
        
        if let error = error {
            throw AudioProcessorError.conversionFailed(error)
        }
        
        // Convert Float32 to Int16
        guard let floatData = outputBuffer.floatChannelData?[0] else {
            throw AudioProcessorError.noAudioData
        }
        
        let frameCount = Int(outputBuffer.frameLength)
        var int16Samples = [Int16](repeating: 0, count: frameCount)
        
        for i in 0..<frameCount {
            let sample = floatData[i]
            let clamped = max(-1.0, min(1.0, sample))
            int16Samples[i] = Int16(clamped * Float(Int16.max))
        }
        
        return int16Samples
    }
    
    enum AudioProcessorError: LocalizedError {
        case bufferCreationFailed
        case formatCreationFailed
        case converterCreationFailed
        case conversionFailed(Error)
        case noAudioData
        
        var errorDescription: String? {
            switch self {
            case .bufferCreationFailed:
                return "Failed to create audio buffer"
            case .formatCreationFailed:
                return "Failed to create audio format"
            case .converterCreationFailed:
                return "Failed to create audio converter"
            case .conversionFailed(let error):
                return "Audio conversion failed: \(error.localizedDescription)"
            case .noAudioData:
                return "No audio data in buffer"
            }
        }
    }
}
