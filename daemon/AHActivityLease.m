#import "AHActivityLease.h"
// Public IOKit ABI, declared locally because this SDK omits pwr_mgt headers.
extern int32_t IOPMAssertionCreateWithDescription(CFStringRef,CFStringRef,CFStringRef,CFStringRef,CFStringRef,CFTimeInterval,CFStringRef,uint32_t *);
extern int32_t IOPMAssertionRelease(uint32_t);
@interface AHActivityLease ()
@property uint32_t identifier;
@property BOOL held;
@end
@implementation AHActivityLease
- (int32_t)begin {
    [self end];
    int32_t result=IOPMAssertionCreateWithDescription(CFSTR("PreventUserIdleSystemSleep"),CFSTR("Agent Home AI turn"),CFSTR("Finish active provider request while display is off"),NULL,NULL,900,CFSTR("TimeoutActionTurnOff"),&_identifier);
    self.held=result==0; return result;
}
- (void)end { if(self.held) { IOPMAssertionRelease(self.identifier); self.held=NO; self.identifier=0; } }
- (void)dealloc { [self end]; }
@end
