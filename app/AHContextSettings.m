#import "AHContextSettings.h"
#import "AHClient.h"
@interface AHContextSettings ()
@property (nonatomic,strong) NSMutableDictionary *config;
@property BOOL saving;
@end
@implementation AHContextSettings
- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }
- (void)viewDidLoad { [super viewDidLoad]; self.title=@"Context & Memory"; self.config=[@{@"enabled":@NO,@"threshold":@80,@"auto_activate":@NO} mutableCopy]; dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{ NSDictionary *result=[AHClient call:@"context.settings" params:@{} error:nil]; dispatch_async(dispatch_get_main_queue(),^{ if(result) { self.config=[result mutableCopy]; [self.tableView reloadData]; } }); }); }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return 3; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section { return @"Tự compact trước lượt AI khi đạt ngưỡng input. Request compact dùng provider của lượt đó và có thể tính phí. Bật Tự áp dụng để tiếp tục chat sau khi memory qua kiểm tra; nếu tắt, cần xem và Dùng summary trong Context. Lỗi/hủy/restart giữ checkpoint cũ; có thể khôi phục trong Context."; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil]; cell.selectionStyle=UITableViewCellSelectionStyleNone; cell.userInteractionEnabled=!self.saving;
    if(path.row<2) { cell.textLabel.text=path.row==0?@"Tự compact":@"Tự áp dụng memory hợp lệ"; UISwitch *toggle=[UISwitch new]; toggle.tag=path.row; toggle.on=[self.config[path.row==0?@"enabled":@"auto_activate"] boolValue]; [toggle addTarget:self action:@selector(change:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView=toggle; }
    else { cell.textLabel.text=[NSString stringWithFormat:@"Ngưỡng %@%%",self.config[@"threshold"]]; UISlider *slider=[[UISlider alloc] initWithFrame:CGRectMake(0,0,160,40)]; slider.minimumValue=50; slider.maximumValue=95; slider.value=[self.config[@"threshold"] floatValue]; [slider addTarget:self action:@selector(threshold:) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside]; cell.accessoryView=slider; }
    return cell;
}
- (void)change:(UISwitch *)toggle { self.config[toggle.tag==0?@"enabled":@"auto_activate"]=@(toggle.on); [self save]; }
- (void)threshold:(UISlider *)slider { slider.value=MAX(50,MIN(95,roundf(slider.value/5)*5)); self.config[@"threshold"]=@((NSInteger)slider.value); [self save]; }
- (void)save { self.saving=YES; [self.tableView reloadData]; NSDictionary *params=[self.config copy]; dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{ NSError *error=nil; NSDictionary *result=[AHClient call:@"context.configure" params:params error:&error]; dispatch_async(dispatch_get_main_queue(),^{ self.saving=NO; if(result) self.config=[result mutableCopy]; [self.tableView reloadData]; if(error) { UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"Context" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert]; [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]]; [self presentViewController:alert animated:YES completion:nil]; } }); }); }
@end
