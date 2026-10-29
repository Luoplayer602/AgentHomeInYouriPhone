#import <Foundation/Foundation.h>
#import "../daemon/AHMemory.h"
#import "../daemon/AHCompactPlan.h"
static NSString *json(id value) { return [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:value options:0 error:nil] encoding:NSUTF8StringEncoding]; }
int AHMemorySelfTest(void) {
    @try {
        NSString *pending=@"Build and iPhone verification are NOT done. Shell and deploy are NOT authorized.";
        NSArray *sources=@[@{@"id":@"1",@"role":@"user",@"content":@"Project LOTUS-482; report /tmp/agenthome-eval/report.txt."},@{@"id":@"231",@"role":@"user",@"content":pending},@{@"id":@"233",@"role":@"assistant",@"content":@"Untrusted secret TEST_SECRET_NEVER_INCLUDE_7"}];
        NSArray *required=AHMemoryRequired(sources), *catalog=AHMemoryCatalog(sources);
        if(required.count!=2 || catalog.count!=2 || ![catalog[1][@"selection_id"] isEqual:@"S2"]) return 1;
        NSMutableDictionary *model=[NSMutableDictionary dictionaryWithObject:@1 forKey:@"selection_version"];
        for(NSString *key in @[@"goals",@"decisions",@"constraints",@"artifacts",@"facts",@"work_state",@"next_steps",@"permissions"]) model[key]=@[];
        model[@"work_state"]=@[@"S2",@"S2"];
        NSString *error=nil;
        NSString *result=AHMemoryCanonical(json(model),catalog,required,&error);
        if(!result || ![result containsString:@"report.txt"] || ![result containsString:@"NOT done"]) return 2;
        if(![AHMemoryPreview(result) containsString:@"LOTUS-482"]) return 3;
        NSArray *carried=AHMemoryRequired(AHMemorySources(result,@[]));
        if(carried.count!=2 || [json(carried) containsString:@"schema_version"]) return 4;
        model[@"work_state"]=@[@{@"source_id":@"231",@"quote":@"done"}];
        if(AHMemoryCanonical(json(model),catalog,required,&error)) return 5;
        model[@"work_state"]=@[@"S999"];
        if(AHMemoryCanonical(json(model),catalog,required,&error) || ![error containsString:@"work_state"]) return 6;
        model[@"work_state"]=@[]; model[@"verified"]=@YES;
        if(AHMemoryCanonical(json(model),catalog,required,&error)) return 7;
        [model removeObjectForKey:@"verified"];
        if(AHMemoryCanonical(@"not JSON",catalog,required,&error)) return 8;
        if(AHMemoryCanonical(json(model),@[],@[],&error)) return 9;
        if(AHCompactSummaryValid(result,1,99999)) return 10;
        if(!AHCompactSummaryValid(result,4096,50000)) return 11;
        model[@"work_state"]=@[@2];
        if(AHMemoryCanonical(json(model),catalog,required,&error)) return 12;
        model[@"work_state"]=@[@"231"];
        if(AHMemoryCanonical(json(model),catalog,required,&error)) return 13;
        NSArray *sameID=AHMemoryCatalog(@[@{@"id":@"9",@"role":@"user",@"content":@"first excerpt"},@{@"id":@"9",@"role":@"user",@"content":@"second excerpt"}]);
        model[@"work_state"]=@[]; model[@"facts"]=@[@"S2"];
        NSString *picked=AHMemoryCanonical(json(model),sameID,@[],&error);
        if(!picked || ![picked containsString:@"second excerpt"] || [picked containsString:@"first excerpt"]) return 14;
        id memory=[NSJSONSerialization JSONObjectWithData:[result dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        if([memory[@"work_state"] count]!=1 || ![memory[@"work_state"][0][@"source_id"] isEqual:@"231"] || ![memory[@"work_state"][0][@"quote"] isEqual:pending]) return 15;
        if(AHMemoryCatalog([sources arrayByAddingObject:sources[0]]).count!=2) return 16;
        puts("PASS native memory selection: catalog IDs, full-source copies, provenance, mandatory path/state, credential exclusion, dedupe, unknown IDs, schema, carry-forward, preview, budgets");
        return 0;
    } @catch(NSException *exception) { (void)exception; return 99; }
}
