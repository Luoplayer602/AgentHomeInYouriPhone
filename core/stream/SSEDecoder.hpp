#pragma once
#include <string>
#include <vector>
#include <stdexcept>
namespace agenthome {
// Byte framing only: UTF-8 is decoded after an entire SSE event arrives.
class SSEDecoder {
    std::string line_, data_;
    bool skipLF_ = false, first_ = true;
    static constexpr size_t limit_ = 256 * 1024;
    void line(std::vector<std::string>& out) {
        if (first_) { if (line_.compare(0, 3, "\xef\xbb\xbf") == 0) line_.erase(0, 3); first_ = false; }
        if (line_.empty()) {
            if (!data_.empty()) { data_.pop_back(); out.push_back(data_); data_.clear(); }
        } else if (line_.compare(0, 5, "data:") == 0 || line_ == "data") {
            size_t start = line_ == "data" ? 4 : 5;
            if (start < line_.size() && line_[start] == ' ') ++start;
            data_.append(line_, start, std::string::npos); data_ += '\n';
            if (data_.size() > limit_) throw std::length_error("SSE event too large");
        }
        line_.clear();
    }
public:
    std::vector<std::string> feed(const char *bytes, size_t length) {
        std::vector<std::string> out;
        for (size_t i = 0; i < length; ++i) {
            char c = bytes[i];
            if (skipLF_) { skipLF_ = false; if (c == '\n') continue; }
            if (c == '\r' || c == '\n') { line(out); skipLF_ = c == '\r'; }
            else { line_ += c; if (line_.size() > limit_) throw std::length_error("SSE line too large"); }
        }
        return out;
    }
};
}
