#import "AHMemorySearch.h"
#import "AHMemory.h"
#import "../core/context/Memory.hpp"
#import "../core/context/Search.hpp"
static NSString *fold(NSString *s) { return [s stringByFoldingWithOptions:NSCaseInsensitiveSearch|NSDiacriticInsensitiveSearch locale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]].lowercaseString; }
NSDictionary *AHMemorySearch(sqlite3 *db,NSString *conversation,NSDictionary *arguments,NSString **error) {
    NSString *query=arguments[@"query"], *category=arguments[@"category"] ?: @"all";
    NSArray *categories=@[@"all",@"goals",@"decisions",@"constraints",@"artifacts",@"facts",@"work_state",@"next_steps",@"permissions",@"history"];
    if(![conversation isKindOfClass:NSString.class] || !conversation.length || ![query isKindOfClass:NSString.class] || !query.length || query.length>200 || ![categories containsObject:category]) { if(error) *error=@"Memory search cần query 1–200 ký tự và category hợp lệ."; return nil; }
    for(NSString *key in arguments) if(![@[@"query",@"category",@"limit"] containsObject:key]) { if(error) *error=@"Memory search có trường không được hỗ trợ."; return nil; }
    id requested=arguments[@"limit"]; if(requested && (![requested isKindOfClass:NSNumber.class] || [requested integerValue]<1 || [requested integerValue]>8)) { if(error) *error=@"Memory search limit phải từ 1 tới 8."; return nil; }
    NSUInteger limit=requested?[requested unsignedIntegerValue]:4;
    NSString *normalized=fold(query); NSMutableArray *words=[NSMutableArray arrayWithArray:[normalized componentsSeparatedByCharactersInSet:NSCharacterSet.alphanumericCharacterSet.invertedSet]];
    if([normalized containsString:@"project"] || [normalized containsString:@"du an"]) [words addObjectsFromArray:@[@"project",@"du an"]];
    if([normalized containsString:@"file"] || [normalized containsString:@"path"] || [normalized containsString:@"artifact"]) [words addObjectsFromArray:@[@"report",@"file",@"path"]];
    if([normalized containsString:@"pending"] || [normalized containsString:@"verified"] || [normalized containsString:@"chua"]) [words addObjectsFromArray:@[@"not done",@"chua",@"not verified"]];
    std::vector<std::string> terms; for(NSString *word in words) if(word.length>=2) terms.push_back(word.UTF8String);
    NSMutableArray *hits=[NSMutableArray array]; NSMutableSet *seen=[NSMutableSet set];
    void (^consider)(NSString *,NSString *,NSString *,NSString *)=^(NSString *sourceID,NSString *role,NSString *text,NSString *section) {
        NSString *lower=fold(text); if(ahmemory::sensitive(lower.UTF8String)) return;
        int rank=ahsearch::score(lower.UTF8String,terms,normalized.UTF8String); if(rank<=0) return;
        NSString *identity=[NSString stringWithFormat:@"%@|%@",sourceID,text]; if([seen containsObject:identity]) return;
        [seen addObject:identity];
        NSString *excerpt=text.length>4096?[text substringToIndex:4096]:text;
        [hits addObject:@{@"source_id":sourceID,@"source_role":role,@"category":section,@"quote":excerpt,@"truncated":@(excerpt.length<text.length),@"score":@(rank)}];
        [hits sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){ NSComparisonResult rank=[b[@"score"] compare:a[@"score"]]; if(rank!=NSOrderedSame) return rank; long long newer=[b[@"source_id"] longLongValue], older=[a[@"source_id"] longLongValue]; return newer>older?NSOrderedAscending:newer<older?NSOrderedDescending:NSOrderedSame; }];
        if(hits.count>limit) [hits removeLastObject];
    };
    sqlite3_stmt *s=NULL; NSString *summary=@""; sqlite3_int64 end=0;
    if(sqlite3_prepare_v2(db,"SELECT summary,end_id FROM compactions WHERE conversation_id=? AND state='active' LIMIT 1",-1,&s,NULL)==SQLITE_OK) {
        sqlite3_bind_text(s,1,conversation.UTF8String,-1,SQLITE_TRANSIENT);
        if(sqlite3_step(s)==SQLITE_ROW) { summary=@((const char *)sqlite3_column_text(s,0)); end=sqlite3_column_int64(s,1); }
    } sqlite3_finalize(s); s=NULL;
    id root=[NSJSONSerialization JSONObjectWithData:[summary dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    if([root isKindOfClass:NSDictionary.class]) {
        for(NSString *key in @[@"required_evidence",@"goals",@"decisions",@"constraints",@"artifacts",@"facts",@"work_state",@"next_steps",@"permissions"]) {
            id records=root[key]; if(![records isKindOfClass:NSArray.class]) continue;
            for(id record in records) if(([category isEqual:@"all"] || [category isEqual:key] || [key isEqual:@"required_evidence"] || ([record isKindOfClass:NSDictionary.class] && [record[@"categories"] isKindOfClass:NSArray.class] && [record[@"categories"] containsObject:category])) && [record isKindOfClass:NSDictionary.class] && [record[@"quote"] isKindOfClass:NSString.class] && [record[@"source_id"] isKindOfClass:NSString.class]) consider(record[@"source_id"],record[@"source_role"] ?: @"memory",record[@"quote"],key);
        }
    } else if(summary.length && ![category isEqual:@"history"]) consider(@"prior",@"memory",summary,@"legacy");
    NSUInteger scanned=0, bytes=0; BOOL capped=NO;
    if((end>0) && ([category isEqual:@"all"] || [category isEqual:@"history"]) && sqlite3_prepare_v2(db,"SELECT id,role,content FROM messages WHERE conversation_id=? AND id<=? ORDER BY id DESC",-1,&s,NULL)==SQLITE_OK) {
        sqlite3_bind_text(s,1,conversation.UTF8String,-1,SQLITE_TRANSIENT); sqlite3_bind_int64(s,2,end);
        while(sqlite3_step(s)==SQLITE_ROW) {
            bytes+=sqlite3_column_bytes(s,2); if(++scanned>10000 || bytes>8*1024*1024) { capped=YES; break; }
            @autoreleasepool { consider([@(sqlite3_column_int64(s,0)) description],@((const char *)sqlite3_column_text(s,1)),@((const char *)sqlite3_column_text(s,2)),@"history"); }
        }
    } sqlite3_finalize(s);
    return @{@"results":hits,@"untrusted":@YES,@"verification":@"source_reports_only",@"scope":@"active memory and archived prefix in this conversation",@"scan_capped":@(capped)};
}
