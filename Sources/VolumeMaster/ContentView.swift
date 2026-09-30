import SwiftUI

enum Palette {
    static let canvas = Color(red: 11/255, green: 13/255, blue: 18/255)
    static let surface = Color(red: 21/255, green: 25/255, blue: 34/255)
    static let border = Color(red: 42/255, green: 48/255, blue: 59/255)
    static let secondary = Color(red: 146/255, green: 155/255, blue: 170/255)
    static let aqua = Color(red: 114/255, green: 220/255, blue: 207/255)
    static let amber = Color(red: 237/255, green: 183/255, blue: 86/255)
}

struct ContentView: View {
    @ObservedObject var model: AppModel
    private let frequencies = ["60", "250", "1k", "4k", "12k"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "waveform")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Palette.aqua)
                    .frame(width: 32, height: 32)
                Text("volume master").font(.system(size: 15, weight: .semibold))
                Spacer()
                Button(action: model.toggle) {
                    Image(systemName: "power").font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(model.enabled ? Palette.canvas : Palette.secondary)
                        .frame(width: 32, height: 32)
                        .background(model.enabled ? Palette.aqua : Palette.surface, in: Circle())
                        .overlay(Circle().stroke(Palette.border, lineWidth: model.enabled ? 0 : 1))
                }
                .buttonStyle(.plain).disabled(model.busy)
                .accessibilityLabel(model.enabled ? "Disable audio processing" : "Enable audio processing")
                .help(model.enabled ? "Restore original system audio" : "Enable system audio processing")
                .keyboardShortcut("e", modifiers: .command)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    label("MASTER VOLUME")
                    Spacer()
                    Text(model.volume > 100 ? String(format: "+%.1f dB", 20 * log10(model.volume / 100)) : "\(Int(model.volume))% gain")
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.secondary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(Int(model.volume))").font(.system(size: 48, weight: .light, design: .rounded)).monospacedDigit()
                    Text("%").font(.system(size: 25, weight: .light)).foregroundStyle(Palette.secondary)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 7) {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.shield.fill")
                            Text("PEAK GUARD")
                        }.font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(Palette.aqua)
                        Text(model.reduction > 0.1 ? String(format: "−%.1f dB limiting", model.reduction) : "−1 dB ceiling")
                            .font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.secondary)
                    }
                }
                Slider(value: Binding(get: { model.volume }, set: { model.volume = $0.rounded() }), in: 0...150)
                    .accessibilityLabel("Master volume").accessibilityValue("\(Int(model.volume)) percent")
                HStack {
                    Text("0%")
                    Spacer()
                    Button("100%") { model.volume = 100 }.buttonStyle(.plain).help("Reset volume to unity gain")
                    Spacer().frame(width: 58)
                    Text("150%")
                }.font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.secondary)
            }.padding(16).panel()

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    label("EQUALIZER")
                    Spacer()
                    ForEach(["Flat", "Warm", "Voice"], id: \.self) { preset in
                        Button(preset) { model.preset(preset) }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .foregroundStyle(model.presetName == preset ? Palette.aqua : Palette.secondary)
                            .background(model.presetName == preset ? Palette.aqua.opacity(0.10) : Color.clear, in: Capsule())
                            .accessibilityAddTraits(model.presetName == preset ? .isSelected : [])
                    }
                }
                HStack(alignment: .top, spacing: 0) {
                    ForEach(0..<5) { index in
                        VStack(spacing: 9) {
                            Text(String(format: "%+.0f", model.bands[index]))
                                .font(.system(size: 11, design: .monospaced)).monospacedDigit()
                                .foregroundStyle(model.bands[index] == 0 ? Palette.secondary : Palette.aqua)
                            VerticalFader(value: $model.bands[index], label: "\(frequencies[index]) hertz")
                                .frame(width: 40, height: 74)
                            Text(frequencies[index]).font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.secondary)
                        }.frame(maxWidth: .infinity)
                    }
                }
                Rectangle().fill(Palette.border).frame(height: 1)
                HStack(spacing: 8) {
                    Image(systemName: "speaker.wave.2").foregroundStyle(Palette.aqua)
                    Text("Bass boost").font(.system(size: 12))
                    Slider(value: Binding(get: { model.bass }, set: { model.bass = ($0 * 2).rounded() / 2 }), in: 0...9)
                        .accessibilityLabel("Bass boost")
                    Text(String(format: "+%.1f", model.bass))
                        .font(.system(size: 11, design: .monospaced)).monospacedDigit()
                        .foregroundStyle(Palette.aqua).frame(width: 35, alignment: .trailing)
                    Text("dB").font(.system(size: 10)).foregroundStyle(Palette.secondary)
                }
            }.padding(16).panel()

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "hifispeaker.fill").foregroundStyle(Palette.secondary)
                    Text(model.output).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!)
                    } label: { Image(systemName: "arrow.up.right").font(.system(size: 10)) }
                    .buttonStyle(.plain).foregroundStyle(Palette.secondary).help("Open Sound settings")
                    .accessibilityLabel("Open Sound settings")
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.border)
                        Capsule().fill(model.reduction > 0.5 ? Palette.amber : Palette.aqua)
                            .frame(width: max(0, geo.size.width * CGFloat(meterLevel)))
                    }
                }.frame(height: 3).accessibilityLabel("Output level").accessibilityValue("\(Int(meterLevel * 100)) percent")
                HStack(spacing: 6) {
                    Circle().fill(model.enabled ? Palette.aqua : Palette.secondary).frame(width: 5, height: 5)
                    Text(model.status).font(.system(size: 10))
                    Spacer()
                    if model.enabled {
                        Text(String(format: "%.1f kHz", model.sampleRate / 1000)).font(.system(size: 10, design: .monospaced))
                    }
                }.foregroundStyle(Palette.secondary)
            }.padding(.horizontal, 2)

            if let error = model.error {
                VStack(alignment: .leading, spacing: 8) {
                    Text(error).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Try again", action: model.start)
                        Button("Audio permission settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                        }
                    }.font(.system(size: 10))
                }.foregroundStyle(Palette.amber).padding(12).panel()
            }

            HStack {
                Button("Reset sound") { model.reset() }.buttonStyle(.plain)
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.plain).keyboardShortcut("q")
            }.font(.system(size: 9, design: .monospaced)).foregroundStyle(Palette.secondary.opacity(0.8))
        }
        .padding(18)
        .frame(width: 350)
        .background(Palette.canvas)
        .foregroundStyle(Color(red: 242/255, green: 244/255, blue: 247/255))
        .tint(Palette.aqua)
        .preferredColorScheme(.dark)
    }

    private var meterLevel: Double {
        guard model.peak > 0 else { return 0 }
        return min(1, max(0, (20 * log10(Double(model.peak)) + 60) / 60))
    }

    private func label(_ title: String) -> some View {
        Text(title).font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.3).foregroundStyle(Palette.secondary)
    }
}

private struct VerticalFader: View {
    @Binding var value: Double
    @FocusState private var focused: Bool
    let label: String
    var body: some View {
        GeometryReader { geo in
            let travel = geo.size.height - 14
            let position = CGFloat((9 - value) / 18) * travel + 7
            ZStack {
                Capsule().fill(Palette.border).frame(width: 3)
                Rectangle().fill(Palette.secondary.opacity(0.4)).frame(width: 16, height: 1)
                Capsule().fill(Palette.aqua.opacity(0.45))
                    .frame(width: 3, height: abs(position - geo.size.height / 2))
                    .position(x: geo.size.width / 2, y: (position + geo.size.height / 2) / 2)
                RoundedRectangle(cornerRadius: 4).fill(Palette.aqua)
                    .frame(width: 24, height: 12)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(.white.opacity(focused ? 0.7 : 0), lineWidth: 1))
                    .overlay(RoundedRectangle(cornerRadius: 1).fill(Palette.canvas.opacity(0.35)).frame(width: 12, height: 1))
                    .position(x: geo.size.width / 2, y: position)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { event in
                value = min(9, max(-9, (9 - Double((event.location.y - 7) / travel) * 18).rounded()))
            })
            .onTapGesture(count: 2) { value = 0 }
            .accessibilityElement().accessibilityLabel(label)
            .accessibilityValue(String(format: "%+.0f decibels", value))
            .accessibilityAdjustableAction { direction in
                if direction == .increment { value = min(9, value + 1) }
                else if direction == .decrement { value = max(-9, value - 1) }
            }
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onKeyPress(.upArrow) { value = min(9, value + 1); return .handled }
            .onKeyPress(.downArrow) { value = max(-9, value - 1); return .handled }
            .help("\(label) · ±9 dB · Double-click to reset")
        }
    }
}

private extension View {
    func panel() -> some View {
        background(Palette.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.border.opacity(0.7), lineWidth: 1))
    }
}
