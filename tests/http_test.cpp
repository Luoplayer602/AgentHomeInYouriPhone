#include "../core/web/HTTP.hpp"
#include <cassert>
#include <iostream>
using namespace agenthome;
static bool invalid(const std::string &s){try{parseHTTP(s);return false;}catch(const std::exception&){return true;}}
int main(){
 auto r=parseHTTP("POST /api/submit HTTP/1.1\r\nHost: 100.65.210.88:8765\r\nContent-Length: 2\r\nContent-Type: application/json\r\nOrigin: http://100.65.210.88:8765\r\nX-AH-CSRF: secret\r\nCookie: other=x; ah_session=token\r\n\r\n{}");
 assert(r.body=="{}"&&allowedHost(r,"100.65.210.88",8765)&&allowedOrigin(r));
 assert(sessionCookie(r)=="token"&&allowedMutation(r,true,"secret")&&!allowedMutation(r,false,"secret")&&!allowedMutation(r,true,"wrong"));
 r.headers["host"]="evil.example:8765"; assert(!allowedHost(r,"100.65.210.88",8765)&&!allowedOrigin(r));
 r.headers["origin"]="http://evil.example";assert(!allowedMutation(r,true,"secret"));
 r.headers["cookie"]="ah_session=a; ah_session=b";assert(sessionCookie(r).empty());
 assert(invalid("POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 1\r\nContent-Length: 1\r\n\r\na"));
 assert(invalid("POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n"));
 assert(invalid("POST / HTTP/1.1\r\nHost: x\r\nContent-Length: -1\r\n\r\n"));
 assert(invalid("POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 2\r\n\r\n{"));
 assert(invalid("GET / HTTP/1.1\r\nHost: x\r\n\r\nextra"));
 assert(invalid("GET / HTTP/1.1\r\n\r\n"));
 auto partial=parseHTTP("POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 2\r\n\r\n{",false);assert(partial.bodyLength==2);
 assert(invalid("POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 999999\r\n\r\n"));
 std::cout<<"PASS HTTP: framing limits, incomplete body, duplicate headers, chunking denied, Host/Origin, cookies, CSRF, read-only mutation gate\n";
}
