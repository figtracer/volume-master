import AppKit
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var volume = 100.0 { didSet { save() } }
    @Published var bass = 0.0 { didSet { save() } }
    @Published var bands = [Double](repeating: 0, count: 5) { didSet { save() } }
    @Published private(set) var enabled = false
    @Published private(set) var busy = false
    @Published private(set) var output = AudioRoute.outputName()
    @Published private(set) var status = "Ready when you are"
    @Published private(set) var error: String?
    @Published private(set) var peak: Float = 0
    @Published private(set) var reduction: Float = 0
    @Published private(set) var sampleRate: Double = 0
    private let route = AudioRoute()
    private var timer: Timer?
    private var observations: [NSObjectProtocol] = []
    private var tick = 0
    private var sleeping = false
    private var lastFrames: UInt64 = 0
    private var stagnantTicks = 0

    init() {
        if let data = UserDefaults.standard.data(forKey: "sound.v1"),
           let settings = try? JSONDecoder().decode(Settings.self, from: data) {
            volume = Self.clamp(settings.volume, 0...150, fallback: 100)
            bass = Self.clamp(settings.bass, 0...9, fallback: 0)
            if settings.bands.count == 5 { bands = settings.bands.map { Self.clamp($0, -9...9, fallback: 0) } }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        let center = NSWorkspace.shared.notificationCenter
        observations.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.sleeping = true
                self?.route.stop()
                self?.status = "Paused while your Mac sleeps"
            }
        })
        observations.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.sleeping = false
                if self?.enabled == true { self?.start() }
            }
        })
        observations.append(NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.route.stop() }
        })
    }

    func toggle() {
        guard !busy else { return }
        if enabled {
            route.stop()
            enabled = false
            peak = 0
            reduction = 0
            status = "Original system audio"
            error = nil
        } else { start() }
    }

    func start() {
        busy = true
        error = nil
        defer { busy = false }
        do {
            try route.start(volume: volume, bass: bass, bands: bands)
            enabled = true
            output = route.name
            sampleRate = route.sampleRate
            status = "Listening for audio"
            lastFrames = 0
            stagnantTicks = 0
        } catch {
            enabled = false
            peak = 0
            reduction = 0
            self.error = error.localizedDescription
            status = "Audio processing is off"
        }
    }

    func preset(_ name: String) {
        switch name {
        case "Warm": bands = [2, 1, 0, -1, -2]; bass = 3
        case "Voice": bands = [-3, -1, 2, 3, 0]; bass = 0
        default: bands = [0, 0, 0, 0, 0]; bass = 0
        }
    }

    var presetName: String {
        if bands == [0, 0, 0, 0, 0] && bass == 0 { return "Flat" }
        if bands == [2, 1, 0, -1, -2] && bass == 3 { return "Warm" }
        if bands == [-3, -1, 2, 3, 0] && bass == 0 { return "Voice" }
        return "Custom"
    }

    func reset() { volume = 100; preset("Flat") }

    private func save() {
        route.update(volume: volume, bass: bass, bands: bands)
        if let data = try? JSONEncoder().encode(Settings(volume: volume, bass: bass, bands: bands)) {
            UserDefaults.standard.set(data, forKey: "sound.v1")
        }
    }

    private func refresh() {
        guard !sleeping else { return }
        tick += 1
        if enabled {
            peak = max(route.peak, peak * 0.86)
            reduction = max(route.reduction, reduction * 0.90)
            if route.faults > 0 {
                toggle()
                error = "The output’s audio layout changed. Audio processing was stopped; try enabling it again."
                return
            }
            if tick % 10 == 0 {
                if route.routeChanged() { start(); return }
                let frames = route.frames
                stagnantTicks = frames == lastFrames ? stagnantTicks + 1 : 0
                lastFrames = frames
                // A stalled IO callback must not leave tapped processes muted indefinitely.
                if stagnantTicks >= 6 {
                    toggle()
                    error = "Audio stopped responding. Check system audio permission, then try again."
                    return
                }
                status = peak > 0.0001 ? "Processing system audio" : "Listening for audio"
            }
        } else if tick % 20 == 0 { output = AudioRoute.outputName() }
    }

    private struct Settings: Codable {
        let volume: Double
        let bass: Double
        let bands: [Double]
    }

    private static func clamp(_ value: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double {
        value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
    }
}
