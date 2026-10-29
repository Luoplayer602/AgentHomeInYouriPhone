#import "AHInput.h"
@implementation AHInput
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.borderStyle = UITextBorderStyleNone;
        self.backgroundColor = [UIColor.secondarySystemBackgroundColor colorWithAlphaComponent:0.72];
        self.layer.cornerRadius = 12;
        self.layer.borderWidth = 0.5;
        self.layer.borderColor = [UIColor.separatorColor colorWithAlphaComponent:0.35].CGColor;
        self.autocorrectionType = UITextAutocorrectionTypeNo;
        self.autocapitalizationType = UITextAutocapitalizationTypeNone;
        self.spellCheckingType = UITextSpellCheckingTypeNo;
        self.smartQuotesType = UITextSmartQuotesTypeNo;
        self.smartDashesType = UITextSmartDashesTypeNo;
        self.inputAssistantItem.leadingBarButtonGroups = @[];
        self.inputAssistantItem.trailingBarButtonGroups = @[];
        UIButton *paste = [UIButton buttonWithType:UIButtonTypeSystem];
        paste.frame = CGRectMake(0, 0, 56, 44);
        paste.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
        [paste setTitle:@"Dán" forState:UIControlStateNormal];
        [paste addTarget:self action:@selector(pasteClipboard) forControlEvents:UIControlEventTouchUpInside];
        self.rightView = paste; self.rightViewMode = UITextFieldViewModeAlways;
    }
    return self;
}
- (CGRect)textRectForBounds:(CGRect)bounds { return CGRectInset([super textRectForBounds:bounds], 12, 0); }
- (CGRect)editingRectForBounds:(CGRect)bounds { return [self textRectForBounds:bounds]; }
- (BOOL)canPerformAction:(SEL)action withSender:(id)sender { return NO; }
- (void)pasteClipboard {
    NSString *text = UIPasteboard.generalPasteboard.string;
    if (!text.length) return;
    [self becomeFirstResponder];
    [self insertText:text];
}
@end
