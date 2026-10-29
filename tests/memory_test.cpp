#include "../core/context/Memory.hpp"
#include <cassert>
#include <cstdio>
int main() {
    using namespace ahmemory;
    assert(required("Project LOTUS-482", "project lotus-482"));
    assert(required("Ticket T-42", "ticket t-42"));
    assert(!required("ABC-12-34", "abc-12-34"));
    assert(required("See https://example.com/report", "see https://example.com/report"));
    assert(required("report file /tmp/agenthome-eval/report.txt.","report file /tmp/agenthome-eval/report.txt."));
    assert(required("Endpoint `/v1/chat/completions`", "endpoint `/v1/chat/completions`"));
    assert(required("Build and iPhone verification are NOT done.","build and iphone verification are not done."));
    assert(required("Chưa kiểm chứng trên iPhone", "chưa kiểm chứng trên iphone"));
    assert(!required("Read-only diagnostic completed", "read-only diagnostic completed"));
    assert(!required("Secret ABC-123 /private/key", "secret abc-123 /private/key"));
    const std::string pending="Build and iPhone verification are NOT done. Only read is authorized.";
    std::vector<Source> sources={{"S1","user","Project LOTUS-482, report /tmp/report.txt"},{"S2","user",pending}};
    assert(select(sources,"S1"));
    const auto *chosen=select(sources,"S2");
    assert(chosen && chosen->text==pending && chosen->role=="user");
    assert(!select(sources,"S999"));
    assert(!select(sources,"231"));
    assert(!reference("S01") && !reference("S0") && !reference("S1 quote"));
    assert(reference("S240"));
    assert(!select(sources,"done"));
    assert(!select(sources,std::string("S1\0invented",11)));
    puts("PASS memory selection: mandatory evidence, credential labels, exact catalog lookup, entire status/permission content, rejects unknown/raw/binary IDs");
}
