#import "AHClient.h"
#import "../shared/AHProtocol.h"
#import <sys/socket.h>
#import <sys/un.h>
#import <unistd.h>
#import <string.h>
#import <errno.h>
@implementation AHClient
+ (NSDictionary *)call:(NSString *)method params:(NSDictionary *)params error:(NSError **)error {
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    struct timeval timeout = {5, 0};
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
    int noSig = 1; setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSig, sizeof(noSig));
    struct sockaddr_un address = {0}; address.sun_family = AF_UNIX;
    strlcpy(address.sun_path, AHSocketPath, sizeof(address.sun_path));
    NSString *failure = nil;
    NSDictionary *response = nil;
    NSString *identifier = NSUUID.UUID.UUIDString;
    if (connect(fd, (struct sockaddr *)&address, sizeof(address))) failure = @"Không kết nối được daemon. Kiểm tra jailbreak và launchd.";
    if (!failure) {
        NSMutableData *out = [[NSJSONSerialization dataWithJSONObject:@{@"id":identifier, @"method":method, @"params":params} options:0 error:nil] mutableCopy];
        [out appendBytes:"\n" length:1];
        const char *p = out.bytes; NSUInteger left = out.length;
        while (left) { ssize_t n = write(fd, p, left); if (n <= 0) { failure = @"IPC write failed"; break; } p += n; left -= n; }
    }
    if (!failure) {
        NSMutableData *input = [NSMutableData data]; BOOL complete=NO; char chunk[4096];
        while(input.length<AHMaxFrame) {
            ssize_t n=read(fd,chunk,MIN(sizeof(chunk),AHMaxFrame-input.length));
            if(n<0 && errno==EINTR) continue;
            if(n<=0) break;
            const char *newline=memchr(chunk,'\n',(size_t)n);
            [input appendBytes:chunk length:newline?(NSUInteger)(newline-chunk):(NSUInteger)n];
            if(newline) { complete=YES; break; }
        }
        if (!complete) failure = @"IPC response incomplete";
        else {
            id value = [NSJSONSerialization JSONObjectWithData:input options:0 error:nil];
            if (![value isKindOfClass:NSDictionary.class] || ![value[@"id"] isEqual:identifier]) failure = @"Invalid IPC response";
            else { response = value; failure = response[@"error"]; }
        }
    }
    close(fd);
    if (failure && error) *error = [NSError errorWithDomain:@"AgentHome" code:1 userInfo:@{NSLocalizedDescriptionKey:failure}];
    return failure ? nil : response[@"result"];
}
@end
