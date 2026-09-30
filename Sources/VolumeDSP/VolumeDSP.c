#include "VolumeDSP.h"
#include <math.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

// -1 dBFS sample ceiling leaves reconstruction headroom; this is not a true-peak limiter.
#define CEILING 0.891250938f
#define MAX_DELAY 2048
#define QUEUE_SIZE (MAX_DELAY + 2)
typedef struct { double b0, b1, b2, a1, a2, z1[2], z2[2]; } Biquad;
struct VMDSP {
    double rate;
    _Atomic(float) controls[7];
    _Atomic(float) peak, reduction;
    _Atomic(uint64_t) frames;
    _Atomic(uint32_t) faults;
    float smoothed[7], applied[6];
    Biquad filters[6];
    float delay[2][MAX_DELAY];
    float peaks[QUEUE_SIZE];
    uint64_t indices[QUEUE_SIZE], index;
    uint32_t head, tail, delayFrames, position, controlCounter, channelOffset, channels;
    float gain, release, volumeSmooth, toneSmooth;
};

static float bounded(float x, float low, float high) {
    return isfinite(x) ? fminf(high, fmaxf(low, x)) : low;
}

// RBJ audio EQ cookbook: low shelf at 100 Hz, then five octave-spaced peaking bands.
static void configure(Biquad *f, double rate, double hz, double db, int shelf) {
    double a = pow(10, db / 40), w = 2 * M_PI * hz / rate;
    double c = cos(w), s = sin(w), alpha = s / (2 * 0.85);
    double b0, b1, b2, a0, a1, a2;
    if (shelf) {
        alpha = s / sqrt(2.0);
        double beta = 2 * sqrt(a) * alpha;
        b0 = a * ((a+1) - (a-1)*c + beta);
        b1 = 2*a * ((a-1) - (a+1)*c);
        b2 = a * ((a+1) - (a-1)*c - beta);
        a0 = (a+1) + (a-1)*c + beta;
        a1 = -2 * ((a-1) + (a+1)*c);
        a2 = (a+1) + (a-1)*c - beta;
    } else {
        b0 = 1 + alpha*a; b1 = -2*c; b2 = 1-alpha*a;
        a0 = 1 + alpha/a; a1 = -2*c; a2 = 1-alpha/a;
    }
    f->b0=b0/a0; f->b1=b1/a0; f->b2=b2/a0; f->a1=a1/a0; f->a2=a2/a0;
}

VMDSP *vm_create(double rate) {
    if (!isfinite(rate) || rate < 22050 || rate > 192000) return NULL;
    VMDSP *d = calloc(1, sizeof(VMDSP));
    if (!d) return NULL;
    d->rate = rate;
    // 5 ms lookahead and 80 ms release balance transient protection and responsiveness.
    d->delayFrames = (uint32_t)ceil(rate * 0.005);
    d->release = exp(-1.0 / (rate * 0.080));
    d->volumeSmooth = 1 - exp(-1.0 / (rate * 0.020));
    d->toneSmooth = 1 - exp(-32.0 / (rate * 0.030));
    d->gain = 1;
    d->channels = 2;
    for (int i=0;i<7;i++) atomic_init(&d->controls[i], i == 0 ? 1 : 0);
    atomic_init(&d->peak, 0); atomic_init(&d->reduction, 0);
    atomic_init(&d->frames, 0); atomic_init(&d->faults, 0);
    for (int i=0;i<6;i++) { d->filters[i].b0=1; d->applied[i]=0; }
    return d;
}

void vm_destroy(VMDSP *d) { free(d); }
void vm_set_controls(VMDSP *d, float volume, float bass, const float bands[5]) {
    atomic_store_explicit(&d->controls[0], bounded(volume, 0, 1.5), memory_order_relaxed);
    atomic_store_explicit(&d->controls[1], bounded(bass, 0, 9), memory_order_relaxed);
    for (int i=0;i<5;i++) atomic_store_explicit(&d->controls[i+2], bounded(bands[i], -9, 9), memory_order_relaxed);
}
void vm_set_routing(VMDSP *d, uint32_t offset, uint32_t channels) { d->channelOffset=offset; d->channels=channels; }
uint32_t vm_latency(VMDSP *d) { return d->delayFrames; }
float vm_peak(VMDSP *d) { return atomic_load_explicit(&d->peak, memory_order_relaxed); }
float vm_reduction(VMDSP *d) { return atomic_load_explicit(&d->reduction, memory_order_relaxed); }
uint64_t vm_frames(VMDSP *d) { return atomic_load_explicit(&d->frames, memory_order_relaxed); }
uint32_t vm_faults(VMDSP *d) { return atomic_load_explicit(&d->faults, memory_order_relaxed); }

static void frame(VMDSP *d, float l, float r, float *ol, float *orr) {
    static const double frequencies[6] = {100, 60, 250, 1000, 4000, 12000};
    float target = atomic_load_explicit(&d->controls[0], memory_order_relaxed);
    d->smoothed[0] += (target - d->smoothed[0]) * d->volumeSmooth;
    if (d->controlCounter++ % 32 == 0) {
        for (int i=0;i<6;i++) {
            float t = atomic_load_explicit(&d->controls[i+1], memory_order_relaxed);
            float *value = &d->smoothed[i+1];
            *value += (t - *value) * d->toneSmooth;
            if (fabsf(t - *value) < 0.0001f) *value=t;
            if (*value != d->applied[i]) {
                configure(&d->filters[i], d->rate, fmin(frequencies[i], d->rate*0.45), *value, i == 0);
                d->applied[i]=*value;
            }
        }
    }
    double samples[2] = {isfinite(l) ? l : 0, isfinite(r) ? r : 0};
    for (int c=0;c<2;c++) {
        for (int j=0;j<6;j++) {
            Biquad *f=&d->filters[j];
            double y=f->b0*samples[c]+f->z1[c];
            f->z1[c]=f->b1*samples[c]-f->a1*y+f->z2[c];
            f->z2[c]=f->b2*samples[c]-f->a2*y;
            if (fabs(f->z1[c])<1e-25) f->z1[c]=0;
            if (fabs(f->z2[c])<1e-25) f->z2[c]=0;
            samples[c]=y;
        }
        samples[c] *= d->smoothed[0];
    }
    float peak = fmax(fabs(samples[0]), fabs(samples[1]));
    // Monotonic queue covers the delayed output and all lookahead samples, O(1) amortized.
    while (d->head!=d->tail && d->index-d->indices[d->head]>d->delayFrames)
        d->head=(d->head+1)%QUEUE_SIZE;
    while (d->head!=d->tail) {
        uint32_t prev=(d->tail+QUEUE_SIZE-1)%QUEUE_SIZE;
        if (d->peaks[prev]>peak) break;
        d->tail=prev;
    }
    d->peaks[d->tail]=peak; d->indices[d->tail]=d->index++;
    d->tail=(d->tail+1)%QUEUE_SIZE;
    float maximum=d->peaks[d->head];
    float required=maximum>CEILING ? CEILING/maximum : 1;
    d->gain=fminf(required, 1-(1-d->gain)*d->release);
    *ol=d->delay[0][d->position]*d->gain;
    *orr=d->delay[1][d->position]*d->gain;
    d->delay[0][d->position]=(float)samples[0]; d->delay[1][d->position]=(float)samples[1];
    d->position=(d->position+1)%d->delayFrames;
}

void vm_process(VMDSP *d, const float *l, const float *r, float *ol, float *orr, uint32_t frames) {
    float peak=0, minimumGain=1;
    for (uint32_t i=0;i<frames;i++) {
        frame(d, l[i], r[i], &ol[i], &orr[i]);
        peak=fmaxf(peak, fmaxf(fabsf(ol[i]), fabsf(orr[i])));
        minimumGain=fminf(minimumGain, d->gain);
    }
    atomic_store_explicit(&d->peak, peak, memory_order_relaxed);
    atomic_store_explicit(&d->reduction, -20*log10f(fmaxf(minimumGain, 1e-12f)), memory_order_relaxed);
    atomic_fetch_add_explicit(&d->frames, frames, memory_order_relaxed);
}

static float *channel(const AudioBufferList *list, uint32_t index, uint32_t *stride, uint32_t *frames) {
    for (uint32_t i=0;i<list->mNumberBuffers;i++) {
        const AudioBuffer *b=&list->mBuffers[i];
        if (index<b->mNumberChannels) {
            *stride=b->mNumberChannels;
            *frames=b->mDataByteSize/(sizeof(float)*(*stride));
            return b->mData ? ((float *)b->mData)+index : NULL;
        }
        index-=b->mNumberChannels;
    }
    return NULL;
}

OSStatus vm_io(AudioObjectID device, const AudioTimeStamp *now, const AudioBufferList *input,
               const AudioTimeStamp *inputTime, AudioBufferList *output,
               const AudioTimeStamp *outputTime, void *context) {
    VMDSP *d=context;
    for (uint32_t i=0;i<output->mNumberBuffers;i++)
        if (output->mBuffers[i].mData) memset(output->mBuffers[i].mData, 0, output->mBuffers[i].mDataByteSize);
    uint32_t ls=0,rs=0,ols=0,ors=0,ln=0,rn=0,oln=0,orn=0;
    float *l=channel(input,d->channelOffset,&ls,&ln);
    float *r=channel(input,d->channelOffset+d->channels-1,&rs,&rn);
    float *ol=channel(output,0,&ols,&oln);
    float *orr=channel(output,d->channels-1,&ors,&orn);
    if (!l || !r || !ol || !orr || ln!=rn || ln!=oln || ln!=orn) {
        atomic_fetch_add_explicit(&d->faults,1,memory_order_relaxed);
        return noErr;
    }
    float peak=0, minimumGain=1;
    for (uint32_t i=0;i<ln;i++) {
        float a,b;
        frame(d,l[i*ls],r[i*rs],&a,&b);
        ol[i*ols]=a; orr[i*ors]=b;
        peak=fmaxf(peak,fmaxf(fabsf(a),fabsf(b)));
        minimumGain=fminf(minimumGain,d->gain);
    }
    atomic_store_explicit(&d->peak,peak,memory_order_relaxed);
    atomic_store_explicit(&d->reduction,-20*log10f(fmaxf(minimumGain,1e-12f)),memory_order_relaxed);
    atomic_fetch_add_explicit(&d->frames,ln,memory_order_relaxed);
    return noErr;
}
