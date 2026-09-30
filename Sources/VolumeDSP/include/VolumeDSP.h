#pragma once
#include <CoreAudio/CoreAudio.h>
#include <stdint.h>

typedef struct VMDSP VMDSP;
#pragma clang assume_nonnull begin
// One control-thread writer, one audio-thread reader. No allocation or locks in render.
VMDSP * _Nullable vm_create(double sampleRate);
void vm_destroy(VMDSP *dsp);
void vm_set_controls(VMDSP *dsp, float volume, float bass, const float *bands);
void vm_set_routing(VMDSP *dsp, uint32_t inputChannelOffset, uint32_t channels);
void vm_process(VMDSP *dsp, const float *left, const float *right, float *outLeft, float *outRight, uint32_t frames);
uint32_t vm_latency(VMDSP *dsp);
float vm_peak(VMDSP *dsp);
float vm_reduction(VMDSP *dsp);
uint64_t vm_frames(VMDSP *dsp);
uint32_t vm_faults(VMDSP *dsp);
OSStatus vm_io(AudioObjectID device, const AudioTimeStamp * _Nonnull now, const AudioBufferList * _Nonnull input,
               const AudioTimeStamp * _Nonnull inputTime, AudioBufferList * _Nonnull output,
               const AudioTimeStamp * _Nonnull outputTime, void * _Nullable context);
#pragma clang assume_nonnull end
