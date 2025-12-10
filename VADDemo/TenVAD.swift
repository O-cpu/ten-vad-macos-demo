//
//  TenVAD.swift
//  VADDemo
//
//  Swift wrapper for TEN VAD C library
//

import Foundation

/// Swift wrapper for TEN VAD voice activity detection library
final class TenVAD {
    private var handle: ten_vad_handle_t?
    let hopSize: Int
    let threshold: Float
    
    /// Result from VAD processing
    struct VADResult {
        let probability: Float
        let isSpeech: Bool
    }
    
    /// Initialize TEN VAD instance
    /// - Parameters:
    ///   - hopSize: Number of samples per frame (160 = 10ms, 256 = 16ms at 16kHz)
    ///   - threshold: Voice detection threshold (0.0 - 1.0, default 0.5)
    init?(hopSize: Int = 256, threshold: Float = 0.5) {
        self.hopSize = hopSize
        self.threshold = threshold
        
        var handlePtr: ten_vad_handle_t? = nil
        let result = ten_vad_create(&handlePtr, hopSize, threshold)
        
        if result != 0 || handlePtr == nil {
            print("Failed to create TEN VAD instance")
            return nil
        }
        
        self.handle = handlePtr
        print("TEN VAD initialized - version: \(TenVAD.version)")
    }
    
    deinit {
        if handle != nil {
            ten_vad_destroy(&handle)
        }
    }
    
    /// Get TEN VAD library version
    static var version: String {
        if let versionPtr = ten_vad_get_version() {
            return String(cString: versionPtr)
        }
        return "unknown"
    }
    
    /// Process a single audio frame for voice activity detection
    /// - Parameter frame: Array of Int16 samples (must match hopSize)
    /// - Returns: VADResult with probability and speech flag, or nil on error
    func process(frame: [Int16]) -> VADResult? {
        guard handle != nil else {
            print("TEN VAD handle is nil")
            return nil
        }
        
        guard frame.count == hopSize else {
            print("Frame size mismatch: expected \(hopSize), got \(frame.count)")
            return nil
        }
        
        var probability: Float = 0.0
        var flag: Int32 = 0
        
        let result = frame.withUnsafeBufferPointer { ptr -> Int32 in
            return ten_vad_process(handle, ptr.baseAddress, hopSize, &probability, &flag)
        }
        
        if result != 0 {
            print("TEN VAD process failed with code: \(result)")
            return nil
        }
        
        return VADResult(probability: probability, isSpeech: flag == 1)
    }
    
    /// Process multiple frames at once
    /// - Parameter samples: Array of Int16 samples (will be split into frames)
    /// - Returns: Array of VADResult for each complete frame
    func processBuffer(samples: [Int16]) -> [VADResult] {
        var results: [VADResult] = []
        var offset = 0
        
        while offset + hopSize <= samples.count {
            let frame = Array(samples[offset..<(offset + hopSize)])
            if let result = process(frame: frame) {
                results.append(result)
            }
            offset += hopSize
        }
        
        return results
    }
}
