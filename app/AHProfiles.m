#import "AHProfiles.h"
#import <Security/Security.h>
NSArray *AHProfiles(void) {
    NSUserDefaults *d=NSUserDefaults.standardUserDefaults; NSArray *profiles=[d arrayForKey:@"providers"];
    if(!profiles.count) {
        profiles=@[@{@"id":@"legacy",@"name":@"Provider hiện tại",@"endpoint":[d stringForKey:@"endpoint"] ?: @"",@"model":[d stringForKey:@"model"] ?: @"",@"disableStreaming":@([d boolForKey:@"disableStreaming"])}];
        [d setObject:profiles forKey:@"providers"]; [d setObject:@"legacy" forKey:@"activeProvider"];
    }
    return profiles;
}
NSDictionary *AHActiveProfile(void) {
    NSArray *profiles=AHProfiles(); NSString *active=[NSUserDefaults.standardUserDefaults stringForKey:@"activeProvider"];
    for(NSDictionary *profile in profiles) if([profile[@"id"] isEqual:active]) return profile;
    return profiles.firstObject;
}
NSDictionary *AHKeyQuery(NSString *identifier) {
    return @{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,(__bridge id)kSecAttrService:@"dev.agenthome.provider",(__bridge id)kSecAttrAccount:[identifier isEqual:@"legacy"] ? @"api-key" : identifier};
}
NSString *AHReadKey(NSString *identifier) {
    NSMutableDictionary *q=[AHKeyQuery(identifier) mutableCopy]; q[(__bridge id)kSecReturnData]=@YES;
    CFTypeRef value=NULL; if(SecItemCopyMatching((__bridge CFDictionaryRef)q,&value)!=errSecSuccess) return @"";
    return [[NSString alloc] initWithData:CFBridgingRelease(value) encoding:NSUTF8StringEncoding] ?: @"";
}
BOOL AHSaveProfile(NSDictionary *profile,NSString *key,NSString **error) {
    if(key.length) {
        NSMutableDictionary *q=[AHKeyQuery(profile[@"id"]) mutableCopy]; q[(__bridge id)kSecValueData]=[key dataUsingEncoding:NSUTF8StringEncoding]; q[(__bridge id)kSecAttrAccessible]=(__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly;
        OSStatus status=SecItemAdd((__bridge CFDictionaryRef)q,NULL);
        if(status==errSecDuplicateItem) status=SecItemUpdate((__bridge CFDictionaryRef)AHKeyQuery(profile[@"id"]),(__bridge CFDictionaryRef)@{(__bridge id)kSecValueData:[key dataUsingEncoding:NSUTF8StringEncoding]});
        if(status!=errSecSuccess) { if(error) *error=[NSString stringWithFormat:@"Keychain lỗi %d",(int)status]; return NO; }
    }
    NSMutableArray *profiles=[AHProfiles() mutableCopy]; NSUInteger index=[profiles indexOfObjectPassingTest:^BOOL(NSDictionary *p,__unused NSUInteger i,__unused BOOL *stop){ return [p[@"id"] isEqual:profile[@"id"]]; }];
    if(index==NSNotFound) [profiles addObject:profile]; else profiles[index]=profile;
    [NSUserDefaults.standardUserDefaults setObject:profiles forKey:@"providers"];
    [NSUserDefaults.standardUserDefaults setObject:profile[@"id"] forKey:@"activeProvider"]; return YES;
}
