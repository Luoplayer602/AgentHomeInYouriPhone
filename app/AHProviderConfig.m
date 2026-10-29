#import "AHProviderConfig.h"
NSURL *AHChatURL(NSString *input, NSString **error) {
    NSString *text = [input stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSURLComponents *parts = [NSURLComponents componentsWithString:text];
    if (![parts.scheme.lowercaseString isEqual:@"https"] || !parts.host.length || parts.user.length || parts.password.length || parts.fragment.length) {
        if (error) *error = @"Cần URL HTTPS hợp lệ, không chứa tài khoản hoặc fragment.";
        return nil;
    }
    NSString *path = parts.path ?: @"";
    while ([path hasSuffix:@"/"]) path = [path substringToIndex:path.length - 1];
    if ([path hasSuffix:@"/responses"] || [path hasSuffix:@"/messages"]) {
        if (error) *error = @"Bản này hỗ trợ OpenAI Chat Completions. Endpoint Responses/Anthropic Messages cần adapter riêng.";
        return nil;
    }
    if (![path hasSuffix:@"/chat/completions"]) {
        path = path.length ? [path stringByAppendingString:@"/chat/completions"] : @"/v1/chat/completions";
    }
    parts.path = path;
    return parts.URL;
}
