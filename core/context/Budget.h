#pragma once
#include <stddef.h>
typedef struct { size_t window, output, reserve, input; } AHContextLimits;
static inline size_t AHMin(size_t a,size_t b) { return a<b?a:b; }
static inline AHContextLimits AHComputeContextLimits(size_t window,size_t inputMax,size_t outputMax,size_t requestedOutput) {
    if(window<1024) window=32768;
    if(window>2000000) window=2000000;
    size_t output=requestedOutput?requestedOutput:8192;
    if(outputMax) output=AHMin(output,outputMax);
    output=AHMin(output,window/4);
    size_t reserve=window/20; if(reserve<1024) reserve=1024;
    size_t input=window>output+reserve?window-output-reserve:0;
    if(inputMax) input=AHMin(input,inputMax);
    return (AHContextLimits){window,output,reserve,input};
}
static inline size_t AHEstimatedTokens(size_t jsonBytes) { return (jsonBytes+2)/3+8; }
