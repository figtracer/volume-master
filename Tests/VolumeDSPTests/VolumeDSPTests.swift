import Foundation
import VolumeDSP

final class VolumeDSPTests {
    private func render(_ processor: OpaquePointer, _ left: [Float], _ right: [Float]? = nil) -> ([Float], [Float]) {
        var a = [Float](repeating: 0, count: left.count)
        var b = a
        let right = right ?? left
        left.withUnsafeBufferPointer { l in
            right.withUnsafeBufferPointer { r in
                a.withUnsafeMutableBufferPointer { ol in
                    b.withUnsafeMutableBufferPointer { or in
                        vm_process(processor, l.baseAddress!, r.baseAddress!, ol.baseAddress!, or.baseAddress!, UInt32(left.count))
                    }
                }
            }
        }
        return (a, b)
    }

    private func controls(_ dsp: OpaquePointer, volume: Float = 1, bass: Float = 0, bands: [Float] = [0,0,0,0,0]) {
        bands.withUnsafeBufferPointer { vm_set_controls(dsp, volume, bass, $0.baseAddress!) }
    }

    func testUnityAnd150PercentGainAfterLookahead() throws {
        let dsp = try unwrap(vm_create(48000))
        defer { vm_destroy(dsp) }
        _ = render(dsp, [Float](repeating: 0, count: 48000))
        let input = (0..<4800).map { Float(sin(Double($0) * 0.14)) * 0.1 }
        let (output, _) = render(dsp, input)
        let latency = Int(vm_latency(dsp))
        expectEqual(latency, 240)
        for i in latency..<input.count { expectEqual(output[i], input[i-latency], accuracy: 0.00001) }
        controls(dsp, volume: 1.5)
        _ = render(dsp, [Float](repeating: 0, count: 48000))
        let (boosted, _) = render(dsp, input)
        for i in latency..<input.count { expectEqual(boosted[i], input[i-latency]*1.5, accuracy: 0.00002) }
    }

    func testLimiterContainsTransientsWithMaximumEQAtAllRates() throws {
        for rate in [22050.0, 44100, 48000, 96000, 192000] {
            let dsp = try unwrap(vm_create(rate))
            defer { vm_destroy(dsp) }
            controls(dsp, volume: 1.5, bass: 9, bands: [9,9,9,9,9])
            var seed: UInt64 = 42
            var input = (0..<Int(rate)).map { index -> Float in
                seed = seed &* 6364136223846793005 &+ 1
                let noise = Float(Double(seed >> 32) / Double(UInt32.max) * 2 - 1)
                return index % 2000 == 0 ? 12 : noise
            }
            input += [Float](repeating: 0, count: Int(vm_latency(dsp)) + 100)
            let (left, right) = render(dsp, input, input.map { $0 * -0.5 })
            for i in left.indices {
                expect(left[i].isFinite && right[i].isFinite)
                expectAtMost(abs(left[i]), 0.8912511)
                expectAtMost(abs(right[i]), 0.8912511)
                expectEqual(right[i], -0.5*left[i], accuracy: 0.000001, "Stereo image must remain linked")
            }
        }
    }

    func testBassShelfAndEqualizerHaveAudibleFrequencyResponse() throws {
        func amplitude(frequency: Double, bass: Float, bands: [Float]) throws -> Double {
            let dsp = try unwrap(vm_create(48000))
            defer { vm_destroy(dsp) }
            controls(dsp, bass: bass, bands: bands)
            let input = (0..<48000).map { Float(sin(2 * .pi * frequency * Double($0) / 48000) * 0.01) }
            let (output, _) = render(dsp, input)
            return sqrt(output.suffix(24000).reduce(0) { $0 + Double($1 * $1) } / 24000)
        }
        let flat: [Float] = [0,0,0,0,0]
        let bassGain = try amplitude(frequency: 30, bass: 6, bands: flat) / amplitude(frequency: 30, bass: 0, bands: flat)
        expectEqual(20 * log10(bassGain), 6, accuracy: 0.15)
        let highGain = try amplitude(frequency: 8000, bass: 6, bands: flat) / amplitude(frequency: 8000, bass: 0, bands: flat)
        expectEqual(highGain, 1, accuracy: 0.01)
        let midGain = try amplitude(frequency: 1000, bass: 0, bands: [0,0,6,0,0]) / amplitude(frequency: 1000, bass: 0, bands: flat)
        expectEqual(20 * log10(midGain), 6, accuracy: 0.05)
    }

    func testMuteRampsToSilenceAndNonfiniteInputCannotPoisonFilters() throws {
        let dsp = try unwrap(vm_create(48000))
        defer { vm_destroy(dsp) }
        _ = render(dsp, [Float](repeating: 0.2, count: 48000))
        controls(dsp, volume: 0)
        let (output, _) = render(dsp, [Float](repeating: 0.2, count: 48000))
        expectBelow(abs(output.last!), 0.000001)
        for index in 1..<output.count { expectBelow(abs(output[index]-output[index-1]), 0.001) }
        controls(dsp)
        let (clean, _) = render(dsp, [.nan, .infinity, -.infinity] + [Float](repeating: 0.1, count: 48000))
        expect(clean.allSatisfy(\.isFinite))
        expectEqual(clean.last!, 0.1, accuracy: 0.0001)
    }

    func testControlChangesAndBlockBoundariesRemainBounded() throws {
        let dsp = try unwrap(vm_create(48000))
        defer { vm_destroy(dsp) }
        for block in 0..<200 {
            controls(dsp, volume: block.isMultiple(of: 2) ? 1.5 : 0.3,
                     bass: block.isMultiple(of: 3) ? 9 : 0,
                     bands: [Float](repeating: block.isMultiple(of: 2) ? 9 : -9, count: 5))
            let input = (0..<257).map { Float(sin(Double(block * 257 + $0) * 0.07)) }
            let (output, _) = render(dsp, input)
            expect(output.allSatisfy { $0.isFinite && abs($0) <= 0.8912511 })
        }
        expectEqual(vm_frames(dsp), 200 * 257)
        expectNil(vm_create(0))
        expectNil(vm_create(.nan))
    }
}


private struct CheckFailure: Error { let message: String }
private func unwrap<T>(_ value: T?) throws -> T {
    guard let value else { throw CheckFailure(message: "Unexpected nil") }
    return value
}
private func expect(_ condition: @autoclosure () -> Bool, file: StaticString = #filePath, line: UInt = #line) {
    guard condition() else { fatalError("Check failed at \(file):\(line)") }
}
private func expectEqual<T: Equatable>(_ a: T, _ b: T) { expect(a == b) }
private func expectEqual<T: BinaryFloatingPoint>(_ a: T, _ b: T, accuracy: T, _ message: String = "") { expect(abs(a - b) <= accuracy) }
private func expectAtMost<T: Comparable>(_ a: T, _ b: T) { expect(a <= b) }
private func expectBelow<T: Comparable>(_ a: T, _ b: T) { expect(a < b) }
private func expectNil<T>(_ value: T?) { expect(value == nil) }

@main
enum VolumeCheck {
    static func main() throws {
        let suite = VolumeDSPTests()
        try suite.testUnityAnd150PercentGainAfterLookahead()
        print("PASS unity, 150% gain, and 5 ms latency")
        try suite.testLimiterContainsTransientsWithMaximumEQAtAllRates()
        print("PASS limiter ceiling and stereo linkage at five sample rates")
        try suite.testBassShelfAndEqualizerHaveAudibleFrequencyResponse()
        print("PASS measured bass shelf and EQ frequency response")
        try suite.testMuteRampsToSilenceAndNonfiniteInputCannotPoisonFilters()
        print("PASS mute ramp and nonfinite input recovery")
        try suite.testControlChangesAndBlockBoundariesRemainBounded()
        print("PASS changing controls, block boundaries, and sample-rate validation")
    }
}
