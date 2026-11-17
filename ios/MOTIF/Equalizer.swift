import AVFoundation
import Combine
import Foundation

/// The user-facing three-band equalizer. The gain values are shared with the
/// audio tap so changes apply to the current track and to preloaded items.
final class Equalizer: ObservableObject {
    static let shared = Equalizer()

    @Published private(set) var isEnabled: Bool
    @Published private(set) var bass: Double
    @Published private(set) var mid: Double
    @Published private(set) var treble: Double

    private let defaults = UserDefaults.standard
    private let parameters: EqualizerParameters

    private enum Key {
        static let enabled = "motif.equalizer.enabled"
        static let bass = "motif.equalizer.bass"
        static let mid = "motif.equalizer.mid"
        static let treble = "motif.equalizer.treble"
    }

    private init() {
        let savedEnabled = defaults.object(forKey: Key.enabled) as? Bool ?? false
        let savedBass = defaults.object(forKey: Key.bass) as? Double ?? 0
        let savedMid = defaults.object(forKey: Key.mid) as? Double ?? 0
        let savedTreble = defaults.object(forKey: Key.treble) as? Double ?? 0

        let clampedBass = min(max(savedBass, -12), 12)
        let clampedMid = min(max(savedMid, -12), 12)
        let clampedTreble = min(max(savedTreble, -12), 12)

        isEnabled = savedEnabled
        bass = clampedBass
        mid = clampedMid
        treble = clampedTreble
        parameters = EqualizerParameters(
            gains: EqualizerGains(
                enabled: savedEnabled,
                bass: Float(clampedBass),
                mid: Float(clampedMid),
                treble: Float(clampedTreble)
            )
        )
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: Key.enabled)
        publish()
    }

    func setBass(_ value: Double) {
        bass = min(max(value, -12), 12)
        defaults.set(bass, forKey: Key.bass)
        publish()
    }

    func setMid(_ value: Double) {
        mid = min(max(value, -12), 12)
        defaults.set(mid, forKey: Key.mid)
        publish()
    }

    func setTreble(_ value: Double) {
        treble = min(max(value, -12), 12)
        defaults.set(treble, forKey: Key.treble)
        publish()
    }

    func reset() {
        setBass(0)
        setMid(0)
        setTreble(0)
    }

    func attach(to item: AVPlayerItem) {
        let parameters = parameters
        Task { @MainActor in
            EqualizerTap.attach(to: item, parameters: parameters)
        }
    }

    private func publish() {
        parameters.update(
            EqualizerGains(
                enabled: isEnabled,
                bass: Float(bass),
                mid: Float(mid),
                treble: Float(treble)
            )
        )
    }
}

private struct EqualizerGains: Equatable {
    var enabled: Bool
    var bass: Float
    var mid: Float
    var treble: Float

    var isNonFlat: Bool {
        abs(bass) > 0.01 || abs(mid) > 0.01 || abs(treble) > 0.01
    }
}

private final class EqualizerParameters {
    private let lock = NSLock()
    private var gains: EqualizerGains

    init(gains: EqualizerGains) {
        self.gains = gains
    }

    func update(_ gains: EqualizerGains) {
        lock.lock()
        self.gains = gains
        lock.unlock()
    }

    func snapshot() -> EqualizerGains {
        lock.lock()
        defer { lock.unlock() }
        return gains
    }
}

private enum EqualizerTap {
    @MainActor
    static func attach(to item: AVPlayerItem, parameters: EqualizerParameters) {
        let asset = item.asset

        Task { @MainActor in
            guard item.audioMix == nil else { return }

            do {
                let tracks = try await asset.loadTracks(withMediaType: .audio)
                guard let track = tracks.first, item.audioMix == nil else { return }
                install(on: item, track: track, parameters: parameters)
            } catch {
                // A track may not expose an audio track until it is ready.
                // Playback continues without EQ rather than failing the item.
            }
        }
    }

    @MainActor
    private static func install(
        on item: AVPlayerItem,
        track: AVAssetTrack,
        parameters: EqualizerParameters
    ) {
        let state = EqualizerTapState(parameters: parameters)
        let clientInfo = Unmanaged.passRetained(state).toOpaque()

        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: clientInfo,
            init: equalizerTapInit,
            finalize: equalizerTapFinalize,
            prepare: equalizerTapPrepare,
            unprepare: equalizerTapUnprepare,
            process: equalizerTapProcess
        )

        var unmanagedTap: Unmanaged<MTAudioProcessingTap>?
        let status = MTAudioProcessingTapCreate(
            kCFAllocatorDefault,
            &callbacks,
            kMTAudioProcessingTapCreationFlag_PostEffects,
            &unmanagedTap
        )

        guard status == noErr, let unmanagedTap else {
            Unmanaged<EqualizerTapState>.fromOpaque(clientInfo).release()
            return
        }

        let tap = unmanagedTap.takeRetainedValue()
        let input = AVMutableAudioMixInputParameters(track: track)
        input.audioTapProcessor = tap

        let mix = AVMutableAudioMix()
        mix.inputParameters = [input]
        item.audioMix = mix
    }
}

private func equalizerTapInit(
    _ tap: MTAudioProcessingTap,
    _ clientInfo: UnsafeMutableRawPointer?,
    _ tapStorageOut: UnsafeMutablePointer<UnsafeMutableRawPointer?>
) {
    tapStorageOut.pointee = clientInfo
}

private func equalizerTapFinalize(_ tap: MTAudioProcessingTap) {
    let storage = MTAudioProcessingTapGetStorage(tap)
    Unmanaged<EqualizerTapState>.fromOpaque(storage).release()
}

private func equalizerTapPrepare(
    _ tap: MTAudioProcessingTap,
    _ maxFrames: CMItemCount,
    _ processingFormat: UnsafePointer<AudioStreamBasicDescription>
) {
    let storage = MTAudioProcessingTapGetStorage(tap)
    let state = Unmanaged<EqualizerTapState>.fromOpaque(storage).takeUnretainedValue()
    state.prepare(format: processingFormat.pointee)
}

private func equalizerTapUnprepare(_ tap: MTAudioProcessingTap) {
    let storage = MTAudioProcessingTapGetStorage(tap)
    let state = Unmanaged<EqualizerTapState>.fromOpaque(storage).takeUnretainedValue()
    state.reset()
}

private func equalizerTapProcess(
    _ tap: MTAudioProcessingTap,
    _ numberFrames: CMItemCount,
    _ flags: MTAudioProcessingTapFlags,
    _ bufferListInOut: UnsafeMutablePointer<AudioBufferList>,
    _ numberFramesOut: UnsafeMutablePointer<CMItemCount>,
    _ flagsOut: UnsafeMutablePointer<MTAudioProcessingTapFlags>
) {
    let status = MTAudioProcessingTapGetSourceAudio(
        tap,
        numberFrames,
        bufferListInOut,
        flagsOut,
        nil,
        numberFramesOut
    )

    guard status == noErr, numberFramesOut.pointee > 0 else { return }

    let storage = MTAudioProcessingTapGetStorage(tap)
    let state = Unmanaged<EqualizerTapState>.fromOpaque(storage).takeUnretainedValue()
    state.process(bufferList: bufferListInOut, frames: Int(numberFramesOut.pointee))
}

private final class EqualizerTapState {
    private let parameters: EqualizerParameters
    private var sampleRate: Double = 44_100
    private var channelCount = 2
    private var isFloatFormat = true
    private var isNonInterleaved = true
    private var filters: [ChannelFilters] = []
    private var appliedGains: EqualizerGains?

    init(parameters: EqualizerParameters) {
        self.parameters = parameters
    }

    func prepare(format: AudioStreamBasicDescription) {
        sampleRate = format.mSampleRate > 0 ? format.mSampleRate : 44_100
        channelCount = max(1, Int(format.mChannelsPerFrame))
        isFloatFormat = (format.mFormatFlags & kAudioFormatFlagIsFloat) != 0
            && format.mBitsPerChannel == 32
        isNonInterleaved = (format.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0

        filters = Array(repeating: ChannelFilters(), count: channelCount)
        appliedGains = nil
        apply(parameters.snapshot())
    }

    func reset() {
        filters = []
        appliedGains = nil
    }

    func process(bufferList: UnsafeMutablePointer<AudioBufferList>, frames: Int) {
        let gains = parameters.snapshot()
        guard gains.enabled, gains.isNonFlat, isFloatFormat, frames > 0 else { return }

        if appliedGains != gains {
            apply(gains)
        }

        guard !filters.isEmpty else { return }

        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        for bufferIndex in 0..<buffers.count {
            let buffer = buffers[bufferIndex]
            guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }

            let channelsInBuffer = max(1, Int(buffer.mNumberChannels))
            let sampleCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            guard sampleCount > 0 else { continue }

            if isNonInterleaved || channelsInBuffer == 1 {
                guard filters.indices.contains(bufferIndex) else { continue }
                let count = min(frames, sampleCount)
                var channelFilters = filters[bufferIndex]

                for frame in 0..<count {
                    var sample = data[frame]
                    sample = channelFilters.bass.process(sample)
                    sample = channelFilters.mid.process(sample)
                    sample = channelFilters.treble.process(sample)
                    data[frame] = sample
                }

                filters[bufferIndex] = channelFilters
            } else {
                let frameCount = min(frames, sampleCount / channelsInBuffer)
                for frame in 0..<frameCount {
                    let base = frame * channelsInBuffer
                    for channel in 0..<channelsInBuffer {
                        let filterIndex = min(channel, filters.count - 1)
                        let index = base + channel
                        var sample = data[index]
                        sample = filters[filterIndex].bass.process(sample)
                        sample = filters[filterIndex].mid.process(sample)
                        sample = filters[filterIndex].treble.process(sample)
                        data[index] = sample
                    }
                }
            }
        }
    }

    private func apply(_ gains: EqualizerGains) {
        appliedGains = gains

        guard !filters.isEmpty else { return }

        for index in filters.indices {
            var channel = filters[index]
            channel.bass.setLowShelf(
                sampleRate: sampleRate,
                frequency: 90,
                gainDB: gains.bass
            )
            channel.mid.setPeaking(
                sampleRate: sampleRate,
                frequency: 1_000,
                gainDB: gains.mid,
                q: 1.0
            )
            channel.treble.setHighShelf(
                sampleRate: sampleRate,
                frequency: 9_000,
                gainDB: gains.treble
            )
            filters[index] = channel
        }
    }
}

private struct ChannelFilters {
    var bass = Biquad()
    var mid = Biquad()
    var treble = Biquad()
}

private struct Biquad {
    private var b0 = 1.0
    private var b1 = 0.0
    private var b2 = 0.0
    private var a1 = 0.0
    private var a2 = 0.0
    private var z1 = 0.0
    private var z2 = 0.0

    mutating func process(_ input: Float) -> Float {
        let x = Double(input)
        let y = b0 * x + z1
        z1 = b1 * x - a1 * y + z2
        z2 = b2 * x - a2 * y
        return Float(y)
    }

    mutating func setLowShelf(sampleRate: Double, frequency: Double, gainDB: Float) {
        let gain = Double(gainDB)
        let a = pow(10, gain / 40)
        let w0 = 2 * .pi * frequency / sampleRate
        let cosine = cos(w0)
        let sine = sin(w0)
        let slope = 1.0
        let alpha = sine / 2 * sqrt((a + 1 / a) * (1 / slope - 1) + 2)
        let beta = 2 * sqrt(a) * alpha

        let b0 = a * ((a + 1) - (a - 1) * cosine + beta)
        let b1 = 2 * a * ((a - 1) - (a + 1) * cosine)
        let b2 = a * ((a + 1) - (a - 1) * cosine - beta)
        let a0 = (a + 1) + (a - 1) * cosine + beta
        let a1 = -2 * ((a - 1) + (a + 1) * cosine)
        let a2 = (a + 1) + (a - 1) * cosine - beta

        set(b0: b0, b1: b1, b2: b2, a0: a0, a1: a1, a2: a2)
    }

    mutating func setPeaking(
        sampleRate: Double,
        frequency: Double,
        gainDB: Float,
        q: Double
    ) {
        let gain = Double(gainDB)
        let a = pow(10, gain / 40)
        let w0 = 2 * .pi * frequency / sampleRate
        let cosine = cos(w0)
        let sine = sin(w0)
        let alpha = sine / (2 * q)

        let b0 = 1 + alpha * a
        let b1 = -2 * cosine
        let b2 = 1 - alpha * a
        let a0 = 1 + alpha / a
        let a1 = -2 * cosine
        let a2 = 1 - alpha / a

        set(b0: b0, b1: b1, b2: b2, a0: a0, a1: a1, a2: a2)
    }

    mutating func setHighShelf(sampleRate: Double, frequency: Double, gainDB: Float) {
        let gain = Double(gainDB)
        let a = pow(10, gain / 40)
        let w0 = 2 * .pi * frequency / sampleRate
        let cosine = cos(w0)
        let sine = sin(w0)
        let slope = 1.0
        let alpha = sine / 2 * sqrt((a + 1 / a) * (1 / slope - 1) + 2)
        let beta = 2 * sqrt(a) * alpha

        let b0 = a * ((a + 1) + (a - 1) * cosine + beta)
        let b1 = -2 * a * ((a - 1) + (a + 1) * cosine)
        let b2 = a * ((a + 1) + (a - 1) * cosine - beta)
        let a0 = (a + 1) - (a - 1) * cosine + beta
        let a1 = 2 * ((a - 1) - (a + 1) * cosine)
        let a2 = (a + 1) - (a - 1) * cosine - beta

        set(b0: b0, b1: b1, b2: b2, a0: a0, a1: a1, a2: a2)
    }

    private mutating func set(
        b0: Double,
        b1: Double,
        b2: Double,
        a0: Double,
        a1: Double,
        a2: Double
    ) {
        self.b0 = b0 / a0
        self.b1 = b1 / a0
        self.b2 = b2 / a0
        self.a1 = a1 / a0
        self.a2 = a2 / a0
        z1 = 0
        z2 = 0
    }
}
