#import "AHWebServer.h"
#import <Security/Security.h>
#import <CommonCrypto/CommonKeyDerivation.h>
#import <CommonCrypto/CommonDigest.h>
#include "../core/web/HTTP.hpp"
#include <atomic>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
static NSString *str(const std::string& s) { return [[NSString alloc] initWithBytes:s.data() length:s.size() encoding:NSUTF8StringEncoding]; }
static NSData *randomData(NSUInteger length) { NSMutableData *d=[NSMutableData dataWithLength:length]; return SecRandomCopyBytes(kSecRandomDefault,length,d.mutableBytes)==errSecSuccess?d:nil; }
static NSString *token(void) { NSData *d=randomData(32); return [[d base64EncodedStringWithOptions:0] stringByReplacingOccurrencesOfString:@"/" withString:@"_"]; }
static NSData *derive(NSString *password,NSData *salt) { NSData *p=[password dataUsingEncoding:NSUTF8StringEncoding]; NSMutableData *d=[NSMutableData dataWithLength:32]; return CCKeyDerivationPBKDF(kCCPBKDF2,(const char *)p.bytes,p.length,(const unsigned char *)salt.bytes,salt.length,kCCPRFHmacAlgSHA256,120000,(unsigned char *)d.mutableBytes,d.length)==0?d:nil; }
static BOOL equalData(NSData *a,NSData *b) { if(a.length!=b.length || !a.length) return NO; const unsigned char *x=(const unsigned char *)a.bytes,*y=(const unsigned char *)b.bytes; unsigned char result=0; for(NSUInteger i=0;i<a.length;i++) result|=x[i]^y[i]; return result==0; }
static BOOL sendBytes(int fd,NSData *data) { const char *p=(const char *)data.bytes; size_t left=data.length; while(left) { ssize_t n=send(fd,p,left,0); if(n<0 && errno==EINTR) continue; if(n<=0) return NO; left-=n; p+=n; } return YES; }
static void respond(int fd,int status,NSString *type,NSData *body,NSString *extra) {
    NSString *headers=[NSString stringWithFormat:@"HTTP/1.1 %d Response\r\nContent-Type: %@\r\nContent-Length: %lu\r\nConnection: close\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\nContent-Security-Policy: default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'none'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'\r\n%@\r\n",status,type,(unsigned long)body.length,extra ?: @""];
    if(sendBytes(fd,[headers dataUsingEncoding:NSUTF8StringEncoding])) sendBytes(fd,body);
}
static void replyJSON(int fd,int status,id object,NSString *extra) { respond(fd,status,@"application/json; charset=utf-8",[NSJSONSerialization dataWithJSONObject:object options:0 error:nil],extra); }
@interface AHWebServer () {
    std::atomic<uint64_t> _generation;
}
@property sqlite3 *db;
@property int listener;
@property NSInteger port;
@property BOOL enabled;
@property BOOL interactive;
@property (nonatomic,strong) NSData *salt;
@property (nonatomic,strong) NSData *passwordHash;
@property (nonatomic,strong) NSDictionary *profile;
@property (nonatomic,strong) NSMutableDictionary *sessions;
@property (nonatomic,strong) NSMutableDictionary *attempts;
@property (nonatomic,copy) NSString *csrf;
@property (nonatomic,copy) NSString *error;
@property (nonatomic,copy) id (^rpc)(NSString *,NSDictionary *,NSString **);
@end
@implementation AHWebServer
- (instancetype)initWithDatabase:(sqlite3 *)db rpc:(id (^)(NSString *,NSDictionary *,NSString **))rpc {
    if((self=[super init])) {
        std::atomic_init(&_generation,uint64_t(0));
        self.db=db; self.rpc=rpc; self.listener=-1; self.port=8765; self.sessions=[NSMutableDictionary dictionary]; self.attempts=[NSMutableDictionary dictionary]; self.csrf=token();
        sqlite3_exec(db,"CREATE TABLE IF NOT EXISTS web_settings(id INTEGER PRIMARY KEY CHECK(id=1),enabled INTEGER NOT NULL,port INTEGER NOT NULL,interactive INTEGER NOT NULL,salt TEXT NOT NULL,verifier TEXT NOT NULL,profile TEXT NOT NULL)",NULL,NULL,NULL);
        sqlite3_stmt *s=NULL; BOOL invalidAuth=NO;
        if(sqlite3_prepare_v2(db,"SELECT enabled,port,interactive,salt,verifier,profile FROM web_settings WHERE id=1",-1,&s,NULL)==SQLITE_OK && sqlite3_step(s)==SQLITE_ROW) {
            self.enabled=sqlite3_column_int(s,0); self.port=sqlite3_column_int(s,1); self.interactive=sqlite3_column_int(s,2);
            NSString *storedVerifier=@((const char *)sqlite3_column_text(s,4));
            self.salt=[[NSData alloc] initWithBase64EncodedString:@((const char *)sqlite3_column_text(s,3)) options:0]; self.passwordHash=[[NSData alloc] initWithBase64EncodedString:@((const char *)sqlite3_column_text(s,4)) options:0];
            invalidAuth=storedVerifier.length && (self.passwordHash.length!=32 || self.salt.length!=16);
            NSString *config=@((const char *)sqlite3_column_text(s,5)); self.profile=[NSJSONSerialization JSONObjectWithData:[config dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        }
        sqlite3_finalize(s); if(![self.profile isKindOfClass:NSDictionary.class]) self.profile=@{};
        if(invalidAuth || !self.csrf || self.port<1024 || self.port>65535) { self.enabled=NO; self.error=@"Cấu hình Webview không hợp lệ; lưu lại trong Cài đặt."; }
        if(self.enabled) [self start];
    } return self;
}
- (NSDictionary *)status { return @{@"enabled":@(self.enabled),@"port":@(self.port),@"interactive":@(self.interactive),@"public":@(!self.passwordHash.length),@"error":self.error ?: @"",@"model":self.profile[@"model"] ?: @""}; }
- (BOOL)save {
    sqlite3_stmt *s=NULL; int rc=sqlite3_prepare_v2(self.db,"INSERT OR REPLACE INTO web_settings VALUES (1,?,?,?,?,?,?)",-1,&s,NULL);
    if(rc==SQLITE_OK) {
        sqlite3_bind_int(s,1,self.enabled); sqlite3_bind_int(s,2,(int)self.port); sqlite3_bind_int(s,3,self.interactive);
        sqlite3_bind_text(s,4,[self.salt base64EncodedStringWithOptions:0].UTF8String ?: "",-1,SQLITE_TRANSIENT); sqlite3_bind_text(s,5,[self.passwordHash base64EncodedStringWithOptions:0].UTF8String ?: "",-1,SQLITE_TRANSIENT);
        NSString *profile=[[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:self.profile ?: @{} options:0 error:nil] encoding:NSUTF8StringEncoding]; sqlite3_bind_text(s,6,profile.UTF8String,-1,SQLITE_TRANSIENT); rc=sqlite3_step(s);
    } sqlite3_finalize(s); return rc==SQLITE_DONE;
}
- (void)profileFrom:(NSDictionary *)profile {
    if(![profile isKindOfClass:NSDictionary.class] || ![profile[@"id"] isKindOfClass:NSString.class] || ![profile[@"endpoint"] isKindOfClass:NSString.class] || ![profile[@"model"] isKindOfClass:NSString.class]) return;
    self.profile=@{@"id":profile[@"id"],@"endpoint":profile[@"endpoint"],@"model":profile[@"model"],@"disableStreaming":@([profile[@"disableStreaming"] boolValue]),@"context_window_tokens":@([profile[@"context_window_tokens"] integerValue]),@"max_output_tokens":@([profile[@"max_output_tokens"] integerValue] ?: 8192)};
}
- (id)handle:(NSString *)method params:(NSDictionary *)params error:(NSString **)error {
    if([method isEqual:@"web.status"]) return [self status];
    if([method isEqual:@"web.profile"]) { [self profileFrom:params[@"profile"]]; if(![self save]) *error=@"Cannot save web profile"; return [self status]; }
    if(![method isEqual:@"web.configure"]) { *error=@"Unknown web method"; return nil; }
    NSInteger port=[params[@"port"] integerValue]; NSString *password=params[@"password"];
    if(port<1024 || port>65535 || ![password isKindOfClass:NSString.class] || password.length>256) { *error=@"Port phải từ 1024–65535, mật khẩu tối đa 256 ký tự."; return nil; }
    NSData *salt=password.length?randomData(16):[NSData data],*hash=password.length?derive(password,salt):[NSData data];
    if(password.length && (!salt || !hash)) { *error=@"Không tạo được cấu hình mật khẩu."; return nil; }
    NSString *csrf=token(); if(!csrf) { *error=@"Không tạo được session token."; return nil; }
    [self stop]; self.port=port; self.enabled=[params[@"enabled"] boolValue]; self.interactive=[params[@"interactive"] boolValue]; self.salt=salt; self.passwordHash=hash; self.csrf=csrf; [self.sessions removeAllObjects]; [self.attempts removeAllObjects]; [self profileFrom:params[@"profile"]];
    if(![self save]) { self.enabled=NO; *error=@"Cannot save web settings"; return nil; }
    if(self.enabled) [self start]; return [self status];
}
- (void)stop { ++_generation; if(self.listener>=0) { shutdown(self.listener,SHUT_RDWR); close(self.listener); self.listener=-1; } }
- (void)start {
    self.error=nil; int fd=socket(AF_INET,SOCK_STREAM,0); int yes=1; setsockopt(fd,SOL_SOCKET,SO_REUSEADDR,&yes,sizeof(yes));
    struct sockaddr_in address={}; address.sin_family=AF_INET; address.sin_addr.s_addr=htonl(INADDR_ANY); address.sin_port=htons((uint16_t)self.port);
    if(fd<0 || bind(fd,(struct sockaddr *)&address,sizeof(address)) || listen(fd,8)) { if(fd>=0) close(fd); self.error=@"Không mở được port (có thể đang được dùng)."; self.enabled=NO; [self save]; return; }
    self.listener=fd; uint64_t generation=++_generation; dispatch_semaphore_t slots=dispatch_semaphore_create(8);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
        while(self->_generation.load()==generation) {
            int client=accept(fd,NULL,NULL); if(client<0) break;
            if(self->_generation.load()!=generation) { close(client); break; }
            if(dispatch_semaphore_wait(slots,DISPATCH_TIME_NOW)) { close(client); continue; }
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{ @autoreleasepool { @try { [self serve:client generation:generation]; } @catch(__unused NSException *exception) { replyJSON(client,400,@{@"error":@"Invalid request"},nil); } } close(client); dispatch_semaphore_signal(slots); });
        }
    });
}
- (BOOL)authorized:(const agenthome::HTTPRequest&)request {
    if(!self.passwordHash.length) return YES;
    NSString *key=str(agenthome::sessionCookie(request)); if(!key.length) return NO; NSNumber *expiry=self.sessions[key];
    return expiry && expiry.doubleValue>NSDate.timeIntervalSinceReferenceDate;
}
- (void)serve:(int)fd generation:(uint64_t)generation {
    struct timeval timeout={5,0}; setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout)); setsockopt(fd,SOL_SOCKET,SO_SNDTIMEO,&timeout,sizeof(timeout)); int yes=1; setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&yes,sizeof(yes));
    std::string bytes; agenthome::HTTPRequest request;
    try {
        char chunk[4096]; size_t end;
        while((end=bytes.find("\r\n\r\n"))==std::string::npos) { ssize_t n=recv(fd,chunk,sizeof(chunk),0); if(n<=0) return; bytes.append(chunk,n); if(bytes.size()>80*1024 || (bytes.size()>16*1024 && bytes.find("\r\n\r\n")==std::string::npos)) throw std::runtime_error("large header"); }
        request=agenthome::parseHTTP(bytes,false); size_t expected=end+4+request.bodyLength;
        while(bytes.size()<expected) { ssize_t n=recv(fd,chunk,std::min(sizeof(chunk),expected-bytes.size()),0); if(n<=0) return; bytes.append(chunk,n); }
        request=agenthome::parseHTTP(bytes);
    } catch(const std::exception&) { replyJSON(fd,400,@{@"error":@"Invalid HTTP request"},nil); return; }
    struct sockaddr_in local={},peer={}; socklen_t length=sizeof(local); getsockname(fd,(struct sockaddr *)&local,&length); length=sizeof(peer); getpeername(fd,(struct sockaddr *)&peer,&length); char ip[INET_ADDRSTRLEN],remote[INET_ADDRSTRLEN]; inet_ntop(AF_INET,&local.sin_addr,ip,sizeof(ip)); inet_ntop(AF_INET,&peer.sin_addr,remote,sizeof(remote));
    NSString *peerAddress=@(remote); NSInteger port=ntohs(local.sin_port);
    if(!agenthome::allowedHost(request,ip,(unsigned)port)) { replyJSON(fd,403,@{@"error":@"Invalid Host"},nil); return; }
    if(!agenthome::allowedOrigin(request)) { replyJSON(fd,403,@{@"error":@"Cross-origin request denied"},nil); return; }
    NSString *target=str(request.target);
    if(!target || [target rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location!=NSNotFound) { replyJSON(fd,400,@{@"error":@"Invalid target"},nil); return; }
    NSURLComponents *url=[NSURLComponents componentsWithString:[@"http://localhost" stringByAppendingString:target]];
    if(!url) { replyJSON(fd,400,@{@"error":@"Invalid URL"},nil); return; }
    NSString *path=url.path; NSMutableDictionary *query=[NSMutableDictionary dictionary]; for(NSURLQueryItem *item in url.queryItems) if(item.value) query[item.name]=item.value;
    if(request.method=="GET" && [path isEqual:@"/"]) { NSData *page=[NSData dataWithContentsOfFile:@"/var/jb/usr/share/agenthome/index.html"]; respond(fd,page?200:500,@"text/html; charset=utf-8",page ?: [NSData data],nil); return; }
    id body=@{};
    if(request.method=="POST") {
        if(request.headers["content-type"].find("application/json")!=0) { replyJSON(fd,415,@{@"error":@"Use application/json"},nil); return; }
        NSData *data=[NSData dataWithBytes:request.body.data() length:request.body.size()]; body=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if(![body isKindOfClass:NSDictionary.class]) { replyJSON(fd,400,@{@"error":@"Invalid JSON object"},nil); return; }
    }
    __block int code=200; __block id result=nil; __block NSString *extra=nil; __block BOOL stream=NO;
    dispatch_sync(dispatch_get_main_queue(),^{
        if(self->_generation.load()!=generation || !self.enabled) { code=503; result=@{@"error":@"Webview disabled"}; return; }
        if([path isEqual:@"/api/login"] && request.method=="POST") {
            NSString *address=peerAddress; NSDictionary *attempt=self.attempts[address]; NSTimeInterval now=NSDate.timeIntervalSinceReferenceDate; NSInteger count=now-[attempt[@"at"] doubleValue]<60?[attempt[@"count"] integerValue]:0;
            if(count>=5) { code=429; result=@{@"error":@"Thử lại sau 60 giây"}; return; }
            if(self.attempts.count>256) [self.attempts removeAllObjects]; self.attempts[address]=@{@"at":@(count?[attempt[@"at"] doubleValue]:now),@"count":@(count+1)};
            NSString *password=body[@"password"];
            if(self.passwordHash.length && (![password isKindOfClass:NSString.class] || password.length>256 || !equalData(derive(password,self.salt),self.passwordHash))) { code=401; result=@{@"error":@"Sai mật khẩu"}; return; }
            [self.attempts removeObjectForKey:address]; NSString *session=token(); if(!session) { code=500; result=@{@"error":@"Random unavailable"}; return; }
            if(self.sessions.count>=64) [self.sessions removeAllObjects]; self.sessions[session]=@(now+3600);
            extra=[NSString stringWithFormat:@"Set-Cookie: ah_session=%@; HttpOnly; SameSite=Strict; Max-Age=3600; Path=/\r\n",session]; result=@{@"ok":@YES}; return;
        }
        if(![self authorized:request]) { code=401; result=@{@"error":@"Cần đăng nhập"}; return; }
        if([path isEqual:@"/api/status"] && request.method=="GET") { NSMutableDictionary *status=[[self status] mutableCopy]; status[@"csrf"]=self.csrf ?: @""; result=status; return; }
        if(request.method=="POST" && !agenthome::allowedMutation(request,YES,std::string(self.csrf.UTF8String ?: ""))) { code=403; result=@{@"error":@"Invalid CSRF token"}; return; }
        if(request.method=="POST" && !self.interactive) { code=403; result=@{@"error":@"Webview chỉ cho phép xem"}; return; }
        NSString *error=nil;
        if(request.method=="GET" && [path isEqual:@"/api/conversations"]) result=self.rpc(@"chat.conversations",@{},&error);
        else if(request.method=="GET" && ([@[@"/api/messages",@"/api/events"] containsObject:path])) {
            NSString *identifier=query[@"conversation_id"];
            if(!identifier.length || identifier.length>80) { code=400; result=@{@"error":@"Invalid conversation"}; return; }
            NSDictionary *params=@{@"conversation_id":identifier}; id history=self.rpc(@"chat.list",params,&error); id snapshot=self.rpc(@"ai.snapshot",params,&error);
            if(history && snapshot) result=@{@"history":history,@"snapshot":snapshot}; stream=[path isEqual:@"/api/events"];
        } else if(request.method=="POST" && [path isEqual:@"/api/create"]) result=self.rpc(@"chat.create",@{},&error);
        else if(request.method=="GET" && [path isEqual:@"/api/context"]) result=self.rpc(@"context.status",@{@"conversation_id":query[@"conversation_id"] ?: @"",@"profile":self.profile ?: @{}},&error);
        else if(request.method=="POST" && [@[@"/api/compact",@"/api/activate",@"/api/discard",@"/api/drop"] containsObject:path]) {
            NSString *method=[path isEqual:@"/api/compact"]?@"context.compact":[path isEqual:@"/api/activate"]?@"context.activate":[path isEqual:@"/api/discard"]?@"context.discard":@"context.drop";
            result=self.rpc(method,@{@"conversation_id":[body[@"conversation_id"] isKindOfClass:NSString.class]?body[@"conversation_id"]:@"",@"id":[body[@"id"] isKindOfClass:NSString.class]?body[@"id"]:@"",@"profile":self.profile ?: @{}},&error);
        }
        else if(request.method=="POST" && [path isEqual:@"/api/submit"]) {
            if(!self.profile.count || ![body[@"conversation_id"] isKindOfClass:NSString.class] || ![body[@"text"] isKindOfClass:NSString.class] || ![body[@"id"] isKindOfClass:NSString.class]) { code=400; result=@{@"error":@"Thiếu cấu hình provider hoặc nội dung"}; return; }
            result=self.rpc(@"ai.submit",@{@"conversation_id":body[@"conversation_id"],@"id":body[@"id"],@"text":body[@"text"],@"profile":self.profile},&error);
        } else if(request.method=="POST" && [path isEqual:@"/api/cancel"]) result=self.rpc(@"ai.cancel",@{@"id":[body[@"id"] isKindOfClass:NSString.class]?body[@"id"]:@""},&error);
        else { code=404; result=@{@"error":@"Not found"}; return; }
        if(!result) { code=400; result=@{@"error":error ?: @"Request failed"}; }
    });
    if(!stream || code!=200) { replyJSON(fd,code,result ?: @{},extra); return; }
    NSString *headers=@"HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-store\r\nConnection: close\r\nX-Content-Type-Options: nosniff\r\n\r\n";
    if(!sendBytes(fd,[headers dataUsingEncoding:NSUTF8StringEncoding])) return;
    NSData *previous=nil;
    for(int tick=0;tick<60 && self->_generation.load()==generation;tick++) {
        __block id snapshot=nil;
        dispatch_sync(dispatch_get_main_queue(),^{ if([self authorized:request] && self.enabled) { NSString *error=nil; NSDictionary *params=@{@"conversation_id":query[@"conversation_id"]}; id h=self.rpc(@"chat.list",params,&error),s=self.rpc(@"ai.snapshot",params,&error); if(h&&s) snapshot=@{@"history":h,@"snapshot":s}; } });
        if(!snapshot) break;
        NSData *data=[NSJSONSerialization dataWithJSONObject:snapshot options:NSJSONWritingSortedKeys error:nil];
        if(![data isEqual:previous]) { NSMutableData *event=[NSMutableData dataWithData:[@"event: snapshot\ndata: " dataUsingEncoding:NSUTF8StringEncoding]]; [event appendData:data]; [event appendData:[@"\n\n" dataUsingEncoding:NSUTF8StringEncoding]]; if(!sendBytes(fd,event)) break; previous=data; }
        else if(tick%4==0 && !sendBytes(fd,[@": ping\n\n" dataUsingEncoding:NSUTF8StringEncoding])) break;
        usleep(500000);
    }
}
@end
