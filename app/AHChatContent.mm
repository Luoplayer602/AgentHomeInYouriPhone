#import "AHChatContent.h"
#import "AHMarkdown.h"
#import "AHDisplay.h"
#include "../core/format/MarkdownBlocks.hpp"
static NSString *AHString(const std::string& s) { return [[NSString alloc] initWithBytes:s.data() length:s.size() encoding:NSUTF8StringEncoding] ?: @""; }
@interface AHCopyButton : UIButton
@property (nonatomic,copy) NSString *code;
@end
@implementation AHCopyButton
- (void)copyCode {
    UIPasteboard.generalPasteboard.string=self.code ?: @""; [self setTitle:@"Copied" forState:UIControlStateNormal];
    __weak AHCopyButton *weak=self; dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{ [weak setTitle:@"Copy" forState:UIControlStateNormal]; });
}
@end
@interface AHRichText : UITextView
@end
@implementation AHRichText
- (BOOL)canPerformAction:(SEL)action withSender:(id)sender { return NO; }
@end
static AHRichText *AHText(NSAttributedString *text) {
    AHRichText *view=[AHRichText new]; view.editable=NO; view.selectable=YES; view.scrollEnabled=NO; view.backgroundColor=UIColor.clearColor;
    view.textContainerInset=UIEdgeInsetsZero; view.textContainer.lineFragmentPadding=0; view.attributedText=text;
    view.inputAssistantItem.leadingBarButtonGroups=@[]; view.inputAssistantItem.trailingBarButtonGroups=@[]; return view;
}
@interface AHChatContent ()
@property (nonatomic,copy) NSString *source;
@property BOOL user;
@property CGFloat fontSize;
@end
@implementation AHChatContent
- (instancetype)initWithFrame:(CGRect)frame {
    if((self=[super initWithFrame:frame])) { self.axis=UILayoutConstraintAxisVertical; self.spacing=10; }
    return self;
}
- (UIView *)codeBlock:(NSString *)code language:(NSString *)language {
    UIView *box=[UIView new]; box.backgroundColor=UIColor.tertiarySystemBackgroundColor; box.layer.cornerRadius=10; box.clipsToBounds=YES; box.layer.borderWidth=0.5; box.layer.borderColor=UIColor.separatorColor.CGColor;
    UILabel *label=[UILabel new]; label.text=language.length?language:@"Code"; label.font=[UIFont systemFontOfSize:MAX(12,AHChatFontSize()-4) weight:UIFontWeightMedium]; label.textColor=UIColor.secondaryLabelColor;
    AHCopyButton *copy=[AHCopyButton new]; [copy setTitleColor:UIColor.systemBlueColor forState:UIControlStateNormal]; copy.code=code; [copy setTitle:@"Copy" forState:UIControlStateNormal]; copy.titleLabel.font=[UIFont systemFontOfSize:MAX(12,AHChatFontSize()-3) weight:UIFontWeightSemibold]; [copy addTarget:copy action:@selector(copyCode) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *header=[[UIStackView alloc] initWithArrangedSubviews:@[label,copy]]; header.spacing=12;
    UIScrollView *scroll=[UIScrollView new]; scroll.showsHorizontalScrollIndicator=YES; scroll.alwaysBounceVertical=NO; scroll.directionalLockEnabled=YES;
    UILabel *body=[UILabel new]; body.text=code.length?code:@" "; body.font=[UIFont monospacedSystemFontOfSize:MAX(12,AHChatFontSize()-2) weight:UIFontWeightRegular]; body.textColor=UIColor.labelColor; body.numberOfLines=0; body.translatesAutoresizingMaskIntoConstraints=NO;
    CGFloat width=0; for(NSString *line in [code componentsSeparatedByString:@"\n"]) width=MAX(width,[line sizeWithAttributes:@{NSFontAttributeName:body.font}].width);
    [scroll addSubview:body];
    [NSLayoutConstraint activateConstraints:@[[body.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],[body.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],[body.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],[body.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],[body.widthAnchor constraintEqualToConstant:MAX(32,MIN(8000,ceil(width)+2))],[body.heightAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.heightAnchor]]];
    UIStackView *stack=[[UIStackView alloc] initWithArrangedSubviews:@[header,scroll]]; stack.axis=UILayoutConstraintAxisVertical; stack.spacing=10; stack.translatesAutoresizingMaskIntoConstraints=NO; [box addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[[stack.leadingAnchor constraintEqualToAnchor:box.leadingAnchor constant:12],[stack.trailingAnchor constraintEqualToAnchor:box.trailingAnchor constant:-12],[stack.topAnchor constraintEqualToAnchor:box.topAnchor constant:8],[stack.bottomAnchor constraintEqualToAnchor:box.bottomAnchor constant:-12],[copy.widthAnchor constraintEqualToConstant:60],[header.heightAnchor constraintEqualToConstant:28]]];
    return box;
}
- (UIView *)tableBlock:(const agenthome::MarkdownBlock&)block {
    UIScrollView *scroll=[UIScrollView new]; scroll.showsHorizontalScrollIndicator=YES; scroll.directionalLockEnabled=YES;
    UIStackView *table=[UIStackView new]; table.axis=UILayoutConstraintAxisVertical; table.spacing=0; table.translatesAutoresizingMaskIntoConstraints=NO; table.layer.cornerRadius=7; table.clipsToBounds=YES; [scroll addSubview:table];
    for(size_t r=0;r<block.rows.size();r++) {
        UIStackView *row=[UIStackView new]; row.axis=UILayoutConstraintAxisHorizontal; row.distribution=UIStackViewDistributionFillEqually;
        for(size_t c=0;c<block.rows[r].size();c++) {
            UIView *cell=[UIView new]; cell.backgroundColor=r==0?UIColor.tertiarySystemFillColor:UIColor.clearColor; cell.layer.borderWidth=0.5; cell.layer.borderColor=UIColor.separatorColor.CGColor;
            NSAttributedString *content=AHMarkdown(AHString(block.rows[r][c]));
            NSMutableAttributedString *styled=[content mutableCopy]; NSMutableParagraphStyle *style=[NSMutableParagraphStyle new]; style.alignment=block.align[c]==2?NSTextAlignmentRight:block.align[c]==1?NSTextAlignmentCenter:NSTextAlignmentLeft;
            [styled addAttribute:NSParagraphStyleAttributeName value:style range:NSMakeRange(0,styled.length)];
            if(r==0) [styled addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:AHChatFontSize() weight:UIFontWeightSemibold] range:NSMakeRange(0,styled.length)];
            UILabel *text=[UILabel new]; text.numberOfLines=0; text.attributedText=styled; text.translatesAutoresizingMaskIntoConstraints=NO; [cell addSubview:text];
            [NSLayoutConstraint activateConstraints:@[[text.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:9],[text.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-9],[text.topAnchor constraintEqualToAnchor:cell.topAnchor constant:9],[text.bottomAnchor constraintEqualToAnchor:cell.bottomAnchor constant:-9],[cell.heightAnchor constraintGreaterThanOrEqualToConstant:40]]];
            [row addArrangedSubview:cell];
        }
        [table addArrangedSubview:row];
    }
    [NSLayoutConstraint activateConstraints:@[[table.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],[table.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],[table.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],[table.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],[table.widthAnchor constraintEqualToConstant:MAX(200,block.align.size()*(150*AHChatFontSize()/16))],[table.heightAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.heightAnchor]]];
    return scroll;
}
- (void)setSource:(NSString *)source user:(BOOL)user {
    CGFloat size=AHChatFontSize();
    if([self.source isEqual:source] && self.user==user && self.fontSize==size) return; self.source=source; self.user=user; self.fontSize=size;
    for(UIView *view in self.arrangedSubviews) { [self removeArrangedSubview:view]; [view removeFromSuperview]; }
    if(user) { [self addArrangedSubview:AHText([[NSAttributedString alloc] initWithString:source attributes:@{NSFontAttributeName:[UIFont systemFontOfSize:AHChatFontSize()],NSForegroundColorAttributeName:UIColor.whiteColor}])]; return; }
    auto blocks=agenthome::markdownBlocks(std::string(source.UTF8String ?: ""));
    for(const auto& block:blocks) {
        if(block.kind==agenthome::MarkdownBlock::Code) [self addArrangedSubview:[self codeBlock:AHString(block.text) language:AHString(block.language)]];
        else if(block.kind==agenthome::MarkdownBlock::Table) [self addArrangedSubview:[self tableBlock:block]];
        else [self addArrangedSubview:AHText(AHMarkdown(AHString(block.text)))];
    }
    if(!self.arrangedSubviews.count) [self addArrangedSubview:AHText([[NSAttributedString alloc] initWithString:@" "])];
}
@end
