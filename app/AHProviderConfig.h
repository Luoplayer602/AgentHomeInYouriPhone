#import <Foundation/Foundation.h>
// Accept a base URL or a complete Chat Completions URL, without guessing
// nonstandard prefixes. Explicit endpoints for other protocols are rejected.
FOUNDATION_EXPORT NSURL *AHChatURL(NSString *input, NSString **error);
