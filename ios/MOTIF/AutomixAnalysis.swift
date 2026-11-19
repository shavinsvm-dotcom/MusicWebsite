import AVFoundation
import Foundation

struct BeatGrid: Codable, Equatable {
    let bpm: Double
    let firstBeat: TimeInterval
    let confidence: Double
    let duration: TimeInterval

    var beatInterval: TimeInterval {
        60 / max(bpm, 1)
    }

    func beat(atOrBefore time: TimeInterval) -> TimeInterval {
        guard time > firstBeat else { return firstBeat }
        let steps = floor((time - firstBeat) / beatInterval)
        return firstBeat + steps * beatInterval
    }

    func beat(after time: TimeInterval) -> TimeInterval {
        guard time >= firstBeat else { return firstBeat }
        let steps = ceil((time - firstBeat) / beatInterval)
        return firstBeat + steps * beatInterval
    }

    /// Start of the 4/4 bar containing `time`. Mixing on a bar line avoids
    /// starting a transition on a weak beat.
    func downbeat(atOrBefore time: TimeInterval) -> TimeInterval {
        let bar = beatInterval * 4
        guard time > firstBeat else { return firstBeat }
        let steps = floor((time - firstBeat) / bar)
        return firstBeat + steps * bar
    }

    /// Start of the phrase (a group of bars) containing `time`. Two bars is a
    /// common, conservative phrase length for a short crossfade.
    func phraseStart(atOrBefore time: TimeInterval, bars: Int = 2) -> TimeInterval {
        let phrase = beatInterval * Double(max(bars, 1) * 4)
        guard time > firstBeat else { return firstBeat }
        let steps = floor((time - firstBeat) / phrase)
        return firstBeat + steps * phrase
    }
}

struct AutomixPlan {
    let nextIndex: Int
    let next: Track
    let outgoingStart: TimeInterval
    let incomingStart: TimeInterval
    let incomingRate: Float
    let duration: TimeInterval
}

final class AutomixAnalysisStore {
    static let shared = AutomixAnalysisStore()

    private let lock = NSLock()
    private var grids: [String: BeatGrid] = [:]
    private let fileURL: URL?

    private init() {
        let manager = FileManager.default
        let support = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        if let support {
            let folder = support.appendingPathComponent("MOTIF", isDirectory: true)
            try? manager.createDirectory(at: folder, withIntermediateDirectories: true)
            fileURL = folder.appendingPathComponent("automix-grids.json")
        } else {
            fileURL = nil
        }

        if let fileURL,
           let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([String: BeatGrid].self, from: data) {
            grids = decoded
        }
    }

    static func key(for track: Track) -> String {
        let attributes = try? FileManager.default.attributesOfItem(atPath: track.mediaURL.path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let identity = track.remoteID ?? track.id.uuidString
        return "\(identity):\(size):\(Int(modified))"
    }

    func grid(for key: String) -> BeatGrid? {
        lock.lock()
        defer { lock.unlock() }
        return grids[key]
    }

    func store(_ grid: BeatGrid, for key: String) {
        lock.lock()
        defer { lock.unlock() }
        grids[key] = grid
        guard let fileURL, let data = try? JSONEncoder().encode(grids) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

@MainActor
final class AutomixAnalysisService {
    static let shared = AutomixAnalysisService()

    private let store = AutomixAnalysisStore.shared
    private var tasks: [String: Task<BeatGrid?, Never>] = [:]
    private var memory: [UUID: BeatGrid] = [:]

    func grid(for track: Track) -> BeatGrid? {
        if let cached = memory[track.id] {
            return cached
        }
        guard let cached = store.grid(for: AutomixAnalysisStore.key(for: track)) else {
            return nil
        }
        memory[track.id] = cached
        return cached
    }

    func analyze(_ track: Track) async -> BeatGrid? {
        guard track.mediaURL.isFileURL else { return nil }

        let key = AutomixAnalysisStore.key(for: track)
        if let cached = grid(for: track) {
            return cached
        }
        if let existing = tasks[key] {
            return await existing.value
        }

        let url = track.mediaURL
        let duration = track.duration
        let task = Task {
            await AudioBeatAnalyzer.analyze(url: url, duration: duration)
        }
        tasks[key] = task

        let result = await task.value
        tasks[key] = nil
        if let result {
            store.store(result, for: key)
            memory[track.id] = result
        }
        return result
    }
}

enum AudioBeatAnalyzer {
    private static let sampleRate: Double = 22_050
    private static let frameSize = 512
    private static let hopSize = 256
    private static let maxAnalysisSeconds: TimeInterval = 90
    private static let minimumBPM: Double = 70
    private static let maximumBPM: Double = 160

    static func analyze(url: URL, duration: TimeInterval) async -> BeatGrid? {
        await Task.detached(priority: .utility) {
            analyzeSynchronously(url: url, duration: duration)
        }.value
    }

    private static func analyzeSynchronously(url: URL, duration: TimeInterval) -> BeatGrid? {
        guard duration >= 8,
              FileManager.default.fileExists(atPath: url.path)
        else { return nil }

        let asset = AVURLAsset(url: url)
        guard let audioTrack = asset.tracks(withMediaType: .audio).first else {
            return nil
        }

        guard let reader = try? AVAssetReader(asset: asset) else { return nil }
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return nil }
        reader.add(output)

        let analysisDuration = min(max(duration, 8), maxAnalysisSeconds)
        reader.timeRange = CMTimeRange(
            start: .zero,
            duration: CMTime(seconds: analysisDuration, preferredTimescale: 600)
        )
        guard reader.startReading() else { return nil }

        var samples: [Float] = []
        samples.reserveCapacity(Int(sampleRate * analysisDuration))
        let maximumSamples = Int(sampleRate * analysisDuration)

        while let sampleBuffer = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            let byteCount = CMBlockBufferGetDataLength(block)
            guard byteCount >= MemoryLayout<Float>.size else { continue }

            let count = byteCount / MemoryLayout<Float>.size
            var chunk = [Float](repeating: 0, count: count)
            chunk.withUnsafeMutableBytes { raw in
                guard let destination = raw.baseAddress else { return }
                _ = CMBlockBufferCopyDataBytes(
                    block,
                    atOffset: 0,
                    dataLength: byteCount,
                    destination: destination
                )
            }
            samples.append(contentsOf: chunk)
            if samples.count >= maximumSamples { break }
        }
        reader.cancelReading()

        guard samples.count >= Int(sampleRate * 8) else { return nil }
        return analyze(samples: samples, duration: duration)
    }

    private static func analyze(samples: [Float], duration: TimeInterval) -> BeatGrid? {
        guard samples.count > frameSize else { return nil }

        var energy: [Float] = []
        energy.reserveCapacity(samples.count / hopSize)
        var previousRMS: Float = 0

        for start in stride(from: 0, through: samples.count - frameSize, by: hopSize) {
            var sum: Float = 0
            for index in start..<(start + frameSize) {
                let value = samples[index]
                sum += value * value
            }
            let rms = sqrt(sum / Float(frameSize))
            energy.append(max(0, rms - previousRMS))
            previousRMS = rms
        }

        guard energy.count > 2 else { return nil }

        let smoothed = (0..<energy.count).map { index -> Float in
            let previous = energy[max(0, index - 1)]
            let next = energy[min(energy.count - 1, index + 1)]
            return previous * 0.25 + energy[index] * 0.5 + next * 0.25
        }

        let mean = smoothed.reduce(0, +) / Float(smoothed.count)
        var envelope = smoothed.map { max(0, $0 - mean) }
        let peak = envelope.max() ?? 0
        guard peak > 0.0001 else { return nil }
        envelope = envelope.map { $0 / peak }

        let hopSeconds = Double(hopSize) / sampleRate
        let minLag = max(1, Int((60 / maximumBPM) / hopSeconds))
        let maxLag = min(envelope.count / 2, Int((60 / minimumBPM) / hopSeconds))
        guard maxLag > minLag else { return nil }

        var bestLag = minLag
        var bestScore: Double = 0
        var scores = [Double](repeating: 0, count: maxLag + 1)

        for lag in minLag...maxLag {
            var dot: Double = 0
            var leftEnergy: Double = 0
            var rightEnergy: Double = 0

            for index in 0..<(envelope.count - lag) {
                let left = Double(envelope[index])
                let right = Double(envelope[index + lag])
                dot += left * right
                leftEnergy += left * left
                rightEnergy += right * right
            }

            let score = dot / sqrt(leftEnergy * rightEnergy + 0.0000001)
            scores[lag] = score
            if score > bestScore {
                bestScore = score
                bestLag = lag
            }
        }

        guard bestScore > 0.12 else { return nil }

        var refinedLag = Double(bestLag)
        if bestLag > minLag, bestLag < maxLag {
            let left = scores[bestLag - 1]
            let right = scores[bestLag + 1]
            let denominator = left - 2 * bestScore + right
            if abs(denominator) > 0.0000001 {
                refinedLag += 0.5 * (left - right) / denominator
            }
        }

        var bpm = 60 / (refinedLag * hopSeconds)
        while bpm < minimumBPM { bpm *= 2 }
        while bpm > maximumBPM { bpm /= 2 }

        let beatPeriod = 60 / (bpm * hopSeconds)
        let phaseCount = max(1, Int(ceil(beatPeriod)))
        var bestPhase = 0
        var bestPhaseScore: Double = 0

        for phase in 0..<phaseCount {
            var score: Double = 0
            var count = 0
            var index = Double(phase)
            while index < Double(envelope.count - 1) {
                let lower = Int(index)
                let fraction = index - Double(lower)
                score += Double(envelope[lower]) * (1 - fraction)
                    + Double(envelope[lower + 1]) * fraction
                count += 1
                index += beatPeriod
            }
            let normalized = score / Double(max(count, 1))
            if normalized > bestPhaseScore {
                bestPhaseScore = normalized
                bestPhase = phase
            }
        }

        let confidence = min(1, max(0, (bestScore - 0.08) * 2.4))
        guard confidence >= 0.12 else { return nil }

        let interval = 60 / bpm
        let firstBeat = (Double(bestPhase) * hopSeconds).truncatingRemainder(dividingBy: interval)

        return BeatGrid(
            bpm: bpm,
            firstBeat: firstBeat,
            confidence: confidence,
            duration: duration
        )
    }
}
