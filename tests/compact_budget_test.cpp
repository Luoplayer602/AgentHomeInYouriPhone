#include "../core/context/Budget.h"
#include "../core/context/Compaction.h"
#include <cassert>
#include <cstdio>
int main() {
    auto limits=AHComputeContextLimits(200000,0,0,8192);
    AHCompactCursor cursor={1000,0,0,0};
    for(size_t i=0;i<800;i++) {
        if(!AHCompactConsume(&cursor,AHEstimatedTokens(1200),1000,i%2==1,limits.input,4*1024*1024)) break;
    }
    assert(cursor.count>200 && cursor.bytes>96000);
    assert(cursor.tokens<=limits.input && cursor.completed%2==0);
    auto saved=cursor;
    assert(!AHCompactConsume(&cursor,limits.input,1,1,limits.input,4*1024*1024));
    assert(cursor.count==saved.count && cursor.completed==saved.completed);
    AHCompactCursor unpaired={0,0,0,0};
    assert(AHCompactConsume(&unpaired,20,5,0,100,100));
    assert(unpaired.completed==0);
    assert(AHCompactConsume(&unpaired,20,5,1,100,100));
    assert(AHCompactConsume(&unpaired,20,5,0,100,100));
    assert(unpaired.count==3 && unpaired.completed==2);
    assert(!AHCompactConsume(&unpaired,1,200,1,100,100));
    AHCompactCursor impossible={1000,0,0,0};
    assert(!AHCompactConsume(&impossible,1,1,1,500,100));
    puts("PASS compact cursor: 200K, >200 rows/>96K chars, completed-turn boundary, byte/token caps, no overflow");
}
