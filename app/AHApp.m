#import <UIKit/UIKit.h>
#import <Security/Security.h>
#import "AHClient.h"
#import "AHProviderConfig.h"
#import "AHProvider.h"
#import "AHProfiles.h"
#import "AHMarkdown.h"
#import "AHInput.h"
#import "AHSettings.h"
#import "AHChatContent.h"
#import "AHDisplay.h"
#import "AHContext.h"
#import "AHTaskList.h"
@interface AHChatCell : UITableViewCell
@property (nonatomic, strong) UIView *bubble;
@property (nonatomic, strong) AHChatContent *messageLabel;
@property (nonatomic, strong) NSLayoutConstraint *left;
@property (nonatomic, strong) NSLayoutConstraint *right;
@property (nonatomic, strong) NSLayoutConstraint *bubbleWidth;
@property (nonatomic, copy) NSString *rawText;
@property BOOL isUser;
- (void)showText:(NSString *)text user:(BOOL)user;
@end
@implementation AHChatCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    if ((self = [super initWithStyle:style reuseIdentifier:identifier])) {
        self.selectionStyle = UITableViewCellSelectionStyleNone; self.backgroundColor = UIColor.clearColor;
        self.bubble = [UIView new]; self.bubble.translatesAutoresizingMaskIntoConstraints = NO; self.bubble.layer.cornerRadius = 17;
        self.messageLabel=[AHChatContent new]; self.messageLabel.translatesAutoresizingMaskIntoConstraints=NO;
        [self.contentView addSubview:self.bubble]; [self.bubble addSubview:self.messageLabel];
        self.left = [self.bubble.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:4];
        self.right = [self.bubble.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-4];
        self.bubbleWidth=[self.bubble.widthAnchor constraintEqualToConstant:100];
        [NSLayoutConstraint activateConstraints:@[self.bubbleWidth,[self.bubble.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:5], [self.bubble.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-5], [self.bubble.widthAnchor constraintLessThanOrEqualToAnchor:self.contentView.widthAnchor multiplier:0.86], [self.messageLabel.topAnchor constraintEqualToAnchor:self.bubble.topAnchor constant:12], [self.messageLabel.bottomAnchor constraintEqualToAnchor:self.bubble.bottomAnchor constant:-12], [self.messageLabel.leadingAnchor constraintEqualToAnchor:self.bubble.leadingAnchor constant:14], [self.messageLabel.trailingAnchor constraintEqualToAnchor:self.bubble.trailingAnchor constant:-14]]];
    }
    return self;
}
- (void)showText:(NSString *)text user:(BOOL)user {
    self.left.active = NO; self.right.active = NO;
    (user ? self.right : self.left).active = YES;
    self.rawText=text; self.isUser=user;
    [self updateBubbleWidth];
    [self.messageLabel setSource:text user:user];
    self.bubble.backgroundColor = user ? UIColor.systemBlueColor : UIColor.secondarySystemBackgroundColor;
}
- (void)updateBubbleWidth {
    CGFloat available=self.contentView.bounds.size.width;
    if(available<50) available=UIScreen.mainScreen.bounds.size.width-24;
    CGFloat maximum=floor(available*0.86);
    CGFloat desired=maximum;
    if(self.isUser) {
        // Measure unwrapped lines; the text view handles wrapping at maximum.
        // Include padding and fractional glyph widths to prevent extra wrapping.
        UIFont *font=[UIFont systemFontOfSize:AHChatFontSize()]; CGFloat longest=0;
        for(NSString *line in [self.rawText componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) longest=MAX(longest,[line sizeWithAttributes:@{NSFontAttributeName:font}].width);
        desired=MIN(maximum,MAX(52,ceil(longest)+30));
    }
    if(fabs(self.bubbleWidth.constant-desired)>0.5) self.bubbleWidth.constant=desired;
}
- (void)layoutSubviews { [self updateBubbleWidth]; [super layoutSubviews]; }

@end

@interface AHController : UIViewController <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *chat;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) AHProvider *provider;
@property (nonatomic, strong) NSMutableString *draft;
@property NSUInteger runID;
@property BOOL running;
@property BOOL requestStreaming;
@property BOOL renderScheduled;
@property UITextField *input;
@property UIButton *sendButton;
@property NSMutableArray *messages;
@property BOOL busy;
@property (nonatomic,strong) UIButton *contextButton;
@property NSUInteger historyCount;
@property (nonatomic, copy) NSString *conversationID;
@end
@implementation AHController
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = @"Agent Home"; self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.conversationID = self.conversationID ?: @"legacy";
    [NSUserDefaults.standardUserDefaults setObject:self.conversationID forKey:@"activeConversation"];
    self.messages = [NSMutableArray array]; self.draft = [NSMutableString string];
    self.navigationItem.rightBarButtonItems = @[
        [[UIBarButtonItem alloc] initWithTitle:@"Cài đặt" style:UIBarButtonItemStylePlain target:self action:@selector(settings)],
        [[UIBarButtonItem alloc] initWithTitle:@"Mới" style:UIBarButtonItemStylePlain target:self action:@selector(newChat)]];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Quay lại" style:UIBarButtonItemStylePlain target:self action:@selector(back)];
    self.chat = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.chat.dataSource = self; self.chat.delegate = self;
    self.chat.separatorStyle = UITableViewCellSeparatorStyleNone; self.chat.backgroundColor = UIColor.clearColor;
    self.chat.rowHeight = UITableViewAutomaticDimension; self.chat.estimatedRowHeight = 70;
    self.chat.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.chat registerClass:AHChatCell.class forCellReuseIdentifier:@"message"];
    self.statusLabel = [UILabel new]; self.statusLabel.font = [UIFont systemFontOfSize:12]; self.statusLabel.textColor = UIColor.secondaryLabelColor;
    self.statusLabel.numberOfLines = 2; self.statusLabel.text = @"Đang tải hội thoại…";
    [self.statusLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
    self.input = [AHInput new]; self.input.placeholder = @"Nhắn tin…";
    self.sendButton = [UIButton buttonWithType:UIButtonTypeSystem]; [self.sendButton setTitle:@"Gửi" forState:UIControlStateNormal]; [self.sendButton addTarget:self action:@selector(send) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[self.input,self.sendButton]]; row.spacing = 8;
    UIVisualEffectView *composer = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial]];
    composer.layer.cornerRadius = 18; composer.clipsToBounds = YES;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [composer.contentView addSubview:row];
    [NSLayoutConstraint activateConstraints:@[[row.topAnchor constraintEqualToAnchor:composer.contentView.topAnchor constant:8], [row.bottomAnchor constraintEqualToAnchor:composer.contentView.bottomAnchor constant:-8], [row.leadingAnchor constraintEqualToAnchor:composer.contentView.leadingAnchor constant:8], [row.trailingAnchor constraintEqualToAnchor:composer.contentView.trailingAnchor constant:-8]]];
    self.contextButton=[UIButton buttonWithType:UIButtonTypeSystem]; self.contextButton.titleLabel.font=[UIFont systemFontOfSize:12]; self.contextButton.accessibilityLabel=@"Mức sử dụng context";
    [self.contextButton addTarget:self action:@selector(contextInfo) forControlEvents:UIControlEventTouchUpInside];
    UIButton *tasks=[UIButton buttonWithType:UIButtonTypeSystem]; [tasks setTitle:@"Tác vụ" forState:UIControlStateNormal]; tasks.titleLabel.font=[UIFont systemFontOfSize:12]; [tasks addTarget:self action:@selector(tasks) forControlEvents:UIControlEventTouchUpInside];
    [self.contextButton setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal]; [tasks setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    UIStackView *info=[[UIStackView alloc] initWithArrangedSubviews:@[self.statusLabel,self.contextButton,tasks]]; info.spacing=10; self.statusLabel.numberOfLines=1; [self.statusLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[self.chat,info,composer]]; stack.axis = UILayoutConstraintAxisVertical; stack.spacing = 10; stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[[stack.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8], [stack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12], [stack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12], [stack.bottomAnchor constraintEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor constant:-8], [row.heightAnchor constraintEqualToConstant:44], [self.sendButton.widthAnchor constraintEqualToConstant:48]]];
    [self setWorking:YES];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{
        NSError *error = nil; [AHClient call:@"chat.touch" params:@{@"conversation_id":self.conversationID} error:nil];
        NSDictionary *result = [AHClient call:@"chat.list" params:@{@"conversation_id":self.conversationID} error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{ [self setWorking:NO]; if (result) { [self.messages addObjectsFromArray:result[@"messages"]]; self.historyCount=[result[@"total_messages"] unsignedIntegerValue]; [self render]; } else [self show:error.localizedDescription]; });
    });
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.input.font=[UIFont systemFontOfSize:AHChatFontSize()];
    [self render];
    if(!self.busy) self.statusLabel.text=[NSString stringWithFormat:@"%@ · %@",AHActiveProfile()[@"name"],AHActiveProfile()[@"model"]];
}
- (void)show:(NSString *)message {
    if(self.presentedViewController || !self.view.window) { self.statusLabel.text=message; return; }
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Agent Home" message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]]; [self presentViewController:a animated:YES completion:nil];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.messages.count + (self.draft.length ? 1 : 0);
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    AHChatCell *cell = [tableView dequeueReusableCellWithIdentifier:@"message" forIndexPath:path];
    NSDictionary *message = path.row < (NSInteger)self.messages.count ? self.messages[path.row] : @{@"role":@"assistant", @"content":self.draft};
    [cell showText:message[@"content"] user:[message[@"role"] isEqual:@"user"]];
    return cell;
}
- (void)render {
    NSDictionary *context=AHContextSnapshot(self.messages,self.historyCount);
    double percent=[context[@"characters"] doubleValue]*100/AHContextBudget;
    [self.contextButton setTitle:[NSString stringWithFormat:@"◉ %.0f%%",percent] forState:UIControlStateNormal];
    self.contextButton.tintColor=percent>=90?UIColor.systemOrangeColor:UIColor.systemBlueColor;
    [self.chat reloadData];
    NSInteger rows = self.messages.count + (self.draft.length ? 1 : 0);
    if (rows) [self.chat scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:rows-1 inSection:0] atScrollPosition:UITableViewScrollPositionBottom animated:NO];
}
- (void)contextInfo {
    NSDictionary *context=AHContextSnapshot(self.messages,self.historyCount);
    [self show:[NSString stringWithFormat:@"Context gửi lần tới: %@ / %@ ký tự tin nhắn\n%lu tin được đưa vào · %@ tin cũ ngoài lượt gửi\n\nĐây là ngân sách đầu vào của app, KHÔNG phải số token hay giới hạn context thật của model. Chưa tính system prompt và tool schema. Lịch sử đầy đủ vẫn ở SQLite.\n\nCompact bằng bản tóm tắt có checkpoint sẽ được triển khai tiếp; hiện app chưa tự tóm tắt.",context[@"characters"],context[@"budget"],(unsigned long)[context[@"messages"] count],context[@"omitted"]]];
}
- (void)tasks {
    if(self.presentedViewController) return;
    AHTaskList *list=[AHTaskList new]; list.conversationID=self.conversationID;
    [self presentViewController:[[UINavigationController alloc] initWithRootViewController:list] animated:YES completion:nil];
}
- (void)settings {
    if (self.busy || self.presentedViewController) return;
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:[AHSettings new]];
    navigation.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:navigation animated:YES completion:nil];
}
- (void)back {
    if (self.busy) return;
    [self.view endEditing:YES];
    [self.navigationController popViewControllerAnimated:YES];
}
- (void)newChat {
    if (self.busy) return;
    [self setWorking:YES];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{
        NSError *error = nil; NSDictionary *result = [AHClient call:@"chat.create" params:@{} error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self setWorking:NO];
            if (!result) { [self show:error.localizedDescription]; return; }
            AHController *chat = [AHController new]; chat.conversationID = result[@"id"];
            [self.navigationController setViewControllers:@[self.navigationController.viewControllers.firstObject,chat] animated:YES];
        });
    });
}
- (void)setWorking:(BOOL)working {
    self.navigationItem.leftBarButtonItem.enabled = !working;
    for (UIBarButtonItem *item in self.navigationItem.rightBarButtonItems) item.enabled = !working;
    self.navigationController.interactivePopGestureRecognizer.enabled = !working;
    self.busy = working; self.sendButton.enabled = !working || self.running; self.input.enabled = !working;
    [self.sendButton setTitle:(working && self.running) ? @"Dừng" : @"Gửi" forState:UIControlStateNormal];
    self.title = @"Agent Home";
    if (!working && [self.statusLabel.text isEqual:@"Đang tải hội thoại…"]) self.statusLabel.text = @"Sẵn sàng.";
}
- (void)send {
    if (self.busy) { [self stop]; return; }
    NSString *text = [self.input.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (self.busy || !text.length) return;
    if (text.length > 8000) { [self show:@"Tin nhắn tối đa 8.000 ký tự trong bản đầu."]; return; }
    NSDictionary *profile=AHActiveProfile();
    NSString *endpoint=profile[@"endpoint"], *model=profile[@"model"], *key=AHReadKey(profile[@"id"]);
    self.requestStreaming=![profile[@"disableStreaming"] boolValue];
    if (!endpoint.length || !model.length || !key.length) { [self settings]; return; }
    self.running = NO; ++self.runID; NSUInteger run = self.runID; self.draft = [NSMutableString string];
    [self setWorking:YES];
    NSDictionary *message = @{@"role":@"user", @"content":text};
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{
        NSError *error = nil; [AHClient call:@"chat.append" params:@{@"role":message[@"role"],@"content":message[@"content"],@"conversation_id":self.conversationID} error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.runID != run) return;
            if (error) { self.running = NO; [self setWorking:NO]; [self show:error.localizedDescription]; return; }
            self.running = YES; [self setWorking:YES];
            self.historyCount++; [self.messages addObject:message]; self.input.text = @""; [self render];
            NSString *system = [NSString stringWithFormat:@"Bạn là trợ lý Agent Home. Model ID đang cấu hình là %@; đây là ID do provider cung cấp, không xác minh danh tính mô hình phía sau. Chỉ có công cụ system_info đọc dung lượng và phiên bản hệ điều hành. Không khẳng định đã thực hiện hành động nếu chưa có kết quả công cụ.", model];
            NSMutableArray *context = [NSMutableArray arrayWithObject:@{@"role":@"system", @"content":system}];
            // Keep outbound context bounded on the 2 GB device.
            [context addObjectsFromArray:AHContextSnapshot(self.messages,self.historyCount)[@"messages"]];
            [self request:context endpoint:endpoint model:model key:key round:0];
        });
    });
}
- (void)request:(NSMutableArray *)context endpoint:(NSString *)endpoint model:(NSString *)model key:(NSString *)key round:(NSUInteger)round {
    NSUInteger run = self.runID;
    if (!self.running) return;
    NSDictionary *tool = @{@"type":@"function", @"function":@{@"name":@"system_info", @"description":@"Read iPhone OS version and disk space. Read-only, risk level 0.", @"parameters":@{@"type":@"object", @"properties":@{}, @"additionalProperties":@NO}}};
    NSString *urlError = nil; NSURL *url = AHChatURL(endpoint, &urlError);
    if (!url) { [self completeAnswer:nil error:[NSError errorWithDomain:@"AgentHome" code:1 userInfo:@{NSLocalizedDescriptionKey:urlError}]]; return; }
    self.provider = [AHProvider new];
    self.statusLabel.text = [NSString stringWithFormat:@"%@ · Đang chờ phản hồi…", model];
    BOOL streaming = self.requestStreaming;
    __weak AHController *weakSelf = self;
    [self.provider sendTo:url model:model key:key messages:context tools:@[tool] streaming:streaming delta:^(NSString *delta) {
        AHController *self = weakSelf; if (!self || self.runID != run || !self.running) return;
        [self.draft appendString:delta]; self.statusLabel.text = @"Đang trả lời…";
        [self scheduleRender];
    } completion:^(NSDictionary *message, NSError *error) {
        AHController *self = weakSelf; if (!self || self.runID != run || !self.running) return;
        self.provider = nil;
        if (error) { [self completeAnswer:nil error:error]; return; }
        id calls = message[@"tool_calls"];
        if ([calls isKindOfClass:NSArray.class] && [calls count]) {
            if (round >= 3 || [calls count] > 4) { [self failRun:@"Đã đạt giới hạn gọi công cụ."]; return; }
            // Validate the entire batch before executing any tool. Only system_info
            // with an empty argument object is currently granted by policy.
            for (id call in calls) {
                if (![call isKindOfClass:NSDictionary.class] || ![call[@"function"] isKindOfClass:NSDictionary.class]) { [self failRun:@"Tool call không hợp lệ."]; return; }
                id function = call[@"function"];
                id args = [function isKindOfClass:NSDictionary.class] ? function[@"arguments"] : nil;
                id parsed = [args isKindOfClass:NSString.class] ? [NSJSONSerialization JSONObjectWithData:[args dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil] : nil;
                if (![call[@"id"] isKindOfClass:NSString.class] || ![call[@"id"] length] || ![function[@"name"] isEqual:@"system_info"] || ![parsed isKindOfClass:NSDictionary.class] || [parsed count]) { [self failRun:@"Tool call bị từ chối: chỉ cho phép system_info với tham số {}."]; return; }
            }
            [context addObject:message];
            self.draft = [NSMutableString string]; [self render]; self.statusLabel.text = @"Công cụ: đọc dung lượng thiết bị…";
            // Bound to one read-only capability; serial execution on background
            // queue avoids blocking UI while the daemon responds.
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{
                NSMutableArray *outputs = [NSMutableArray array];
                for (NSDictionary *call in calls) {
                    NSError *toolError = nil; id result = [AHClient call:@"system.info" params:@{} error:&toolError];
                    NSString *content = result ? [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:result options:0 error:nil] encoding:NSUTF8StringEncoding] : toolError.localizedDescription;
                    [outputs addObject:@{@"role":@"tool",@"tool_call_id":call[@"id"],@"content":content ?: @"Tool failed"}];
                }
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (self.runID != run || !self.running) return;
                    [context addObjectsFromArray:outputs]; [self request:context endpoint:endpoint model:model key:key round:round+1];
                });
            });
            return;
        }
        id answer = message[@"content"];
        if (![answer isKindOfClass:NSString.class] || ![answer length] || [answer length] > 32000) { [self failRun:@"Provider không trả văn bản hợp lệ."]; return; }
        [self completeAnswer:answer error:nil];
    }];
}
- (void)failRun:(NSString *)reason {
    [self completeAnswer:nil error:[NSError errorWithDomain:@"AgentHome" code:1 userInfo:@{NSLocalizedDescriptionKey:reason}]];
}
- (void)scheduleRender {
    if (self.renderScheduled) return; self.renderScheduled = YES;
    __weak AHController *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        AHController *self = weakSelf; if (!self) return; self.renderScheduled = NO; [self render];
    });
}
- (void)stop {
    if (!self.running) return;
    ++self.runID; [self.provider cancel]; self.provider = nil;
    NSString *partial = self.draft.length ? [[self.draft substringToIndex:MIN(self.draft.length, (NSUInteger)31900)] stringByAppendingString:@"\n\n[Đã dừng]"] : nil;
    self.statusLabel.text = @"Đã dừng yêu cầu.";
    [self completeAnswer:partial error:nil];
}
- (void)completeAnswer:(NSString *)answer error:(NSError *)error {
    self.running = NO;
    NSString *text = answer;
    if (!text.length && error && self.draft.length) text = [[self.draft substringToIndex:MIN(self.draft.length, (NSUInteger)31900)] stringByAppendingString:@"\n\n[Phản hồi bị gián đoạn]"];
    self.draft = [NSMutableString string];
    if (!text.length) { [self setWorking:NO]; [self render]; if (error) { self.statusLabel.text = @"Yêu cầu thất bại."; [self show:error.localizedDescription]; } return; }
    NSDictionary *item = @{@"role":@"assistant", @"content":text};
    self.historyCount++; [self.messages addObject:item]; [self render];
    self.sendButton.enabled = NO;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{
        NSError *saveError = nil; [AHClient call:@"chat.append" params:@{@"role":item[@"role"],@"content":item[@"content"],@"conversation_id":self.conversationID} error:&saveError];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self setWorking:NO];
            if (error) { self.statusLabel.text = @"Phản hồi bị gián đoạn."; [self show:error.localizedDescription]; }
            else if (![text hasSuffix:@"[Đã dừng]"]) self.statusLabel.text = @"Đã lưu hội thoại.";
            if (saveError) [self show:saveError.localizedDescription];
        });
    });
}

@end
@interface AHConversations : UITableViewController
@property (nonatomic, strong) NSArray *conversations;
@property BOOL loading;
@end
@implementation AHConversations
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = @"Hội thoại"; self.conversations = @[];
    self.navigationItem.rightBarButtonItems = @[
        [[UIBarButtonItem alloc] initWithTitle:@"Mới" style:UIBarButtonItemStylePlain target:self action:@selector(newChat)],
        [[UIBarButtonItem alloc] initWithTitle:@"Cài đặt" style:UIBarButtonItemStylePlain target:self action:@selector(settings)]];
    self.tableView.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.tableView.tableFooterView = [UIView new];
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; self.navigationController.interactivePopGestureRecognizer.enabled = YES; [self reload]; }
- (void)reload {
    if (self.loading) return; self.loading = YES;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{
        NSError *error = nil; NSDictionary *result = [AHClient call:@"chat.conversations" params:@{} error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.loading = NO;
            if (result) { self.conversations = result[@"conversations"]; [self.tableView reloadData]; }
            else {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Không tải được hội thoại" message:[error.localizedDescription stringByAppendingString:@"\nSau khi nâng cấp, cần khởi động lại daemon."] preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"Thử lại" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action){ [self reload]; }]];
                [alert addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:nil]];
                if (!self.presentedViewController && self.navigationController.topViewController == self) [self presentViewController:alert animated:YES completion:nil];
            }
        });
    });
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.conversations.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"conversation"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"conversation"];
    NSDictionary *conversation = self.conversations[path.row]; cell.textLabel.text = conversation[@"title"]; cell.textLabel.font=[UIFont systemFontOfSize:AHChatFontSize()]; cell.textLabel.numberOfLines = 2;
    UIButton *star=[UIButton buttonWithType:UIButtonTypeSystem]; star.frame=CGRectMake(0,0,44,44);
    [star setTitle:[conversation[@"pinned"] boolValue]?@"★":@"☆" forState:UIControlStateNormal]; star.titleLabel.font=[UIFont systemFontOfSize:27];
    star.accessibilityLabel=[conversation[@"pinned"] boolValue]?@"Bỏ ghim hội thoại":@"Ghim hội thoại";
    star.accessibilityIdentifier=conversation[@"id"]; [star addTarget:self action:@selector(pin:) forControlEvents:UIControlEventTouchUpInside];
    cell.accessoryView=star;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    AHController *chat = [AHController new]; chat.conversationID = self.conversations[path.row][@"id"];
    [self.navigationController pushViewController:chat animated:YES];
}
- (void)pin:(UIButton *)sender {
    if(self.loading) return;
    NSDictionary *selected=nil; for(NSDictionary *conversation in self.conversations) if([conversation[@"id"] isEqual:sender.accessibilityIdentifier]) selected=conversation;
    if(!selected) return; self.loading=YES;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{
        NSError *error=nil; [AHClient call:@"chat.pin" params:@{@"conversation_id":selected[@"id"],@"pinned":@(![selected[@"pinned"] boolValue])} error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{ self.loading=NO; [self reload]; });
    });
}
- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)path {
    NSDictionary *conversation=self.conversations[path.row];
    UIContextualAction *remove=[UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"Xóa" handler:^(__unused UIContextualAction *action,__unused UIView *view,void (^done)(BOOL)){
        if(self.loading) { done(NO); return; } self.loading=YES;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{
            NSError *error=nil; NSDictionary *result=[AHClient call:@"chat.delete" params:@{@"conversation_id":conversation[@"id"]} error:&error];
            dispatch_async(dispatch_get_main_queue(), ^{
                self.loading=NO;
                if(result && [[NSUserDefaults.standardUserDefaults stringForKey:@"activeConversation"] isEqual:conversation[@"id"]]) [NSUserDefaults.standardUserDefaults removeObjectForKey:@"activeConversation"];
                done(result!=nil); [self reload];
            });
        });
    }];
    UISwipeActionsConfiguration *configuration=[UISwipeActionsConfiguration configurationWithActions:@[remove]]; configuration.performsFirstActionWithFullSwipe=NO; return configuration;
}
- (void)newChat {
    if (self.loading) return; self.loading = YES;
    for (UIBarButtonItem *item in self.navigationItem.rightBarButtonItems) item.enabled = NO;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{
        NSError *error = nil; NSDictionary *result = [AHClient call:@"chat.create" params:@{} error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.loading = NO; for (UIBarButtonItem *item in self.navigationItem.rightBarButtonItems) item.enabled = YES;
            if (result) { AHController *chat = [AHController new]; chat.conversationID = result[@"id"]; [self.navigationController pushViewController:chat animated:YES]; }
            else { self.title = @"Chưa tạo được · thử lại"; [self reload]; }
        });
    });
}
- (void)settings {
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:[AHSettings new]];
    [self presentViewController:navigation animated:YES completion:nil];
}
@end

@interface AHApp : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end
@implementation AHApp
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    AHConversations *list = [[AHConversations alloc] initWithStyle:UITableViewStyleInsetGrouped];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:list];
    NSString *active=[NSUserDefaults.standardUserDefaults stringForKey:@"activeConversation"];
    if(active.length) { AHController *chat=[AHController new]; chat.conversationID=active; [navigation setViewControllers:@[list,chat] animated:NO]; }
    self.window.rootViewController = navigation;
    [self.window makeKeyAndVisible]; return YES;
}
@end
