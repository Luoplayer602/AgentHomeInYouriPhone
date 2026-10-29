#import <UIKit/UIKit.h>
#import <Security/Security.h>
#import "AHClient.h"
#import "AHProviderConfig.h"
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
@property (nonatomic, strong) NSMutableString *draft;
@property NSUInteger runID;
@property BOOL running;
@property UITextField *input;
@property UIButton *sendButton;
@property NSMutableArray *messages;
@property BOOL busy;
@property (nonatomic,strong) UIButton *contextButton;
@property NSUInteger historyCount;
@property (nonatomic,strong) NSTimer *pollTimer;
@property BOOL polling;
@property NSTimeInterval lastPoll;
@property (nonatomic,copy) NSString *aiTaskID;
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
        dispatch_async(dispatch_get_main_queue(), ^{ [self setWorking:NO]; if (result) { [self.messages addObjectsFromArray:result[@"messages"]]; self.historyCount=[result[@"total_messages"] unsignedIntegerValue]; [self render]; [self poll]; } else [self show:error.localizedDescription]; });
    });
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.input.font=[UIFont systemFontOfSize:AHChatFontSize()];
    [self render];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{ [AHClient call:@"web.profile" params:@{@"profile":AHActiveProfile()} error:nil]; });
    [self startPolling];
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
    if (self.busy && !self.running) return;
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
    self.navigationItem.leftBarButtonItem.enabled = !working || self.running;
    for (UIBarButtonItem *item in self.navigationItem.rightBarButtonItems) item.enabled = !working;
    self.navigationController.interactivePopGestureRecognizer.enabled = !working || self.running;
    self.busy = working; self.sendButton.enabled = !working || self.running; self.input.enabled = !working;
    [self.sendButton setTitle:(working && self.running) ? @"Dừng" : @"Gửi" forState:UIControlStateNormal];
    self.title = @"Agent Home";
    if (!working && [self.statusLabel.text isEqual:@"Đang tải hội thoại…"]) self.statusLabel.text = @"Sẵn sàng.";
}
- (void)send {
    if(self.busy) { [self stop]; return; }
    NSString *text=[self.input.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if(!text.length) return; if(text.length>8000) { [self show:@"Tin nhắn tối đa 8.000 ký tự."]; return; }
    NSDictionary *profile=AHActiveProfile();
    if(![profile[@"endpoint"] length] || !AHReadKey(profile[@"id"]).length) { [self settings]; return; }
    ++self.runID; self.running=NO; [self setWorking:YES]; NSString *identifier=NSUUID.UUID.UUIDString;
    // Keep submission ID stable until its outcome is known, making retry safe.
    NSDictionary *request=@{@"id":identifier,@"conversation_id":self.conversationID,@"text":text,@"profile":profile};
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
        NSError *error=nil; NSDictionary *result=[AHClient call:@"ai.submit" params:request error:&error];
        if(!result) result=[AHClient call:@"ai.submit" params:request error:&error];
        dispatch_async(dispatch_get_main_queue(),^{
            if(result) { self.aiTaskID=result[@"id"]; self.input.text=@""; self.running=YES; [self setWorking:YES]; [self poll]; }
            else { [self setWorking:NO]; [self show:error.localizedDescription]; }
        });
    });
}
- (void)startPolling {
    [self.pollTimer invalidate]; self.lastPoll=0; __weak AHController *weak=self;
    self.pollTimer=[NSTimer scheduledTimerWithTimeInterval:0.4 repeats:YES block:^(__unused NSTimer *timer){ [weak poll]; }];
    [self poll];
}
- (void)viewWillDisappear:(BOOL)animated { [super viewWillDisappear:animated]; [self.pollTimer invalidate]; self.pollTimer=nil; }
- (void)poll {
    if(self.polling || (self.busy && !self.running)) return;
    NSTimeInterval now=NSDate.timeIntervalSinceReferenceDate;
    if(!self.running && now-self.lastPoll<2) return; self.lastPoll=now; self.polling=YES; NSUInteger generation=self.runID;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
        NSError *error=nil; NSDictionary *snapshot=[AHClient call:@"ai.snapshot" params:@{@"conversation_id":self.conversationID} error:&error];
        NSDictionary *history=snapshot?[AHClient call:@"chat.list" params:@{@"conversation_id":self.conversationID} error:&error]:nil;
        dispatch_async(dispatch_get_main_queue(),^{
            self.polling=NO; if(self.runID!=generation) return;
            if(!snapshot || !history) { self.statusLabel.text=error.localizedDescription ?: @"Mất kết nối daemon"; return; }
            BOOL changed=![self.messages isEqual:history[@"messages"]];
            self.messages=[history[@"messages"] mutableCopy]; self.historyCount=[history[@"total_messages"] unsignedIntegerValue];
            NSString *state=snapshot[@"state"]; BOOL active=[@[@"queued",@"running"] containsObject:state ?: @""];
            NSString *partial=active?snapshot[@"partial"]:@""; if(![self.draft isEqual:partial]) changed=YES;
            self.draft=[(partial ?: @"") mutableCopy]; self.aiTaskID=snapshot[@"id"];
            self.running=active; [self setWorking:active];
            self.statusLabel.text=active?([state isEqual:@"queued"]?@"Đang chờ daemon…":([snapshot[@"reasoning"] length] && ![snapshot[@"partial"] length]?@"Provider đang reasoning…":@"AI đang chạy trong daemon…")) : ([state isEqual:@"failed"]?snapshot[@"result"]:@"Sẵn sàng · daemon");
            if(changed) [self render];
        });
    });
}
- (void)stop {
    if(!self.aiTaskID.length) return; NSString *identifier=self.aiTaskID;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
        NSError *error=nil; [AHClient call:@"ai.cancel" params:@{@"id":identifier} error:&error];
        dispatch_async(dispatch_get_main_queue(),^{ if(error) [self show:error.localizedDescription]; [self poll]; });
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
