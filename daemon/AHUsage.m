#import "AHUsage.h"
#import "../app/AHProviderConfig.h"
static NSString *key(NSDictionary *profile) { return [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:@[profile[@"id"] ?: @"",(AHChatURL(profile[@"endpoint"] ?: @"",NULL).absoluteString ?: profile[@"endpoint"] ?: @""),profile[@"model"] ?: @""] options:0 error:nil] encoding:NSUTF8StringEncoding]; }
static long long count(id value) { return [value isKindOfClass:NSNumber.class]?MAX(0,MIN(100000000,[value longLongValue])):0; }
void AHUsageRecord(sqlite3 *db,NSString *task,NSInteger round,NSDictionary *profile,NSDictionary *usage,NSUInteger estimated) {
    if(![usage isKindOfClass:NSDictionary.class]) return;
    long long input=count(usage[@"prompt_tokens"] ?: usage[@"input_tokens"]), output=count(usage[@"completion_tokens"] ?: usage[@"output_tokens"]);
    if(!input) return;
    sqlite3_stmt *s=NULL;
    if(sqlite3_prepare_v2(db,"INSERT OR REPLACE INTO request_usage(task_id,round,profile_key,input_tokens,output_tokens,estimated_tokens,usage) VALUES (?,?,?,?,?,?,?)",-1,&s,NULL)==SQLITE_OK) {
        NSString *json=[[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:usage options:0 error:nil] encoding:NSUTF8StringEncoding];
        sqlite3_bind_text(s,1,task.UTF8String,-1,SQLITE_TRANSIENT); sqlite3_bind_int(s,2,(int)round); sqlite3_bind_text(s,3,key(profile).UTF8String,-1,SQLITE_TRANSIENT); sqlite3_bind_int64(s,4,input); sqlite3_bind_int64(s,5,output); sqlite3_bind_int64(s,6,(sqlite3_int64)estimated); sqlite3_bind_text(s,7,json.UTF8String,-1,SQLITE_TRANSIENT); sqlite3_step(s);
    } sqlite3_finalize(s);
}
NSDictionary *AHUsageStats(sqlite3 *db,NSDictionary *profile) {
    sqlite3_stmt *s=NULL; NSMutableDictionary *result=[NSMutableDictionary dictionaryWithDictionary:@{@"requests":@0,@"input_total":@0,@"output_total":@0,@"peak_input":@0,@"peak_combined":@0,@"calibration_factor":@1,@"capacity_note":@"Peak usage là mức đã quan sát, không xác nhận giới hạn tối đa của model."}];
    if(sqlite3_prepare_v2(db,"SELECT count(*),coalesce(sum(input_tokens),0),coalesce(sum(output_tokens),0),coalesce(max(input_tokens),0),coalesce(max(input_tokens+output_tokens),0),coalesce(max(input_tokens*1.0/max(1,estimated_tokens)),0) FROM request_usage WHERE profile_key=?",-1,&s,NULL)==SQLITE_OK) {
        sqlite3_bind_text(s,1,key(profile).UTF8String,-1,SQLITE_TRANSIENT);
        if(sqlite3_step(s)==SQLITE_ROW) {
            NSArray *names=@[@"requests",@"input_total",@"output_total",@"peak_input",@"peak_combined"];
            for(int i=0;i<5;i++) result[names[i]]=@(sqlite3_column_int64(s,i));
            result[@"calibration_factor"]=@(MAX(1.0,sqlite3_column_double(s,5)*1.1));
        }
    } sqlite3_finalize(s); return result;
}
double AHUsageFactor(sqlite3 *db,NSDictionary *profile) { return [AHUsageStats(db,profile)[@"calibration_factor"] doubleValue]; }
