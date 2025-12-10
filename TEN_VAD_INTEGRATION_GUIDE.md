# TEN VAD Integration Guide for macOS Swift Projects

This guide explains how to integrate the TEN VAD (Voice Activity Detection) library into your Xcode Swift project and use it to detect speech and pauses in audio.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Library Files](#library-files)
3. [Xcode Project Setup](#xcode-project-setup)
4. [Swift Wrapper](#swift-wrapper)
5. [Usage Examples](#usage-examples)
6. [Detecting Pauses](#detecting-pauses)
7. [Best Practices](#best-practices)

---

## Prerequisites

- macOS 14.0+ (Sonoma)
- Xcode 15.0+
- Swift 5.0+

---

## Library Files

The TEN VAD library consists of two files located at:

```
ThirdParty/
├── libten_vad.dylib    # Dynamic library (universal: x86_64 + arm64)
└── ten_vad.h           # C header file
```

Copy both files to your project.

---

## Xcode Project Setup

### Step 1: Add Library Files to Your Project

1. Create a `ThirdParty` folder in your Xcode project
2. Copy `libten_vad.dylib` and `ten_vad.h` into this folder
3. Drag the folder into Xcode's Project Navigator
4. In the dialog, check **"Copy items if needed"** and select your app target

### Step 2: Create Bridging Header

1. Create a new file: `YourAppName-Bridging-Header.h`
2. Add the following content:

```objc
//
//  YourAppName-Bridging-Header.h
//

#import "ThirdParty/ten_vad.h"
```

3. In Xcode, go to your target's **Build Settings**
4. Search for **"Objective-C Bridging Header"**
5. Set the value to: `YourAppName/YourAppName-Bridging-Header.h`

### Step 3: Configure Build Settings

In your target's **Build Settings**, configure the following:

#### Header Search Paths
```
$(PROJECT_DIR)/YourAppName/ThirdParty
```

#### Library Search Paths
```
$(PROJECT_DIR)/YourAppName/ThirdParty
```

#### Other Linker Flags
```
-lten_vad
```

#### Runpath Search Paths
```
@executable_path/../Frameworks
@loader_path/../Frameworks
```

#### Disable User Script Sandboxing
Set **"User Script Sandboxing"** to **No** (required for the copy script)

### Step 4: Add Copy Files Build Phase

The dynamic library must be copied to the app bundle at build time.

1. Select your target → **Build Phases**
2. Click **+** → **New Run Script Phase**
3. Name it "Copy TEN VAD Library"
4. Add this script:

```bash
mkdir -p "${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}"
cp "${PROJECT_DIR}/YourAppName/ThirdParty/libten_vad.dylib" "${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}/"
codesign --force --sign - "${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}/libten_vad.dylib"
```

5. Add Input Files:
```
$(PROJECT_DIR)/YourAppName/ThirdParty/libten_vad.dylib
```

6. Add Output Files:
```
$(BUILT_PRODUCTS_DIR)/$(FRAMEWORKS_FOLDER_PATH)/libten_vad.dylib
```

### Step 5: Disable App Sandbox (if needed)

If your app needs to access files outside the sandbox, update your `.entitlements` file:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
</dict>
</plist>
```

---

## Swift Wrapper

Create a Swift file named `TenVAD.swift` with the following content:

```swift
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
    /// - Parameter frame: Array of Int16 samples (must match hopSize, 16kHz mono)
    /// - Returns: VADResult with probability and speech flag, or nil on error
    func process(frame: [Int16]) -> VADResult? {
        guard handle != nil else { return nil }
        guard frame.count == hopSize else { return nil }
        
        var probability: Float = 0.0
        var flag: Int32 = 0
        
        let result = frame.withUnsafeBufferPointer { ptr -> Int32 in
            return ten_vad_process(handle, ptr.baseAddress, hopSize, &probability, &flag)
        }
        
        if result != 0 { return nil }
        
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
```

---

## Usage Examples

### Basic Usage

```swift
// Initialize VAD
guard let vad = TenVAD(hopSize: 256, threshold: 0.5) else {
    print("Failed to initialize VAD")
    return
}

// Process a frame of audio (256 samples of 16kHz mono Int16)
let audioFrame: [Int16] = // ... your audio data
if let result = vad.process(frame: audioFrame) {
    print("Probability: \(result.probability), Speech: \(result.isSpeech)")
}
```

### Processing Audio from AVAudioEngine (Real-time)

```swift
import AVFoundation

class RealtimeVAD {
    private let engine = AVAudioEngine()
    private let vad: TenVAD
    private var sampleBuffer = [Int16]()
    private let hopSize = 256
    
    init?() {
        guard let vad = TenVAD(hopSize: hopSize, threshold: 0.5) else {
            return nil
        }
        self.vad = vad
    }
    
    func start() throws {
        let input = engine.inputNode
        
        // Target format: 16kHz mono Float32
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ) else { return }
        
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.processBuffer(buffer)
        }
        
        engine.prepare()
        try engine.start()
    }
    
    private func processBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let floatData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        
        // Convert Float32 to Int16
        for i in 0..<frameCount {
            let sample = max(-1.0, min(1.0, floatData[i]))
            sampleBuffer.append(Int16(sample * Float(Int16.max)))
            
            if sampleBuffer.count == hopSize {
                if let result = vad.process(frame: sampleBuffer) {
                    DispatchQueue.main.async {
                        self.handleResult(result)
                    }
                }
                sampleBuffer.removeAll(keepingCapacity: true)
            }
        }
    }
    
    private func handleResult(_ result: TenVAD.VADResult) {
        if result.isSpeech {
            print("Speech detected! Probability: \(result.probability)")
        }
    }
    
    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }
}
```

---

## Detecting Pauses

Pause detection is essential for voice interfaces, transcription, and conversation analysis. Here's a complete implementation:

### PauseDetector Class

```swift
import Foundation

/// Detects pauses (silence) in speech using TEN VAD
final class PauseDetector {
    
    /// Pause event types
    enum PauseEvent {
        case speechStarted
        case speechEnded(duration: TimeInterval)
        case pauseDetected(duration: TimeInterval)
        case longPauseDetected(duration: TimeInterval)
    }
    
    /// Configuration for pause detection
    struct Config {
        /// VAD threshold (0.0 - 1.0)
        var threshold: Float = 0.5
        
        /// Hop size in samples (160 = 10ms, 256 = 16ms at 16kHz)
        var hopSize: Int = 256
        
        /// Minimum pause duration to trigger pauseDetected (seconds)
        var minPauseDuration: TimeInterval = 0.3
        
        /// Duration for a "long pause" / end of utterance (seconds)
        var longPauseDuration: TimeInterval = 1.0
        
        /// Minimum speech duration to consider it valid speech (seconds)
        var minSpeechDuration: TimeInterval = 0.1
    }
    
    private let vad: TenVAD
    private let config: Config
    private let sampleRate: Double = 16000
    
    // State tracking
    private var isSpeaking = false
    private var speechStartTime: TimeInterval = 0
    private var silenceStartTime: TimeInterval = 0
    private var currentTime: TimeInterval = 0
    private var consecutiveSpeechFrames = 0
    private var consecutiveSilenceFrames = 0
    
    // Callbacks
    var onPauseEvent: ((PauseEvent) -> Void)?
    
    /// Frame duration in seconds
    private var frameDuration: TimeInterval {
        Double(config.hopSize) / sampleRate
    }
    
    init?(config: Config = Config()) {
        guard let vad = TenVAD(hopSize: config.hopSize, threshold: config.threshold) else {
            return nil
        }
        self.vad = vad
        self.config = config
    }
    
    /// Reset the detector state
    func reset() {
        isSpeaking = false
        speechStartTime = 0
        silenceStartTime = 0
        currentTime = 0
        consecutiveSpeechFrames = 0
        consecutiveSilenceFrames = 0
    }
    
    /// Process a single audio frame
    /// - Parameter frame: Array of Int16 samples (must match hopSize)
    func processFrame(_ frame: [Int16]) {
        guard let result = vad.process(frame: frame) else { return }
        
        currentTime += frameDuration
        
        if result.isSpeech {
            handleSpeechFrame()
        } else {
            handleSilenceFrame()
        }
    }
    
    /// Process a buffer of samples
    /// - Parameter samples: Array of Int16 samples
    func processBuffer(_ samples: [Int16]) {
        var offset = 0
        while offset + config.hopSize <= samples.count {
            let frame = Array(samples[offset..<(offset + config.hopSize)])
            processFrame(frame)
            offset += config.hopSize
        }
    }
    
    private func handleSpeechFrame() {
        consecutiveSpeechFrames += 1
        consecutiveSilenceFrames = 0
        
        // Check if this is the start of speech
        let minSpeechFrames = Int(config.minSpeechDuration / frameDuration)
        
        if !isSpeaking && consecutiveSpeechFrames >= minSpeechFrames {
            isSpeaking = true
            speechStartTime = currentTime - config.minSpeechDuration
            onPauseEvent?(.speechStarted)
        }
    }
    
    private func handleSilenceFrame() {
        consecutiveSilenceFrames += 1
        
        if isSpeaking && consecutiveSilenceFrames == 1 {
            // Just started silence, record the time
            silenceStartTime = currentTime
        }
        
        consecutiveSpeechFrames = 0
        
        guard isSpeaking else { return }
        
        let silenceDuration = currentTime - silenceStartTime
        
        // Check for long pause (end of utterance)
        if silenceDuration >= config.longPauseDuration {
            let speechDuration = silenceStartTime - speechStartTime
            isSpeaking = false
            onPauseEvent?(.speechEnded(duration: speechDuration))
            onPauseEvent?(.longPauseDetected(duration: silenceDuration))
        }
        // Check for regular pause
        else if silenceDuration >= config.minPauseDuration {
            // Only fire once when we first cross the threshold
            let previousDuration = silenceDuration - frameDuration
            if previousDuration < config.minPauseDuration {
                onPauseEvent?(.pauseDetected(duration: silenceDuration))
            }
        }
    }
    
    /// Get pause statistics from a buffer of samples
    /// - Parameter samples: Array of Int16 samples
    /// - Returns: Array of detected pauses with their timestamps and durations
    func analyzePauses(in samples: [Int16]) -> [PauseInfo] {
        reset()
        
        var pauses: [PauseInfo] = []
        var currentPauseStart: TimeInterval?
        
        let results = vad.processBuffer(samples: samples)
        
        for (index, result) in results.enumerated() {
            let timestamp = Double(index) * frameDuration
            
            if result.isSpeech {
                // End of pause
                if let pauseStart = currentPauseStart {
                    let duration = timestamp - pauseStart
                    if duration >= config.minPauseDuration {
                        pauses.append(PauseInfo(
                            startTime: pauseStart,
                            endTime: timestamp,
                            duration: duration
                        ))
                    }
                    currentPauseStart = nil
                }
            } else {
                // Start of pause
                if currentPauseStart == nil {
                    currentPauseStart = timestamp
                }
            }
        }
        
        // Handle trailing pause
        if let pauseStart = currentPauseStart {
            let endTime = Double(results.count) * frameDuration
            let duration = endTime - pauseStart
            if duration >= config.minPauseDuration {
                pauses.append(PauseInfo(
                    startTime: pauseStart,
                    endTime: endTime,
                    duration: duration
                ))
            }
        }
        
        return pauses
    }
}

/// Information about a detected pause
struct PauseInfo {
    let startTime: TimeInterval
    let endTime: TimeInterval
    let duration: TimeInterval
    
    var description: String {
        String(format: "Pause at %.2fs - %.2fs (%.2fs)", startTime, endTime, duration)
    }
}
```

### Usage: Real-time Pause Detection

```swift
// Initialize
guard let detector = PauseDetector(config: PauseDetector.Config(
    threshold: 0.5,
    minPauseDuration: 0.3,    // Detect pauses > 300ms
    longPauseDuration: 1.5     // End of utterance > 1.5s
)) else { return }

// Set up callbacks
detector.onPauseEvent = { event in
    switch event {
    case .speechStarted:
        print("🎤 User started speaking")
        
    case .speechEnded(let duration):
        print("🔇 User stopped speaking (spoke for \(String(format: "%.1f", duration))s)")
        
    case .pauseDetected(let duration):
        print("⏸️ Short pause detected: \(String(format: "%.1f", duration))s")
        
    case .longPauseDetected(let duration):
        print("⏹️ Long pause / utterance end: \(String(format: "%.1f", duration))s")
    }
}

// Process audio frames as they arrive
detector.processFrame(audioFrame)
```

### Usage: Analyze Pauses in Audio File

```swift
// Analyze all pauses in an audio buffer
let pauses = detector.analyzePauses(in: audioSamples)

print("Found \(pauses.count) pauses:")
for pause in pauses {
    print("  - \(pause.description)")
}

// Example output:
// Found 3 pauses:
//   - Pause at 2.45s - 3.12s (0.67s)
//   - Pause at 5.80s - 6.35s (0.55s)
//   - Pause at 10.20s - 11.85s (1.65s)
```

### Usage: Segment Audio by Speech/Silence

```swift
/// Segment audio into speech and silence regions
func segmentAudio(samples: [Int16], hopSize: Int = 256, threshold: Float = 0.5) -> [(isSpeech: Bool, start: TimeInterval, end: TimeInterval)] {
    guard let vad = TenVAD(hopSize: hopSize, threshold: threshold) else { return [] }
    
    let results = vad.processBuffer(samples: samples)
    let frameDuration = Double(hopSize) / 16000.0
    
    var segments: [(isSpeech: Bool, start: TimeInterval, end: TimeInterval)] = []
    var currentSegmentStart: TimeInterval = 0
    var currentIsSpeech = results.first?.isSpeech ?? false
    
    for (index, result) in results.enumerated() {
        if result.isSpeech != currentIsSpeech {
            let timestamp = Double(index) * frameDuration
            segments.append((
                isSpeech: currentIsSpeech,
                start: currentSegmentStart,
                end: timestamp
            ))
            currentSegmentStart = timestamp
            currentIsSpeech = result.isSpeech
        }
    }
    
    // Add final segment
    let endTime = Double(results.count) * frameDuration
    segments.append((
        isSpeech: currentIsSpeech,
        start: currentSegmentStart,
        end: endTime
    ))
    
    return segments
}

// Usage
let segments = segmentAudio(samples: audioSamples)
for segment in segments {
    let type = segment.isSpeech ? "🎤 Speech" : "🔇 Silence"
    print("\(type): \(String(format: "%.2f", segment.start))s - \(String(format: "%.2f", segment.end))s")
}
```

---

## Best Practices

### Audio Format Requirements

TEN VAD requires:
- **Sample Rate**: 16,000 Hz (16 kHz)
- **Channels**: Mono (1 channel)
- **Format**: Int16 (signed 16-bit integers)

Always resample your audio if it's in a different format.

### Choosing Threshold

| Threshold | Use Case |
|-----------|----------|
| 0.3 - 0.4 | Sensitive detection, noisy environments |
| 0.5 | Balanced (default) |
| 0.6 - 0.7 | Less sensitive, clean audio |
| 0.8+ | Only very clear speech |

### Choosing Hop Size

| Hop Size | Frame Duration | Use Case |
|----------|----------------|----------|
| 160 | 10ms | Higher time resolution, more CPU |
| 256 | 16ms | Good balance (recommended) |

### Performance Tips

1. **Reuse TenVAD instance** - Don't create/destroy for each frame
2. **Process in batches** when analyzing files
3. **Use background threads** for processing, update UI on main thread
4. **Buffer audio samples** to avoid processing partial frames

### Common Pitfalls

1. **Wrong sample rate** - Always resample to 16kHz
2. **Wrong frame size** - Frame must exactly match hopSize
3. **Stereo audio** - Convert to mono first
4. **Float samples** - Convert to Int16

---

## API Reference

### C API (from ten_vad.h)

```c
// Create VAD instance
int ten_vad_create(ten_vad_handle_t *handle, size_t hop_size, float threshold);

// Process one frame
int ten_vad_process(ten_vad_handle_t handle, const int16_t *audio_data, 
                    size_t audio_data_length, float *out_probability, int *out_flag);

// Destroy instance
int ten_vad_destroy(ten_vad_handle_t *handle);

// Get version string
const char *ten_vad_get_version(void);
```

### Return Values

- `0` = Success
- `-1` = Error

---

## Troubleshooting

### "Library not loaded" Error

Ensure the dylib is copied to Frameworks folder and has correct install name:
```bash
otool -L /path/to/libten_vad.dylib
# Should show: @rpath/libten_vad.dylib
```

If not, fix it:
```bash
install_name_tool -id "@rpath/libten_vad.dylib" /path/to/libten_vad.dylib
```

### "Code signature invalid" Error

Re-sign the library in your build script:
```bash
codesign --force --sign - "${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}/libten_vad.dylib"
```

### VAD Returns nil

- Check that hopSize matches between init and process calls
- Ensure frame array has exactly hopSize elements
- Verify audio is 16kHz mono Int16

---

## License

TEN VAD is part of the TEN Framework by Agora, licensed under Apache License 2.0.
See: https://github.com/TEN-framework/ten-vad
