#import "AHDisplay.h"
NSArray<NSNumber *> *AHFontPresets(void) { return @[@12,@14,@16,@18,@20,@22]; }
NSArray<NSString *> *AHFontPresetNames(void) { return @[@"Rất nhỏ",@"Nhỏ",@"Vừa",@"Lớn",@"Rất lớn",@"Tối đa"]; }
NSInteger AHFontPresetIndex(void) {
    id value=[NSUserDefaults.standardUserDefaults objectForKey:@"chatFontPreset"];
    // Preserve existing point size when inserting a new preset at index zero.
    if(![NSUserDefaults.standardUserDefaults boolForKey:@"fontPresetsV2"]) {
        if(value) { [NSUserDefaults.standardUserDefaults setInteger:[value integerValue]+1 forKey:@"chatFontPreset"]; value=[NSUserDefaults.standardUserDefaults objectForKey:@"chatFontPreset"]; }
        [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"fontPresetsV2"];
    }
    NSInteger index=value?[value integerValue]:2;
    return MAX(0,MIN((NSInteger)AHFontPresets().count-1,index));
}
CGFloat AHChatFontSize(void) { return [AHFontPresets()[AHFontPresetIndex()] doubleValue]; }
void AHSetFontPreset(NSInteger index) { [NSUserDefaults.standardUserDefaults setInteger:MAX(0,MIN((NSInteger)AHFontPresets().count-1,index)) forKey:@"chatFontPreset"]; }
