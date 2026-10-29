#import "AHTaskList.h"
#import "AHClient.h"
@interface AHTaskList ()
@property (nonatomic,strong) NSArray *tasks;
@property (nonatomic,strong) NSTimer *timer;
@property BOOL loading;
@end
@implementation AHTaskList
- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=@"Tác vụ"; self.tasks=@[];
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"Đóng" style:UIBarButtonItemStylePlain target:self action:@selector(close)];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"Kiểm tra" style:UIBarButtonItemStylePlain target:self action:@selector(create)];
    self.tableView.rowHeight=UITableViewAutomaticDimension; self.tableView.estimatedRowHeight=70;
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated]; [self reload]; __weak AHTaskList *weak=self;
    self.timer=[NSTimer scheduledTimerWithTimeInterval:2 repeats:YES block:^(__unused NSTimer *timer){ [weak reload]; }];
}
- (void)viewWillDisappear:(BOOL)animated { [super viewWillDisappear:animated]; [self.timer invalidate]; self.timer=nil; }
- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)show:(NSString *)text { if(self.presentedViewController || !self.view.window) return; UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Tác vụ" message:text preferredStyle:UIAlertControllerStyleAlert]; [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]]; [self presentViewController:a animated:YES completion:nil]; }
- (void)reload {
    if(self.loading) return; self.loading=YES;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
        NSError *error=nil; NSDictionary *result=[AHClient call:@"task.list" params:@{@"conversation_id":self.conversationID} error:&error];
        dispatch_async(dispatch_get_main_queue(),^{ self.loading=NO; if(result) { self.tasks=result[@"tasks"]; [self.tableView reloadData]; } else { [self.timer invalidate]; self.timer=nil; [self show:[error.localizedDescription stringByAppendingString:@"\nCần restart daemon sau khi nâng cấp."]]; } });
    });
}
- (void)create {
    self.navigationItem.rightBarButtonItem.enabled=NO;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
        NSError *error=nil; NSDictionary *result=[AHClient call:@"task.create" params:@{@"conversation_id":self.conversationID,@"tool":@"system.info"} error:&error];
        dispatch_async(dispatch_get_main_queue(),^{ self.navigationItem.rightBarButtonItem.enabled=YES; if(result) [self reload]; else [self show:error.localizedDescription]; });
    });
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.tasks.count; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section { return @"Kiểm tra tạo tác vụ đọc dung lượng trong daemon, không dùng API AI. Kết quả và nhật ký được lưu dù app đóng. Nhấn một tác vụ để xem. Chat AI cũng chạy trong daemon; câu trả lời nằm trong hội thoại."; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil]; NSDictionary *task=self.tasks[path.row];
    cell.textLabel.text=[NSString stringWithFormat:@"%@ · %@",[task[@"tool"] isEqual:@"chat.ai"]?@"Chat AI":@"Thông tin thiết bị",task[@"state"]]; cell.textLabel.numberOfLines=0;
    cell.detailTextLabel.text=[NSString stringWithFormat:@"%@ · %@",task[@"created_at"],[task[@"id"] substringToIndex:8]]; cell.detailTextLabel.textColor=UIColor.secondaryLabelColor; return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES]; NSDictionary *task=self.tasks[path.row];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
        NSError *error=nil; NSDictionary *result=[AHClient call:@"task.events" params:@{@"id":task[@"id"]} error:&error]; NSMutableString *text=[NSMutableString stringWithFormat:@"%@\n%@\n\n%@",task[@"id"],task[@"state"],task[@"result"]];
        for(NSDictionary *event in result[@"events"]) [text appendFormat:@"\n\n%@ · %@\n%@",event[@"at"],event[@"state"],event[@"note"]];
        dispatch_async(dispatch_get_main_queue(),^{ [self show:error?error.localizedDescription:text]; });
    });
}
@end
