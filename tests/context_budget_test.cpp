#include "../core/context/Budget.h"
#include <cassert>
#include <cstdio>
int main() {
    auto large=AHComputeContextLimits(200000,0,0,8192);
    assert(large.input==181808 && large.reserve==10000);
    size_t tokens=500, messages=0;
    while(tokens+AHEstimatedTokens(1500)<=large.input) { tokens+=AHEstimatedTokens(1500); messages++; }
    assert(messages>100); // Regress old 100-message/16K-character truncation.
    assert(messages*1500>500000);
    auto separate=AHComputeContextLimits(200000,100000,4096,8192);
    assert(separate.input==100000 && separate.output==4096);
    auto unknown=AHComputeContextLimits(0,0,0,0);
    assert(unknown.window==32768 && unknown.input<32768);
    auto tiny=AHComputeContextLimits(1024,0,0,8192);
    assert(tiny.input==0); // Reject impossible request, never unsigned-wrap.
    auto enormous=AHComputeContextLimits(9000000,0,0,8192);
    assert(enormous.window==2000000);
    std::puts("PASS context: 200K budget, >100 messages, output/input ceilings, unknown fallback, overflow guard");
}
