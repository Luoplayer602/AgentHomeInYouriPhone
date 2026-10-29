#pragma once
#include <string>
#include <vector>
#include <algorithm>
namespace agenthome {
struct MarkdownBlock {
    enum Kind { Text, Code, Table } kind=Text;
    std::string text, language;
    std::vector<std::vector<std::string>> rows;
    std::vector<int> align; // 0 left, 1 center, 2 right
};
inline std::string trim(const std::string &s) { auto a=s.find_first_not_of(" \t\r\n"); if(a==std::string::npos) return ""; auto b=s.find_last_not_of(" \t\r\n"); return s.substr(a,b-a+1); }
inline std::vector<std::string> tableCells(std::string line) {
    line=trim(line); if(!line.empty() && line.front()=='|') line.erase(0,1);
    if(!line.empty() && line.back()=='|' && (line.size()<2 || line[line.size()-2]!='\\')) line.pop_back();
    std::vector<std::string> cells; std::string cell; bool code=false;
    for(size_t i=0;i<line.size();i++) {
        char c=line[i];
        if(c=='\\' && i+1<line.size() && line[i+1]=='|') { cell+='|'; ++i; continue; }
        if(c=='`') code=!code;
        if(c=='|' && !code) { cells.push_back(trim(cell)); cell.clear(); } else cell+=c;
    }
    cells.push_back(trim(cell)); return cells;
}
inline bool tableDivider(const std::string& line,std::vector<int>& align) {
    if(line.find('|')==std::string::npos) return false;
    auto cells=tableCells(line); if(cells.empty() || cells.size()>16) return false;
    align.clear();
    for(auto cell:cells) {
        bool left=!cell.empty() && cell.front()==':', right=!cell.empty() && cell.back()==':';
        if(left) cell.erase(0,1);
        if(right && !cell.empty()) cell.pop_back();
        if(cell.size()<3 || cell.find_first_not_of('-')!=std::string::npos) return false;
        align.push_back(left && right?1:right?2:0);
    }
    return true;
}
inline std::vector<MarkdownBlock> markdownBlocks(const std::string& source) {
    std::vector<std::string> lines; size_t start=0;
    while(true) { auto end=source.find('\n',start); if(end==std::string::npos) { lines.push_back(source.substr(start)); break; } lines.push_back(source.substr(start,end-start)); start=end+1; }
    std::vector<MarkdownBlock> out; std::string text;
    auto flush=[&] { if(!trim(text).empty()) { MarkdownBlock b; b.text=text; out.push_back(b); } text.clear(); };
    for(size_t i=0;i<lines.size();) {
        auto line=trim(lines[i]); char marker=line.empty()?0:line[0]; size_t fence=0;
        if(marker=='`' || marker=='~') while(fence<line.size() && line[fence]==marker) ++fence;
        size_t indent=lines[i].find_first_not_of(' ');
        if(fence>=3 && indent<=3) {
            flush(); MarkdownBlock b; b.kind=MarkdownBlock::Code; b.language=trim(line.substr(fence)); ++i;
            while(i<lines.size()) {
                auto end=trim(lines[i]); size_t n=0; while(n<end.size() && end[n]==marker) ++n;
                if(n>=fence && lines[i].find_first_not_of(' ')<=3 && trim(end.substr(n)).empty()) { ++i; break; }
                b.text+=lines[i]; if(i+1<lines.size()) b.text+='\n'; ++i;
            }
            out.push_back(b); continue;
        }
        std::vector<int> align;
        if(i+1<lines.size() && lines[i].find('|')!=std::string::npos && tableDivider(lines[i+1],align)) {
            auto header=tableCells(lines[i]);
            if(header.size()==align.size()) {
                flush(); MarkdownBlock b; b.kind=MarkdownBlock::Table; b.align=align; b.rows.push_back(header); i+=2;
                while(i<lines.size() && !trim(lines[i]).empty() && lines[i].find('|')!=std::string::npos && b.rows.size()<201) {
                    auto cells=tableCells(lines[i]); cells.resize(header.size()); b.rows.push_back(cells); ++i;
                }
                out.push_back(b); continue;
            }
        }
        text+=lines[i]; if(i+1<lines.size()) text+='\n'; ++i;
    }
    flush(); return out;
}
}
