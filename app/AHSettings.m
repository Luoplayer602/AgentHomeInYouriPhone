#import "AHSettings.h"
#import "AHInput.h"
#import "AHProfiles.h"
#import "AHProviderConfig.h"
#import "AHClient.h"
#import "AHDisplay.h"
#import "AHWebSettings.h"
static NSString *AHTypeName(NSDictionary *profile) { return [profile[@"type"] isEqual:@"gemini"] ? @"Gemini" : @"OpenAI compatible"; }
static void AHSettingsError(UIViewController *owner,NSString *text) {
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"Agent Home" message:text preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    if(!owner.presentedViewController && owner.view.window) [owner presentViewController:alert animated:YES completion:nil];
}
@interface AHProviderEditor : UITableViewController
@property (nonatomic,copy) NSString *identifier;
@property (nonatomic,copy) NSString *type;
@property (nonatomic,strong) NSArray *fields;
@property (nonatomic,strong) NSArray *labels;
@end
@implementation AHProviderEditor
- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=@"Provider"; self.tableView.rowHeight=UITableViewAutomaticDimension; self.tableView.estimatedRowHeight=100; self.view.backgroundColor=UIColor.systemGroupedBackgroundColor;
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"Quay lại" style:UIBarButtonItemStylePlain target:self action:@selector(back)];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"Lưu" style:UIBarButtonItemStyleDone target:self action:@selector(save)];
    NSDictionary *profile=nil; for(NSDictionary *p in AHProfiles()) if([p[@"id"] isEqual:self.identifier]) profile=p;
    self.type=profile[@"type"] ?: self.type ?: @"compatible"; self.identifier=self.identifier ?: NSUUID.UUID.UUIDString;
    BOOL gemini=[self.type isEqual:@"gemini"];
    self.labels=gemini?@[@"Provider name",@"Model ID",@"Context window tokens (0 = chưa biết)",@"Max output tokens",@"API key"]:@[@"Provider name",@"Base URL",@"Model ID",@"Context window tokens (0 = chưa biết)",@"Max output tokens",@"API key"];
    NSString *limit=[profile[@"max_output_tokens"] description] ?: @"8192", *window=[profile[@"context_window_tokens"] description] ?: @"0";
    NSArray *values=gemini?@[profile[@"name"]?:@"",profile[@"model"]?:@"",window,limit,@""]:@[profile[@"name"]?:@"",profile[@"endpoint"]?:@"",profile[@"model"]?:@"",window,limit,@""];
    NSMutableArray *fields=[NSMutableArray array];
    for(NSUInteger i=0;i<self.labels.count;i++) {
        AHInput *field=[AHInput new]; field.text=values[i]; field.font=[UIFont systemFontOfSize:15];
        field.placeholder=self.labels[i];
        if(i==self.labels.count-1) { field.secureTextEntry=YES; field.placeholder=profile?@"Để trống để giữ key":@"Nhập API key"; }
        if(i==self.labels.count-2 || i==self.labels.count-3) field.keyboardType=UIKeyboardTypeNumberPad;
        if(!gemini && i==1) { field.keyboardType=UIKeyboardTypeURL; field.placeholder=@"https://host/v1"; }
        [fields addObject:field];
    }
    self.fields=fields; self.tableView.keyboardDismissMode=UIScrollViewKeyboardDismissModeInteractive;
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.fields.count; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return [self.type isEqual:@"gemini"]?@"GEMINI":@"OPENAI COMPATIBLE"; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section { return [self.type isEqual:@"gemini"]?@"Dùng Google AI Studio API key. Endpoint Gemini được cấu hình sẵn. Key lưu riêng trong Keychain.":@"Nhập base URL hoặc endpoint chat/completions. Key lưu riêng trong Keychain."; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil]; cell.selectionStyle=UITableViewCellSelectionStyleNone;
    UILabel *label=[UILabel new]; label.text=self.labels[path.row]; label.textColor=UIColor.secondaryLabelColor; label.font=[UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    UIStackView *stack=[[UIStackView alloc] initWithArrangedSubviews:@[label,self.fields[path.row]]]; stack.axis=UILayoutConstraintAxisVertical; stack.spacing=7; stack.translatesAutoresizingMaskIntoConstraints=NO;
    [cell.contentView addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[[stack.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:14],[stack.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-14],[stack.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:12],[stack.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-12],[[(UIView *)self.fields[path.row] heightAnchor] constraintEqualToConstant:46]]];
    return cell;
}
- (void)back { [self.navigationController popViewControllerAnimated:YES]; }
- (void)save {
    NSMutableArray *values=[NSMutableArray array]; for(UITextField *field in self.fields) [values addObject:[field.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @""];
    BOOL gemini=[self.type isEqual:@"gemini"];
    NSString *name=values[0], *model=values[gemini?1:2], *key=values.lastObject;
    NSString *limit=values[values.count-2], *window=values[values.count-3];
    if(!window.length || [window rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location!=NSNotFound || window.integerValue<0 || window.integerValue>2000000) { AHSettingsError(self,@"Context window phải từ 0 tới 2.000.000 token; 0 = chưa biết."); return; }
    if(!limit.length || [limit rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location!=NSNotFound || limit.integerValue<256 || limit.integerValue>32768) { AHSettingsError(self,@"Max output tokens phải từ 256 tới 32768 (tùy giới hạn model)."); return; }
    NSString *error=nil; NSURL *url=AHChatURL(gemini?@"https://generativelanguage.googleapis.com/v1beta/openai/":values[1],&error);
    if(!name.length || !model.length || !url) { AHSettingsError(self,error ?: @"Cần tên provider và model ID."); return; }
    NSDictionary *old=nil; for(NSDictionary *p in AHProfiles()) if([p[@"id"] isEqual:self.identifier]) old=p;
    if(!key.length && !AHReadKey(self.identifier).length) { AHSettingsError(self,@"Cần API key cho provider mới."); return; }
    NSDictionary *profile=@{@"id":self.identifier,@"type":self.type,@"name":name,@"endpoint":url.absoluteString,@"model":model,@"disableStreaming":old[@"disableStreaming"] ?: @NO,@"max_output_tokens":@(limit.integerValue),@"context_window_tokens":@(window.integerValue)};
    if(!AHSaveProfile(profile,key,&error)) { AHSettingsError(self,error); return; }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{ [AHClient call:@"web.profile" params:@{@"profile":AHActiveProfile()} error:nil]; });
    [self.navigationController popToRootViewControllerAnimated:YES];
}
@end
@interface AHProviderTypes : UITableViewController
@end
@implementation AHProviderTypes
- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }
- (void)viewDidLoad { [super viewDidLoad]; self.title=@"Add provider"; self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"Quay lại" style:UIBarButtonItemStylePlain target:self action:@selector(back)]; }
- (void)back { [self.navigationController popViewControllerAnimated:YES]; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return 2; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.text=path.row?@"Gemini":@"OpenAI compatible"; cell.detailTextLabel.text=path.row?@"Google AI Studio · endpoint có sẵn":@"API key, base URL và model tùy chỉnh"; cell.detailTextLabel.textColor=UIColor.secondaryLabelColor; return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path { AHProviderEditor *editor=[AHProviderEditor new]; editor.type=path.row?@"gemini":@"compatible"; [self.navigationController pushViewController:editor animated:YES]; }
@end
@interface AHSavedProviders : UITableViewController
@end
@implementation AHSavedProviders
- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }
- (void)viewDidLoad { [super viewDidLoad]; self.title=@"Saved providers"; self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"Quay lại" style:UIBarButtonItemStylePlain target:self action:@selector(back)]; }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self.tableView reloadData]; }
- (void)back { [self.navigationController popViewControllerAnimated:YES]; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return AHProfiles().count+1; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    if(path.row==0) { cell.textLabel.text=@"＋ Add provider"; cell.textLabel.textColor=UIColor.systemBlueColor; return cell; }
    NSDictionary *profile=AHProfiles()[path.row-1]; cell.textLabel.text=profile[@"name"]; cell.detailTextLabel.text=AHTypeName(profile); cell.detailTextLabel.textColor=UIColor.secondaryLabelColor;
    UIButton *edit=[UIButton buttonWithType:UIButtonTypeSystem]; edit.frame=CGRectMake(0,0,70,44); [edit setTitle:[profile[@"id"] isEqual:AHActiveProfile()[@"id"]]?@"✓ Sửa":@"Sửa" forState:UIControlStateNormal];
    edit.accessibilityIdentifier=profile[@"id"]; [edit addTarget:self action:@selector(edit:) forControlEvents:UIControlEventTouchUpInside]; cell.accessoryView=edit;
    return cell;
}
- (void)edit:(UIButton *)button { AHProviderEditor *editor=[AHProviderEditor new]; editor.identifier=button.accessibilityIdentifier; [self.navigationController pushViewController:editor animated:YES]; }
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    if(path.row==0) { [self.navigationController pushViewController:[AHProviderTypes new] animated:YES]; return; }
    [NSUserDefaults.standardUserDefaults setObject:AHProfiles()[path.row-1][@"id"] forKey:@"activeProvider"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{ [AHClient call:@"web.profile" params:@{@"profile":AHActiveProfile()} error:nil]; });
    [self.navigationController popViewControllerAnimated:YES];
}
@end
@interface AHFontCell : UITableViewCell
@property (nonatomic,strong) UILabel *title;
@property (nonatomic,strong) UILabel *preview;
@property (nonatomic,strong) UISlider *slider;
@property (nonatomic,copy) void (^onChanged)(void);
@property NSInteger presetIndex;
@end
@implementation AHFontCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    if((self=[super initWithStyle:style reuseIdentifier:identifier])) {
        self.selectionStyle=UITableViewCellSelectionStyleNone; self.presetIndex=AHFontPresetIndex();
        self.title=[UILabel new]; self.title.font=[UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
        self.slider=[UISlider new]; self.slider.minimumValue=0; self.slider.maximumValue=AHFontPresets().count-1; self.slider.value=self.presetIndex;
        self.slider.accessibilityLabel=@"Cỡ chữ hội thoại";
        [self.slider addTarget:self action:@selector(snap:) forControlEvents:UIControlEventValueChanged];
        [self.slider addTarget:self action:@selector(snap:) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside|UIControlEventTouchCancel];
        UIView *track=[UIView new]; self.slider.translatesAutoresizingMaskIntoConstraints=NO; [track addSubview:self.slider];
        [NSLayoutConstraint activateConstraints:@[[track.heightAnchor constraintEqualToConstant:36],[self.slider.leadingAnchor constraintEqualToAnchor:track.leadingAnchor constant:16],[self.slider.trailingAnchor constraintEqualToAnchor:track.trailingAnchor constant:-16],[self.slider.centerYAnchor constraintEqualToAnchor:track.centerYAnchor]]];
        UIStackView *ticks=[UIStackView new]; ticks.distribution=UIStackViewDistributionFillEqually;
        for(NSString *name in AHFontPresetNames()) {
            UILabel *tick=[UILabel new]; tick.text=[@"│\n" stringByAppendingString:name]; tick.font=[UIFont systemFontOfSize:11]; tick.textColor=UIColor.secondaryLabelColor; tick.textAlignment=NSTextAlignmentCenter; tick.numberOfLines=2; [ticks addArrangedSubview:tick];
        }
        self.preview=[UILabel new]; self.preview.numberOfLines=0; self.preview.text=@"Xin chào! Đây là cỡ chữ hiển thị trong hội thoại."; self.preview.textColor=UIColor.labelColor;
        UIStackView *stack=[[UIStackView alloc] initWithArrangedSubviews:@[self.title,track,ticks,self.preview]]; stack.axis=UILayoutConstraintAxisVertical; stack.spacing=10; stack.translatesAutoresizingMaskIntoConstraints=NO;
        [self.contentView addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[[stack.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:14],[stack.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-14],[stack.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:16],[stack.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-16]]];
        [self updatePreview];
    }
    return self;
}
- (void)updatePreview {
    self.title.text=[NSString stringWithFormat:@"Cỡ chữ · %@ (%@ pt)",AHFontPresetNames()[self.presetIndex],AHFontPresets()[self.presetIndex]];
    self.preview.font=[UIFont systemFontOfSize:[AHFontPresets()[self.presetIndex] doubleValue]];
    self.slider.accessibilityValue=[NSString stringWithFormat:@"%@, %@ point",AHFontPresetNames()[self.presetIndex],AHFontPresets()[self.presetIndex]];
}
- (void)snap:(UISlider *)slider {
    NSInteger index=MAX(0,MIN((NSInteger)AHFontPresets().count-1,(NSInteger)lroundf(slider.value)));
    slider.value=index;
    if(self.presetIndex==index) return;
    self.presetIndex=index; AHSetFontPreset(index); [self updatePreview]; if(self.onChanged) self.onChanged();
}
@end

@implementation AHSettings
- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }
- (void)viewDidLoad { [super viewDidLoad]; self.title=@"Cài đặt"; self.tableView.rowHeight=UITableViewAutomaticDimension; self.tableView.estimatedRowHeight=70; self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"Đóng" style:UIBarButtonItemStylePlain target:self action:@selector(close)]; }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self.tableView reloadData]; }
- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 4; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section==0?2:1; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return section==0?@"API PROVIDER":section==1?@"HIỂN THỊ":section==2?@"WEBVIEW":@"DEVICE INFO"; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    if(path.section==1) {
        AHFontCell *font=[[AHFontCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        __weak AHSettings *weak=self;
        font.onChanged=^{ [weak.tableView beginUpdates]; [weak.tableView endUpdates]; }; return font;
    }
    UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    if(path.section==2) { cell.textLabel.text=@"Webview"; cell.detailTextLabel.text=@"Port · Password · Tương tác"; return cell; }
    if(path.section==3) { cell.textLabel.text=@"Device info"; return cell; }
    if(path.row==0) { cell.textLabel.text=@"Saved providers"; cell.detailTextLabel.text=AHActiveProfile()[@"name"]; }
    else { cell.textLabel.text=@"Streaming"; cell.selectionStyle=UITableViewCellSelectionStyleNone; UISwitch *toggle=[UISwitch new]; toggle.on=![AHActiveProfile()[@"disableStreaming"] boolValue]; [toggle addTarget:self action:@selector(streamChanged:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView=toggle; }
    return cell;
}
- (void)streamChanged:(UISwitch *)toggle { NSMutableDictionary *profile=[AHActiveProfile() mutableCopy]; profile[@"disableStreaming"]=@(!toggle.on); NSString *error=nil; if(!AHSaveProfile(profile,@"",&error)) AHSettingsError(self,error); }
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    if(path.section==0 && path.row==0) { [self.navigationController pushViewController:[AHSavedProviders new] animated:YES]; return; }
    if(path.section==2) { [self.navigationController pushViewController:[AHWebSettings new] animated:YES]; return; }
    if(path.section!=3) return;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{ NSError *error=nil; NSDictionary *info=[AHClient call:@"system.info" params:@{} error:&error]; NSString *text=info?[NSString stringWithFormat:@"%@\nTrống %.2f GB / %.2f GB\nDaemon UID %@",info[@"os"],[info[@"free_bytes"] doubleValue]/1e9,[info[@"total_bytes"] doubleValue]/1e9,info[@"uid"]]:error.localizedDescription; dispatch_async(dispatch_get_main_queue(),^{ AHSettingsError(self,text); }); });
}
@end
