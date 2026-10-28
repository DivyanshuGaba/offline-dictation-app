import Foundation

// Pure synthesis with no audio APIs, so the same sounds can also be rendered on a Mac to audition them.
// Each cue is two soft glass-like taps a fifth apart: rising to begin, falling to finish.
enum CueTones {
    enum Kind { case start, end }

    private struct Note {
        let frequency: Double
        let start: Double
        let decay: Double
    }

    static func wav(for kind: Kind) -> Data {
        let notes: [Note]
        switch kind {
        case .start: notes = [Note(frequency: 784, start: 0, decay: 0.060), Note(frequency: 1175, start: 0.085, decay: 0.085)]
        case .end: notes = [Note(frequency: 1175, start: 0, decay: 0.060), Note(frequency: 784, start: 0.085, decay: 0.105)]
        }

        let sampleRate = 44_100.0
        let count = Int(0.7 * sampleRate)
        var mix = [Double](repeating: 0, count: count)

        // Bell-like partials: the upper ones are quieter and die away faster, which keeps it soft, never harsh.
        let partials: [(ratio: Double, amplitude: Double, decayScale: Double)] = [(1, 1, 1), (2.756, 0.16, 0.55), (5.404, 0.05, 0.30)]

        for note in notes {
            let startIndex = Int(note.start * sampleRate)
            for index in startIndex..<count {
                let t = Double(index - startIndex) / sampleRate
                if t > note.decay * 9 { break }
                let attack = min(1, t / 0.004)
                var value = 0.0
                for partial in partials {
                    value += partial.amplitude
                        * sin(2 * Double.pi * note.frequency * partial.ratio * t)
                        * exp(-t / (note.decay * partial.decayScale))
                }
                mix[index] += value * attack
            }
        }

        let peak = max(mix.map { abs($0) }.max() ?? 1, 0.0001)
        let fade = Int(0.03 * sampleRate)
        var samples = [Int16]()
        samples.reserveCapacity(count)
        for index in 0..<count {
            var value = mix[index] / peak * 0.6
            if index > count - fade { value *= Double(count - index) / Double(fade) }
            samples.append(Int16(clamping: Int((value * 32767).rounded())))
        }
        return wavData(samples, sampleRate: Int(sampleRate))
    }

    private static func wavData(_ samples: [Int16], sampleRate: Int) -> Data {
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        let byteCount = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36) + byteCount)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(sampleRate)); append(UInt32(sampleRate) * 2); append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(byteCount)
        for sample in samples { append(sample) }
        return data
    }
}
