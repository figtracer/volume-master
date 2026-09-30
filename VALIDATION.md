# Validation — 0.1.0

Tested locally on Apple silicon, macOS 26.5.1, Apple Swift 6.3.2 (Command Line Tools). No external packages are used.

## Completed

- `bash scripts/check.sh`: all signal checks passed in release configuration.
- Limiter ceiling and stereo linkage tested at 22.05, 44.1, 48, 96, and 192 kHz, with maximum tone boost and large transients.
- Unity/150% gain, 5 ms lookahead, actual EQ/shelf frequency response, mute ramps, nonfinite-input recovery, and changing controls across callback boundaries passed.
- Actual C audio callback tested with planar/interleaved stereo, mono, ignored microphone channels, and missing buffers. AddressSanitizer and UndefinedBehaviorSanitizer reported no errors.
- `bash scripts/package.sh`: native release executable and app bundle built; `codesign --verify --strict` and `plutil -lint` passed.
- Live system-audio routing on WH-1000XM4 headphones at 44.1 kHz: the application showed continuously updating output level and limiter gain reduction while another app played audio. Volume and EQ changes were reflected in the live UI.
- Normal quit exited the running audio process. The subsequent menu-bar-only build launched with saved volume/EQ values available in preferences.

## Limits

Live routing and meters do not constitute an independent recording of the physical output or a perceptual listening test. Sleep/wake, sample-rate changes, device hot-plug, permission denial/revocation, and crash cleanup have implementation paths but have not all been exercised end-to-end on hardware. Intel, macOS 14.2, wired/USB outputs, protected content, and exclusive audio clients have not been hardware-tested. The app deliberately rejects multichannel outputs.

The limiter bounds sample peaks; it is not an oversampled true-peak limiter. No guarantee is made about distortion from source recordings or downstream hardware. Builds are ad-hoc signed and not notarized.

## Compatibility

This is a new, standalone repository, with no existing downstream callers, public library API, dependencies, or persisted-data migration to preserve. Reference repositories `figtracer/dove`, `figtracer/stacksampler`, and `figtracer/pitch-shifter` were inspected for conventions/style and were not changed. The app stores its own versioned `sound.v1` settings, validates stored values, and starts processing off. It does not alter the default output device, hardware volume, or hardware sample rate.
