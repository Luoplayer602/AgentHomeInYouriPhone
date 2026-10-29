#import <UIKit/UIKit.h>
#define GLES_SILENCE_DEPRECATION 1
#import <OpenGLES/EAGL.h>
int main(int argc, char **argv) { @autoreleasepool {
    // Keep OpenGLES as a direct dependency. CoreUI creates a CoreImage GL
    // context lazily when rendering text-edit menu symbols on iOS 15.
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wdeprecated-declarations"
    (void)[EAGLContext class];
    #pragma clang diagnostic pop
    return UIApplicationMain(argc, argv, nil, @"AHApp");
} }
