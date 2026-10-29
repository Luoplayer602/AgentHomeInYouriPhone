#pragma once
#include <stddef.h>
typedef struct { size_t tokens, bytes, count, completed; } AHCompactCursor;
// Return false before consuming a row that would exceed either budget.
static inline int AHCompactConsume(AHCompactCursor *cursor,size_t cost,size_t bytes,int assistant,size_t budget,size_t byteLimit) {
    if(cursor->tokens>budget || cost>budget-cursor->tokens || cursor->bytes>byteLimit || bytes>byteLimit-cursor->bytes) return 0;
    cursor->tokens+=cost; cursor->bytes+=bytes; cursor->count++;
    if(assistant) cursor->completed=cursor->count;
    return 1;
}
