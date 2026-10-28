import AVFoundation

// Keeps the microphone running and saves speech to a file only while a dictation is being recorded.
//
// While "listening" but not recording, audio is measured for the level meter and then thrown away, apart
// from the last 0.3 seconds, which is kept so the first word isn't clipped when a dictation starts.
// Nothing is stored or sent anywhere unless a recording was started.
//
// Runs on the audio thread, so everything here is thread-safe and independent of the UI.
nonisolated final class AudioCapture: @unchecked Sendable {
    enum CaptureError: Error {
        case noInput
    }

    // Whisper wants 16 kHz mono, so audio is converted to that as it arrives.
    static let sampleRate = 16_000.0

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!

    private var converter: AVAudioConverter?
    private var file: AVAudioFile?
    private var framesWritten: Int64 = 0
    private var preRoll: [AVAudioPCMBuffer] = []
    private var preRollFrames = 0
    private var smoothedLevel: Float = 0

    private let preRollLimit = 4_800

    // MARK: State

    var isRunning: Bool { engine.isRunning }
    var isRecording: Bool { lock.withLock { file != nil } }

    // 0...1, shaped like the level meter the UI and keyboard draw.
    var level: Float { lock.withLock { smoothedLevel } }

    var recordedSeconds: Double { lock.withLock { Double(framesWritten) / Self.sampleRate } }

    // MARK: Running the microphone

    // Starts listening. The audio session must already be configured and active.
    func start() throws {
        guard !engine.isRunning else { return }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        try configure(inputFormat: format)

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.feed(buffer)
        }
        engine.prepare()
        try engine.start()
    }

    // Restarts after a route change, for example headphones connecting.
    func restart() throws {
        stopEngine()
        try start()
    }

    func stop() {
        stopEngine()
        lock.withLock {
            file = nil
            preRoll.removeAll()
            preRollFrames = 0
            smoothedLevel = 0
        }
    }

    private func stopEngine() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    // Prepares the converter for audio arriving in `inputFormat`. Also used directly by tests.
    func configure(inputFormat: AVAudioFormat) throws {
        guard inputFormat.sampleRate > 0, let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw CaptureError.noInput
        }
        lock.withLock { self.converter = converter }
    }

    // MARK: Recording on demand

    // Starts saving to `url`, beginning with the last few tenths of a second already heard.
    func beginRecording(to url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        let newFile = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: Self.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false
        ])

        try lock.withLock {
            framesWritten = 0
            for buffer in preRoll {
                try newFile.write(from: buffer)
                framesWritten += Int64(buffer.frameLength)
            }
            preRoll.removeAll()
            preRollFrames = 0
            file = newFile
        }
    }

    // Stops saving and closes the file.
    func endRecording() {
        lock.withLock { file = nil }
    }

    // MARK: Audio path

    // Called for every buffer from the microphone.
    func feed(_ input: AVAudioPCMBuffer) {
        guard let converter = lock.withLock({ self.converter }) else { return }

        let ratio = targetFormat.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return input
        }
        guard status != .error, output.frameLength > 0, let samples = output.floatChannelData?[0] else { return }

        var sum: Float = 0
        let count = Int(output.frameLength)
        for index in 0..<count { sum += samples[index] * samples[index] }
        let rms = (sum / Float(count)).squareRoot()
        // Same shaping as the old recorder meter: -40 dB and below is silence, 0 dB is full scale.
        let decibels = 20 * log10(max(rms, 1e-7))
        let normalised = max(0, min(1, (decibels + 40) / 40))
        let level = powf(normalised, 1.3)

        lock.withLock {
            smoothedLevel = level > smoothedLevel ? level : smoothedLevel * 0.6 + level * 0.4

            if let file {
                try? file.write(from: output)
                framesWritten += Int64(output.frameLength)
            } else {
                preRoll.append(output)
                preRollFrames += count
                while preRollFrames > preRollLimit, preRoll.count > 1 {
                    preRollFrames -= Int(preRoll.removeFirst().frameLength)
                }
            }
        }
    }
}
