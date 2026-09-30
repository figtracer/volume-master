# Volume Master

A small native macOS menu-bar app for a little more volume, a warmer low end, and a simple EQ. Click the speaker icon for a compact popup with every control. No separate window or Dock icon.

SwiftUI interface inspired by [stacksampler](https://github.com/figtracer/stacksampler). Swift + C audio engine. No third-party dependencies, virtual audio driver, account, or network access.

## Sound controls

- **0–150% master volume** — 150% is 1.5× linear amplitude, about +3.52 dB; it is not 50% more perceived loudness.
- **Five-band EQ** — 60 Hz, 250 Hz, 1 kHz, 4 kHz, and 12 kHz, each ±9 dB.
- **Bass boost** — a 100 Hz low shelf, up to +9 dB.
- **Flat, Warm, and Voice presets**, plus saved custom settings.
- **Peak Guard** — an always-on, stereo-linked lookahead limiter after the tone controls and gain. It caps digital samples at −1 dBFS, with 5 ms lookahead and an 80 ms release.
- **Menu-bar popup**, live output meter, and gain-reduction readout.

The limiter reduces gain when needed, so loud recordings may not become much louder at 150%. It prevents sample clipping in the app’s output; it cannot repair distorted recordings or guarantee that a DAC, headphones, or speakers will never distort. This is a sample-peak limiter, not an oversampled true-peak limiter. Device and Bluetooth latency are additional to the 5 ms DSP lookahead.

## Requirements and use

macOS 14.2 or newer, with a mono or stereo default output at 22.05–192 kHz. The supplied local build is for Apple silicon. Intel builds can be compiled with `ARCH=x86_64` but have not been hardware-tested.

1. Open **Volume Master.app**.
2. Click its speaker icon in the menu bar, press the power button, and grant macOS system-audio access when prompted. If needed, use **System Settings → Privacy & Security → Screen & System Audio Recording** and reopen the app.
3. Play audio in another app. Adjust the volume, EQ, and bass.

Processing starts **off** on each launch. Tone and volume preferences are saved. The app follows the default macOS output; use the output arrow to open Sound settings. It does not change the hardware volume, default device, or sample rate. Dismissing the popup keeps processing active. Power off or quit to restore original system audio.

Audio is processed locally and is never saved or sent over a network. The engine captures the first output stream of the current default device using Apple’s [Core Audio process taps](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps). The private tap excludes Volume Master and mutes the original stream only while being read. A private aggregate routes the result to the same device. Physical microphone inputs are disabled for this IO callback. Tap and aggregate resources are destroyed on stop, failure, and normal quit; macOS owns their lifetime if the process exits unexpectedly.

Audio routed by another app to a different device is outside this tap. Separate system-alert outputs, protected content, multichannel devices, and exclusive-device applications are not guaranteed to work. Device disconnects and sample-rate changes trigger a route rebuild; unsupported layouts stop processing with an error instead of guessing a channel map. Sleep pauses processing and wake attempts to reconnect.

## Build

Install Apple’s Command Line Tools (`xcode-select --install`) or Xcode. There are no package dependencies.

```sh
bash scripts/check.sh
bash scripts/package.sh
open "dist/Volume Master.app"
```

The package script produces an app bundle, ZIP, and SHA-256 checksum in `dist/`. It uses ad-hoc signing by default. Set `SIGNING_IDENTITY` to use your own signing identity. **These development builds are not notarized**; public distribution needs Developer ID signing and Apple notarization. No signing credentials are included.

## Controls

| Control | Action |
| --- | --- |
| ⌘E | Enable / disable processing |
| ⇧⌘R | Reset volume, EQ, and bass |
| EQ fader double-click | Reset that band |
| Focused EQ fader ↑ / ↓ | Adjust by 1 dB |
| Menu-bar speaker icon | Open / dismiss controls |

## Verification

`VolumeCheck` is a standalone executable so the signal tests run with Command Line Tools as well as Xcode. It verifies unity gain, 150% gain, lookahead latency, maximum-EQ transient protection across five sample rates, stereo linking, measured shelf/EQ frequency response, mute ramps, invalid-input recovery, and rapidly changing controls across buffer boundaries. `scripts/check.sh` also exercises the real C IO callback with planar, interleaved, and mono buffers, microphone exclusion, and missing-buffer failures under AddressSanitizer and UndefinedBehaviorSanitizer.

See [VALIDATION.md](VALIDATION.md) for the tested environment, live checks, and remaining limits. This is an initial implementation, not a claim of flawless compatibility with every macOS audio device.
