#pragma once
#include <string>
#include <vector>
#include <regex>
namespace ahmemory {
struct Source { std::string id, role, text; };
inline bool sensitive(const std::string &lower) {
    for(const auto *term:{"api key","api_key","apikey","password","secret","mật khẩu","token="}) if(lower.find(term)!=std::string::npos) return true;
    return false;
}
inline bool required(const std::string &text,const std::string &lower) {
    if(sensitive(lower)) return false;
    static const std::regex identifier(R"((^|[^A-Za-z0-9_-])[A-Z][A-Z0-9]{0,15}-[0-9]{1,12}($|[^A-Za-z0-9_-]))");
    static const std::regex path(R"((^|[\s`"'(=:])/(?:[A-Za-z0-9_.~-]+/)*[A-Za-z0-9_.~-]+)");
    if(lower.find("https://")!=std::string::npos || lower.find("http://")!=std::string::npos) return true;
    if(std::regex_search(text,identifier) || std::regex_search(text,path)) return true;
    for(const auto *term:{"not done","not verified","not authorized","not authorised","unverified","chưa kiểm","chưa xác","chưa hoàn","chưa chạy","chưa cho phép","không được phép","không deploy"}) if(lower.find(term)!=std::string::npos) return true;
    return false;
}
inline bool reference(const std::string &id) {
    if(id.size()<2 || id.size()>8 || id[0]!='S' || id[1]<'1' || id[1]>'9') return false;
    for(size_t i=2;i<id.size();i++) if(id[i]<'0' || id[i]>'9') return false;
    return true;
}
inline const Source *select(const std::vector<Source> &sources,const std::string &id) {
    if(!reference(id)) return nullptr;
    for(const auto &source:sources) if(source.id==id) return &source;
    return nullptr;
}
}
