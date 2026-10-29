#import "AHWebSettings.h"
#import "AHInput.h"
#import "AHClient.h"
#import "AHProfiles.h"
@interface AHWebSettings ()
@property (nonatomic,strong) UISwitch *enabled;
@property (nonatomic,strong) UISwitch *interactive;
@property (nonatomic,strong) AHInput *port;
@property (nonatomic,strong) AHInput *password;
@property (nonatomic,strong) UILabel *status;
@end
@implementation AHWebSettings
- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=@"Webview"; self.tableView.rowHeight=UITableViewAutomaticDimension; self.tableView.estimatedRowHeight=60;
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"Quay lại" style:UIBarButtonItemStylePlain target:self action:@selector(back)];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"Lưu" style:UIBarButtonItemStyleDone target:self action:@selector(save)]; self.navigationItem.rightBarButtonItem.enabled=NO;
    self.enabled=[UISwitch new]; self.interactive=[UISwitch new]; self.port=[AHInput new]; self.port.keyboardType=UIKeyboardTypeNumberPad; self.port.text=@"8765";
    self.password=[AHInput new]; self.password.secureTextEntry=YES; self.password.placeholder=@"Trống = công cộng";
    self.status=[UILabel new]; self.status.numberOfLines=0; self.status.font=[UIFont systemFontOfSize:13]; self.status.text=@"Đang tải trạng thái daemon…";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{ NSError *error=nil; NSDictionary *status=[AHClient call:@"web.status" params:@{} error:&error]; dispatch_async(dispatch_get_main_queue(),^{
        if(status) { self.enabled.on=[status[@"enabled"] boolValue]; self.interactive.on=[status[@"interactive"] boolValue]; self.port.text=[status[@"port"] description]; self.password.placeholder=[status[@"public"] boolValue]?@"Trống = công cộng":@"Nhập lại để giữ bảo vệ; trống = công cộng"; self.navigationItem.rightBarButtonItem.enabled=YES; self.status.text=[NSString stringWithFormat:@"%@ · port %@\n%@",[status[@"enabled"] boolValue]?@"Đang bật":@"Đang tắt",status[@"port"],status[@"error"]]; }
        else self.status.text=[error.localizedDescription stringByAppendingString:@"\nCần restart daemon sau khi nâng cấp."];
        [self.tableView reloadData];
    }); });
}
- (void)back { [self.navigationController popViewControllerAnimated:YES]; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return 5; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section { return @"Mật khẩu trống = CÔNG CỘNG (rủi ro bảo mật): bất kỳ ai kết nối được port đều có thể xem hội thoại và reasoning do provider trả về. Khi bật tương tác, họ cũng có thể gửi/dừng chat.\n\nHTTP: nên dùng Tailscale, mạng tin cậy hoặc SSH tunnel. Mật khẩu đã lưu không hiện lại; nhập lại khi lưu để giữ chế độ có mật khẩu. API key không xuất hiện trên web.\n\nTruy cập http://IP-IPHONE:PORT. Thinking chỉ có nếu provider cung cấp reasoning qua API."; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil]; cell.selectionStyle=UITableViewCellSelectionStyleNone;
    if(path.row==0 || path.row==3) { cell.textLabel.text=path.row==0?@"Bật Webview":@"Cho phép tương tác"; cell.accessoryView=path.row==0?self.enabled:self.interactive; return cell; }
    if(path.row==4) { self.status.translatesAutoresizingMaskIntoConstraints=NO; [cell.contentView addSubview:self.status]; [NSLayoutConstraint activateConstraints:@[[self.status.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:14],[self.status.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-14],[self.status.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:14],[self.status.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-14]]]; return cell; }
    UILabel *label=[UILabel new]; label.text=path.row==1?@"Port":@"Password"; label.font=[UIFont systemFontOfSize:13]; label.textColor=UIColor.secondaryLabelColor;
    UITextField *field=path.row==1?self.port:self.password;
    UIStackView *stack=[[UIStackView alloc] initWithArrangedSubviews:@[label,field]]; stack.axis=UILayoutConstraintAxisVertical; stack.spacing=6; stack.translatesAutoresizingMaskIntoConstraints=NO; [cell.contentView addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[[stack.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:14],[stack.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-14],[stack.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:12],[stack.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-12],[field.heightAnchor constraintEqualToConstant:46]]]; return cell;
}
- (void)save {
    [self.view endEditing:YES]; NSString *digits=self.port.text;
    if(!digits.length || [digits rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location!=NSNotFound || digits.integerValue<1024 || digits.integerValue>65535) { self.status.text=@"Port phải từ 1024 tới 65535."; [self.tableView beginUpdates]; [self.tableView endUpdates]; return; }
    NSDictionary *params=@{@"enabled":@(self.enabled.on),@"port":@(digits.integerValue),@"password":self.password.text ?: @"",@"interactive":@(self.interactive.on),@"profile":AHActiveProfile()}; self.navigationItem.rightBarButtonItem.enabled=NO;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{ NSError *error=nil; NSDictionary *status=[AHClient call:@"web.configure" params:params error:&error]; dispatch_async(dispatch_get_main_queue(),^{
        self.navigationItem.rightBarButtonItem.enabled=YES;
        if(status) { self.enabled.on=[status[@"enabled"] boolValue]; self.status.text=[NSString stringWithFormat:@"%@ · http://IP-IPHONE:%@\n%@ · %@\n%@",self.enabled.on?@"Đã bật":@"Đã tắt",status[@"port"],[status[@"public"] boolValue]?@"CÔNG CỘNG · rủi ro bảo mật":@"Có mật khẩu",[status[@"interactive"] boolValue]?@"Có tương tác":@"Chỉ xem",status[@"error"]]; }
        else self.status.text=error.localizedDescription;
        [self.tableView beginUpdates]; [self.tableView endUpdates];
    }); });
}
@end
