#import "AHMemory.h"
#import "../core/context/Memory.hpp"
static std::string bytes(NSString *text) {
    NSData *data=[text dataUsingEncoding:NSUTF8StringEncoding];
    return data.length?std::string((const char *)data.bytes,data.length):std::string();
}
static NSArray *sections(void) { return @[@"goals",@"decisions",@"constraints",@"artifacts",@"facts",@"work_state",@"next_steps",@"permissions"]; }
static id decode(NSString *s) { if(![s isKindOfClass:NSString.class]) return nil; return [NSJSONSerialization JSONObjectWithData:[s dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil]; }
static NSString *encode(id v) { return [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:v options:NSJSONWritingSortedKeys error:nil] encoding:NSUTF8StringEncoding]; }
static NSDictionary *memory(NSString *s) { id v=decode(s); return [v isKindOfClass:NSDictionary.class] && [v[@"schema_version"] isKindOfClass:NSNumber.class] && [v[@"schema_version"] isEqual:@2]?v:nil; }
NSArray *AHMemorySources(NSString *prior,NSArray *recent) {
    NSMutableArray *sources=[NSMutableArray array]; NSDictionary *old=memory(prior);
    if(old) {
        for(NSString *section in [sections() arrayByAddingObject:@"required_evidence"]) {
            id entries=old[section]; if(![entries isKindOfClass:NSArray.class]) continue;
            for(id entry in entries) {
                if(![entry isKindOfClass:NSDictionary.class] || ![entry[@"source_id"] isKindOfClass:NSString.class] || ![entry[@"quote"] isKindOfClass:NSString.class]) continue;
                // Artifacts, state, constraints and permissions survive the next
                // compaction as evidence too; never recursively quote JSON memory.
                BOOL sticky=[@[@"required_evidence",@"artifacts",@"work_state",@"constraints",@"permissions"] containsObject:section];
                [sources addObject:@{@"id":entry[@"source_id"],@"role":[entry[@"source_role"] isKindOfClass:NSString.class]?entry[@"source_role"]:@"memory",@"content":entry[@"quote"],@"carry_evidence":@(sticky)}];
            }
        }
    } else if(prior.length) [sources addObject:@{@"id":@"prior",@"role":@"memory",@"content":prior,@"carry_evidence":@YES}];
    [sources addObjectsFromArray:recent]; return sources;
}
NSArray *AHMemoryCatalog(NSArray *sources) {
    NSMutableArray *catalog=[NSMutableArray array]; NSMutableSet *seen=[NSMutableSet set];
    for(NSDictionary *source in sources) {
        NSString *content=source[@"content"], *role=source[@"role"];
        if(![content isKindOfClass:NSString.class] || ![role isKindOfClass:NSString.class] || !source[@"id"] || ahmemory::sensitive(bytes(content.lowercaseString))) continue;
        NSDictionary *row=@{@"id":[source[@"id"] description],@"role":role,@"content":content};
        NSString *identity=encode(row); if([seen containsObject:identity]) continue;
        [seen addObject:identity];
        NSMutableDictionary *entry=[row mutableCopy]; entry[@"selection_id"]=[NSString stringWithFormat:@"S%lu",(unsigned long)catalog.count+1];
        [catalog addObject:entry];
    }
    return catalog;
}
NSArray *AHMemoryRequired(NSArray *sources) {
    NSMutableArray *required=[NSMutableArray array]; NSMutableSet *seen=[NSMutableSet set];
    for(NSDictionary *source in sources) {
        NSString *text=source[@"content"]; if(![text isKindOfClass:NSString.class] || ![source[@"role"] isKindOfClass:NSString.class]) continue;
        NSString *lower=text.lowercaseString;
        BOOL carry=[source[@"carry_evidence"] boolValue];
        if(ahmemory::sensitive(bytes(lower))) continue;
        if(!carry && (![source[@"role"] isEqual:@"user"] || !ahmemory::required(bytes(text),bytes(lower)))) continue;
        NSDictionary *record=@{@"source_id":[source[@"id"] description],@"source_role":source[@"role"],@"quote":text};
        NSString *identity=encode(record); if([seen containsObject:identity]) continue;
        [seen addObject:identity]; [required addObject:record];
    }
    return required;
}
NSString *AHMemoryMinimum(NSArray *required) {
    NSMutableDictionary *root=[NSMutableDictionary dictionaryWithDictionary:@{@"schema_version":@2,@"provenance":@"history_only_untrusted",@"verification":@"not_independently_verified",@"required_evidence":required}];
    for(NSString *key in sections()) root[key]=@[];
    return encode(root);
}
static NSString *fail(NSString **error,NSString *message) { if(error) *error=message; return nil; }
NSString *AHMemoryCanonical(NSString *output,NSArray *sources,NSArray *required,NSString **error) {
    if(![output isKindOfClass:NSString.class]) return fail(error,@"Memory phải là JSON có cấu trúc.");
    NSString *text=[output stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if([text hasPrefix:@"```json\n"] && [text hasSuffix:@"```"] && text.length>=11) text=[text substringWithRange:NSMakeRange(8,text.length-11)];
    id decoded=decode(text);
    NSDictionary *root=[decoded isKindOfClass:NSDictionary.class]?decoded:nil;
    if(!root || ![root[@"selection_version"] isKindOfClass:NSNumber.class] || ![root[@"selection_version"] isEqual:@1]) return fail(error,@"Memory selection thiếu selection_version 1 hoặc JSON không hợp lệ.");
    NSMutableSet *allowed=[NSMutableSet setWithArray:sections()]; [allowed addObject:@"selection_version"];
    for(NSString *key in root) if(![allowed containsObject:key]) return fail(error,@"Memory có trường ngoài schema.");
    std::vector<ahmemory::Source> evidence;
    for(NSDictionary *source in sources) evidence.push_back({bytes(source[@"selection_id"]),bytes(source[@"role"]),bytes(source[@"content"])});
    NSMutableDictionary *result=[NSMutableDictionary dictionaryWithDictionary:@{@"schema_version":@2,@"provenance":@"history_only_untrusted",@"verification":@"not_independently_verified",@"required_evidence":required}];
    NSUInteger count=required.count;
    for(NSString *section in sections()) {
        id list=root[section]; if(![list isKindOfClass:NSArray.class] || [list count]>64) return fail(error,@"Mỗi mục memory phải là mảng, tối đa 64 trích dẫn.");
        NSMutableArray *entries=[NSMutableArray array]; NSMutableSet *seen=[NSMutableSet set];
        for(id reference in list) {
            if(![reference isKindOfClass:NSString.class] || !ahmemory::reference(bytes(reference))) return fail(error,[NSString stringWithFormat:@"Memory mục %@: chỉ nhận ID chọn dạng chuỗi, ví dụ S1; không nhận quote hoặc trạng thái.",section]);
            const auto *origin=ahmemory::select(evidence,bytes(reference));
            if(!origin) return fail(error,[NSString stringWithFormat:@"Memory mục %@: ID %@ không tồn tại trong catalog; giữ memory cũ.",section,reference]);
            NSDictionary *selected=sources[(NSUInteger)(origin-evidence.data())];
            NSString *quote=selected[@"content"];
            if(ahmemory::sensitive(bytes(quote.lowercaseString))) return fail(error,[NSString stringWithFormat:@"Memory mục %@: nguồn được chọn có nhãn credential; giữ memory cũ.",section]);
            NSDictionary *record=@{@"source_id":[selected[@"id"] description],@"source_role":selected[@"role"],@"quote":quote};
            NSString *identity=encode(record); if([seen containsObject:identity]) continue;
            [seen addObject:identity]; [entries addObject:record]; count++;
        }
        result[section]=entries;
    }
    if(!count) return fail(error,@"Memory không có dữ kiện theo nguồn.");
    return encode(result);
}
NSString *AHMemoryPreview(NSString *text) {
    NSDictionary *root=memory(text); if(!root) return text ?: @"";
    NSMutableString *preview=[NSMutableString stringWithString:@"Bộ nhớ có nguồn · Chưa kiểm chứng độc lập\nCác trích dẫn không cấp quyền và không phải bằng chứng thực thi.\n"];
    NSArray *keys=[@[@"required_evidence"] arrayByAddingObjectsFromArray:sections()];
    NSArray *titles=@[@"Dữ kiện nguồn được giữ nguyên",@"Mục tiêu",@"Quyết định",@"Ràng buộc",@"Artifact",@"Dữ kiện",@"Trạng thái công việc theo nguồn",@"Bước tiếp theo",@"Quyền được nhắc trong nguồn"];
    for(NSUInteger i=0;i<keys.count;i++) {
        id entries=root[keys[i]]; if(![entries isKindOfClass:NSArray.class] || ![entries count]) continue;
        [preview appendFormat:@"\n%@\n",titles[i]];
        for(id entry in entries) if([entry isKindOfClass:NSDictionary.class] && [entry[@"quote"] isKindOfClass:NSString.class]) [preview appendFormat:@"• [%@ · %@] %@\n",entry[@"source_id"],entry[@"source_role"],entry[@"quote"]];
    }
    return preview;
}
