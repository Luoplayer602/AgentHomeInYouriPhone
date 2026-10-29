#import <Foundation/Foundation.h>
FOUNDATION_EXPORT NSArray *AHProfiles(void);
FOUNDATION_EXPORT NSDictionary *AHActiveProfile(void);
FOUNDATION_EXPORT NSDictionary *AHKeyQuery(NSString *identifier);
FOUNDATION_EXPORT NSString *AHReadKey(NSString *identifier);
FOUNDATION_EXPORT BOOL AHSaveProfile(NSDictionary *profile, NSString *key, NSString **error);
