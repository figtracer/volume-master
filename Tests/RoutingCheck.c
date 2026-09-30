#include "VolumeDSP.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>

static void check_layout(int planar, int microphone, int channels) {
    VMDSP *dsp=vm_create(48000);
    assert(dsp);
    vm_set_routing(dsp,microphone,channels);
    float left[256], right[256], mic[256], interleaved[512], outA[512], outB[256];
    for (int i=0;i<256;i++) {
        left[i]=0.1f; right[i]=0.2f; mic[i]=40;
        interleaved[i*2]=0.1f; interleaved[i*2+1]=0.2f;
    }
    struct { UInt32 count; AudioBuffer buffers[3]; } input={0}, output={0};
    if (microphone) input.buffers[input.count++]=(AudioBuffer){1,sizeof(mic),mic};
    if (planar || channels==1) {
        input.buffers[input.count++]=(AudioBuffer){1,sizeof(left),left};
        output.buffers[output.count++]=(AudioBuffer){1,sizeof(left),outA};
        if (channels==2) {
            input.buffers[input.count++]=(AudioBuffer){1,sizeof(right),right};
            output.buffers[output.count++]=(AudioBuffer){1,sizeof(right),outB};
        }
    } else {
        input.buffers[input.count++]=(AudioBuffer){2,sizeof(interleaved),interleaved};
        output.buffers[output.count++]=(AudioBuffer){2,sizeof(interleaved),outA};
    }
    AudioTimeStamp stamp={0};
    for (int block=0;block<256;block++)
        assert(vm_io(0,&stamp,(AudioBufferList *)&input,&stamp,(AudioBufferList *)&output,&stamp,dsp)==0);
    assert(vm_faults(dsp)==0);
    assert(vm_frames(dsp)==256*256);
    for (int i=0;i<256;i++) {
        assert(fabsf(outA[i*(planar || channels==1 ? 1 : 2)]-0.1f)<0.00002f);
        if (channels==2) assert(fabsf((planar ? outB[i] : outA[i*2+1])-0.2f)<0.00002f);
    }
    // A missing tap buffer must fail silent; physical microphone samples never enter the output.
    input.buffers[input.count-1].mData=NULL;
    vm_io(0,&stamp,(AudioBufferList *)&input,&stamp,(AudioBufferList *)&output,&stamp,dsp);
    assert(vm_faults(dsp)==1);
    for (UInt32 b=0;b<output.count;b++) {
        float *samples=output.buffers[b].mData;
        for (UInt32 i=0;i<output.buffers[b].mDataByteSize/sizeof(float);i++) assert(samples[i]==0);
    }
    vm_destroy(dsp);
}

int main(void) {
    check_layout(1,0,2); check_layout(0,0,2);
    check_layout(1,1,2); check_layout(0,1,2);
    check_layout(1,0,1); check_layout(1,1,1);
    puts("PASS planar, interleaved, mono, microphone exclusion, and fail-silent IO routing");
}
