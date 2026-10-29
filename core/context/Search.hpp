#pragma once
#include <string>
#include <vector>
namespace ahsearch {
inline int score(const std::string &text,const std::vector<std::string> &terms,const std::string &phrase) {
    int result=0;
    if(!phrase.empty() && text.find(phrase)!=std::string::npos) result+=30;
    for(const auto &term:terms) if(term.size()>=2 && text.find(term)!=std::string::npos) result+=4;
    return result;
}
}
