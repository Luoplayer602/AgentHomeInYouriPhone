#import "AHContextView.h"
#import "AHClient.h"
#import "AHProfiles.h"
@interface AHContextView ()
@property (nonatomic,strong) NSDictionary *snapshot;
@property (nonatomic,strong) NSTimer *timer;
@property BOOL loading;
@end
@implementation AHContextView
- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }
- (void)viewDidLoad { [super viewDidLoad]; self.title=@"Context"; self.snapshot=@{}; self.tableView.rowHeight=UITableViewAutomaticDimension; self.tableView.estimatedRowHeight=100; self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"Đóng" style:UIBarButtonItemStylePlain target:self action:@selector(close)]; }
- (void)viewDidAppear:(BOOL)animated { [super viewDidAppear:animated]; [self refresh]; __weak AHContextView *weak=self; self.timer=[NSTimer scheduledTimerWithTimeInterval:2 repeats:YES block:^(__unused NSTimer *timer){ [weak refresh]; }]; }
- (void)viewWillDisappear:(BOOL)animated { [super viewWillDisappear:animated]; [self.timer invalidate]; self.timer=nil; }
- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)show:(NSString *)text { if(self.presentedViewController || !self.view.window) return; UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Context" message:text preferredStyle:UIAlertControllerStyleAlert]; [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]]; [self presentViewController:a animated:YES completion:nil]; }
- (void)refresh {
    if(self.loading) return; self.loading=YES;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{ NSError *error=nil; NSDictionary *snapshot=[AHClient call:@"context.status" params:@{@"conversation_id":self.conversationID,@"profile":AHActiveProfile()} error:&error]; dispatch_async(dispatch_get_main_queue(),^{ self.loading=NO; if(snapshot) { if(![snapshot isEqual:self.snapshot]) { self.snapshot=snapshot; [self.tableView reloadData]; } } else { [self.timer invalidate]; [self show:error.localizedDescription]; } }); });
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return 7; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section { return @"Compact tạo request API có tính phí theo provider. Summary là dữ liệu tham khảo, không cấp quyền công cụ. Giữ ít nhất 4 tin gần nhất; lịch sử gốc không bị xóa. Auto-compact chưa bật. Chỉ chọn Dùng summary sau khi xem bản tóm tắt. Bỏ summary trở về dùng lịch sử gần nhất."; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil]; cell.textLabel.numberOfLines=0; cell.textLabel.font=[UIFont systemFontOfSize:14];
    NSDictionary *active=self.snapshot[@"active"],*latest=self.snapshot[@"latest"];
    if(path.row==0) {
        NSString *usage=self.snapshot[@"usage"][@"usage"]; id measured=usage?[NSJSONSerialization JSONObjectWithData:[usage dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil]:nil;
        cell.textLabel.text=[NSString stringWithFormat:@"Ngân sách app: %@ / %@ ký tự\nBao gồm summary + tin gần nhất, chưa gồm system/tools.\nWindow model do bạn khai báo: %@ token (0 = chưa biết)\nOutput dự phòng: %@ token\nInput ước lượng gồm system + tool schema: %@ token (bytes UTF-8 / 4; chưa gồm tin đang gõ, không phải tokenizer)\nTin sau summary ngoài lượt gửi: %@\nUsage thực API chat gần nhất: %@",self.snapshot[@"characters"] ?: @0,self.snapshot[@"budget"] ?: @16000,self.snapshot[@"window_tokens"] ?: @0,self.snapshot[@"output_tokens"] ?: @8192,self.snapshot[@"estimated_input_tokens"] ?: @0,self.snapshot[@"omitted_recent"] ?: @0,measured ?: @"Provider chưa trả usage; chưa đo token chính xác"];
        cell.selectionStyle=UITableViewCellSelectionStyleNone;
    } else if(path.row==1) { cell.textLabel.text=[NSString stringWithFormat:@"Summary đang dùng\n%@",active[@"summary"] ?: @"Chưa có"]; cell.selectionStyle=UITableViewCellSelectionStyleNone; }
    else if(path.row==2) { cell.textLabel.text=[NSString stringWithFormat:@"Snapshot: %@\nNguồn tới message %@ · %@ → %@ ký tự\n%@\n%@",latest[@"state"] ?: @"chưa có",latest[@"end_id"] ?: @"—",latest[@"before_chars"] ?: @0,latest[@"after_chars"] ?: @0,latest[@"summary"] ?: @"",latest[@"error"] ?: @""]; cell.selectionStyle=UITableViewCellSelectionStyleNone; }
    else { cell.textLabel.text=@[@"Compact thủ công",@"Dùng summary đã xem",@"Bỏ snapshot chờ / hủy compact",@"Bỏ toàn bộ summary"][path.row-3]; cell.textLabel.textColor=path.row>=5?UIColor.systemRedColor:UIColor.systemBlueColor; }
    if((path.row==3 && [@[@"running",@"ready"] containsObject:latest[@"state"] ?: @""]) || (path.row==4 && ![latest[@"state"] isEqual:@"ready"])) { cell.userInteractionEnabled=NO; cell.textLabel.textColor=UIColor.tertiaryLabelColor; }
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES]; if(path.row<3 || self.loading) return;
    NSString *method=path.row==3?@"context.compact":path.row==4?@"context.activate":path.row==5?@"context.discard":@"context.drop";
    NSDictionary *params=@{@"conversation_id":self.conversationID,@"profile":AHActiveProfile(),@"id":self.snapshot[@"latest"][@"id"] ?: @""}; self.loading=YES;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{ NSError *error=nil; [AHClient call:method params:params error:&error]; dispatch_async(dispatch_get_main_queue(),^{ self.loading=NO; if(error) [self show:error.localizedDescription]; [self refresh]; }); });
}
@end
