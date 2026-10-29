#import "../app/AHClient.h"
int main(void) { @autoreleasepool {
    NSError *error = nil;
    NSDictionary *info = [AHClient call:@"system.info" params:@{} error:&error];
    if (!info) { NSLog(@"FAIL: %@", error); return 1; }
    NSLog(@"PASS system.info: %@", info);
    NSDictionary *history = [AHClient call:@"chat.list" params:@{} error:&error];
    if (!history) { NSLog(@"FAIL history: %@", error); return 2; }
    if ([AHClient call:@"shell.exec" params:@{} error:&error]) return 3;
    NSLog(@"PASS history and unknown tool rejection"); return 0;
} }
