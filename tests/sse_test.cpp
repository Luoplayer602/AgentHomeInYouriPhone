#include "../core/stream/SSEDecoder.hpp"
#include <cassert>
#include <iostream>
using agenthome::SSEDecoder;
int main() {
    std::string source = "\xef\xbb\xbf:heartbeat\r\ndata: {\"text\":\"Xin chào 👋\"}\r\n\r\nevent: message\ndata: a\ndata:b\n\ndata: [DONE]\r\rdata: incomplete";
    for (size_t chunk = 1; chunk <= source.size(); ++chunk) {
        SSEDecoder parser; std::vector<std::string> events;
        for (size_t i = 0; i < source.size(); i += chunk) {
            auto next = parser.feed(source.data() + i, std::min(chunk, source.size() - i));
            events.insert(events.end(), next.begin(), next.end());
        }
        assert((events == std::vector<std::string>{"{\"text\":\"Xin chào 👋\"}", "a\nb", "[DONE]"}));
    }
    SSEDecoder parser;
    auto empty = parser.feed("data\n\n", 6); assert(empty.size() == 1 && empty[0].empty());
    bool rejected = false;
    try { std::string huge(256 * 1024 + 1, 'x'); parser.feed(huge.data(), huge.size()); }
    catch (const std::length_error&) { rejected = true; }
    assert(rejected);
    std::cout << "PASS SSE: all chunk boundaries, UTF-8, BOM, CR/LF/CRLF, comments, multiline, EOF, size bound\n";
}
