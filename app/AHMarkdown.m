#import "AHMarkdown.h"
#import "AHDisplay.h"
NSAttributedString *AHMarkdown(NSString *source) {
    static NSCache *cache; static dispatch_once_t once;
    dispatch_once(&once,^{ cache=[NSCache new]; cache.totalCostLimit=2*1024*1024; cache.countLimit=80; });
    CGFloat size=AHChatFontSize();
    NSString *cacheKey=[NSString stringWithFormat:@"%.0f|%@",size,source];
    NSAttributedString *cached=[cache objectForKey:cacheKey]; if(cached) return cached;
    NSMutableAttributedString *output=[NSMutableAttributedString new];
    BOOL fenced=NO;
    NSAttributedStringMarkdownParsingOptions *options=[NSAttributedStringMarkdownParsingOptions new];
    options.interpretedSyntax=NSAttributedStringMarkdownInterpretedSyntaxInlineOnlyPreservingWhitespace;
    options.failurePolicy=NSAttributedStringMarkdownParsingFailureReturnPartiallyParsedIfPossible;
    NSArray *lines=[source componentsSeparatedByString:@"\n"];
    for(NSUInteger i=0;i<lines.count;i++) {
        NSString *line=lines[i], *trim=[line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if([trim hasPrefix:@"```"] || [trim hasPrefix:@"~~~"]) { fenced=!fenced; continue; }
        NSUInteger heading=0; while(heading<line.length && [line characterAtIndex:heading]=='#' && heading<6) heading++;
        BOOL isHeading=!fenced && heading && line.length>heading && [line characterAtIndex:heading]==' ';
        if(isHeading) line=[line substringFromIndex:heading+1];
        BOOL quote=!fenced && [trim hasPrefix:@">"];
        if(quote) line=[@"│ " stringByAppendingString:[[trim substringFromIndex:1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet]];
        if(!fenced && ([trim hasPrefix:@"- "] || [trim hasPrefix:@"* "] || [trim hasPrefix:@"+ "])) {
            NSRange prefix=[line rangeOfString:trim];
            line=[NSString stringWithFormat:@"%@• %@",[line substringToIndex:prefix.location],[trim substringFromIndex:2]];
        }
        BOOL table=!fenced && [trim hasPrefix:@"|"] && [trim hasSuffix:@"|"];
        BOOL mono=fenced || table;
        UIFont *base=mono ? [UIFont monospacedSystemFontOfSize:MAX(12,size-2) weight:UIFontWeightRegular] : [UIFont systemFontOfSize:isHeading ? (heading==1?size+7:size+3) : size weight:isHeading?UIFontWeightSemibold:UIFontWeightRegular];
        NSAttributedString *parsed=mono ? [[NSAttributedString alloc] initWithString:line] : [[NSAttributedString alloc] initWithMarkdownString:line options:options baseURL:nil error:nil];
        if(!parsed) parsed=[[NSAttributedString alloc] initWithString:line];
        NSMutableAttributedString *styled=[parsed mutableCopy]; NSRange all=NSMakeRange(0,styled.length);
        [styled addAttributes:@{NSFontAttributeName:base,NSForegroundColorAttributeName:quote?UIColor.secondaryLabelColor:UIColor.labelColor} range:all];
        if(mono) [styled addAttribute:NSBackgroundColorAttributeName value:UIColor.tertiarySystemFillColor range:all];
        [parsed enumerateAttribute:NSInlinePresentationIntentAttributeName inRange:all options:0 usingBlock:^(NSNumber *value,NSRange range,__unused BOOL *stop){
            NSInlinePresentationIntent intent=value.unsignedIntegerValue;
            UIFontDescriptorSymbolicTraits traits=0;
            if(intent & NSInlinePresentationIntentStronglyEmphasized) traits|=UIFontDescriptorTraitBold;
            if(intent & NSInlinePresentationIntentEmphasized) traits|=UIFontDescriptorTraitItalic;
            UIFont *font=traits?[UIFont fontWithDescriptor:[base.fontDescriptor fontDescriptorWithSymbolicTraits:traits] size:base.pointSize]:base;
            if(intent & NSInlinePresentationIntentCode) { font=[UIFont monospacedSystemFontOfSize:MAX(12,size-2) weight:UIFontWeightRegular]; [styled addAttribute:NSBackgroundColorAttributeName value:UIColor.tertiarySystemFillColor range:range]; }
            [styled addAttribute:NSFontAttributeName value:font range:range];
            if(intent & NSInlinePresentationIntentStrikethrough) [styled addAttribute:NSStrikethroughStyleAttributeName value:@(NSUnderlineStyleSingle) range:range];
        }];
        // UITextView opens only explicit http(s) link taps. Other schemes stay text.
        [parsed enumerateAttribute:NSLinkAttributeName inRange:all options:0 usingBlock:^(id value,NSRange range,__unused BOOL *stop){
            NSURL *url=[value isKindOfClass:NSURL.class]?value:([value isKindOfClass:NSString.class]?[NSURL URLWithString:value]:nil);
            if(![@[@"http",@"https"] containsObject:url.scheme.lowercaseString]) [styled removeAttribute:NSLinkAttributeName range:range];
        }];
        NSMutableParagraphStyle *paragraph=[NSMutableParagraphStyle new]; paragraph.lineSpacing=3; paragraph.paragraphSpacing=isHeading?8:3;
        [styled addAttribute:NSParagraphStyleAttributeName value:paragraph range:all];
        [output appendAttributedString:styled];
        if(i+1<lines.count) [output appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n" attributes:@{NSFontAttributeName:base}]];
    }
    NSAttributedString *result=[output copy]; [cache setObject:result forKey:cacheKey cost:source.length*8+512];
    return result;
}
