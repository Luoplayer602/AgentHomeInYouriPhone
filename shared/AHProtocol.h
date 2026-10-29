#import <Foundation/Foundation.h>
#define AHSocketPath "/var/mobile/Library/AgentHome/agent.sock"
#define AHDataPath @"/var/mobile/Library/AgentHome"
#define AHMaxFrame (2 * 1024 * 1024)
// Protocol: one newline-delimited JSON request and response per connection.
// Requests: {"id": string, "method": string, "params": object}.
// Responses: {"id": string, "result": object} or {"id": string, "error": string}.
