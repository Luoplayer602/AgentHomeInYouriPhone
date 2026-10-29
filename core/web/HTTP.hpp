#pragma once
#include <string>
#include <map>
#include <algorithm>
#include <stdexcept>
#include <cctype>
namespace agenthome {
struct HTTPRequest { std::string method,target,body; size_t bodyLength=0; std::map<std::string,std::string> headers; };
inline std::string httpTrim(std::string s) { auto a=s.find_first_not_of(" \t"); if(a==std::string::npos) return ""; return s.substr(a,s.find_last_not_of(" \t")-a+1); }
inline HTTPRequest parseHTTP(const std::string &bytes,bool complete=true) {
    if(bytes.size()>80*1024) throw std::runtime_error("Request too large");
    auto end=bytes.find("\r\n\r\n"); if(end==std::string::npos || end>16*1024) throw std::runtime_error("Bad headers");
    HTTPRequest r; auto first=bytes.find("\r\n"); std::string start=bytes.substr(0,first); auto a=start.find(' '),b=start.find(' ',a==std::string::npos?0:a+1);
    if(a==std::string::npos || b==std::string::npos || start.substr(b+1)!="HTTP/1.1") throw std::runtime_error("Bad request line");
    r.method=start.substr(0,a); r.target=start.substr(a+1,b-a-1);
    if((r.method!="GET" && r.method!="POST") || r.target.empty() || r.target[0]!='/' || r.target.size()>2048) throw std::runtime_error("Unsupported request");
    size_t pos=first+2;
    while(pos<end) {
        auto next=bytes.find("\r\n",pos); auto line=bytes.substr(pos,next-pos); auto colon=line.find(':');
        if(colon==std::string::npos || colon==0) throw std::runtime_error("Bad header");
        auto key=line.substr(0,colon); for(char &c:key) c=(char)std::tolower((unsigned char)c);
        if(key.find_first_not_of("abcdefghijklmnopqrstuvwxyz0123456789-")!=std::string::npos || r.headers.count(key)) throw std::runtime_error("Duplicate or invalid header");
        r.headers[key]=httpTrim(line.substr(colon+1)); pos=next+2;
    }
    if(!r.headers.count("host") || r.headers.count("transfer-encoding") || r.headers.count("expect")) throw std::runtime_error("Invalid framing");
    size_t length=0;
    if(r.headers.count("content-length")) {
        auto s=r.headers["content-length"]; if(s.empty() || s.find_first_not_of("0123456789")!=std::string::npos || s.size()>6) throw std::runtime_error("Invalid length");
        length=std::stoul(s); if(length>64*1024) throw std::runtime_error("Body too large");
    }
    r.bodyLength=length;
    if((complete && bytes.size()!=end+4+length) || bytes.size()>end+4+length) throw std::runtime_error("Incomplete or extra body");
    r.body=bytes.substr(end+4); return r;
}
}
namespace agenthome {
inline bool allowedHost(const HTTPRequest &r,const std::string& localIP,unsigned port) {
    auto h=r.headers.find("host"); if(h==r.headers.end()) return false;
    auto suffix=":"+std::to_string(port);
    return h->second==localIP+suffix || (localIP=="127.0.0.1" && h->second=="localhost"+suffix);
}
inline bool allowedOrigin(const HTTPRequest &r) {
    auto origin=r.headers.find("origin"),host=r.headers.find("host");
    return origin==r.headers.end() || (host!=r.headers.end() && origin->second=="http://"+host->second);
}
inline std::string sessionCookie(const HTTPRequest& r) {
    auto cookie=r.headers.find("cookie"); if(cookie==r.headers.end()) return "";
    size_t start=0; std::string session;
    while(start<cookie->second.size()) {
        auto end=cookie->second.find(';',start); auto value=httpTrim(cookie->second.substr(start,end==std::string::npos?end:end-start));
        if(value.compare(0,11,"ah_session=")==0) { if(!session.empty()) return ""; session=value.substr(11); }
        if(end==std::string::npos) break;
        start=end+1;
    }
    return session;
}
inline bool allowedMutation(const HTTPRequest& r,bool interactive,const std::string& csrf) {
    auto value=r.headers.find("x-ah-csrf"); return interactive && !csrf.empty() && value!=r.headers.end() && value->second==csrf && allowedOrigin(r);
}
}
