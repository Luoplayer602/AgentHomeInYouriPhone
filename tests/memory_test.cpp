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
    std::vector<Source> sources={{"1","user","Project LOTUS-482, report /tmp/report.txt"},{"231","user",pending}};
    assert(ground(sources,"1","LOTUS-482",false));
    assert(!ground(sources,"1","NEW-999",false));
    assert(!ground(sources,"2","LOTUS-482",false));
    assert(!ground(sources,"231","done",true)); // Cannot strip NOT or permission conditions.
    assert(ground(sources,"231",pending,true));
    assert(!ground(sources,"231","",true));
    assert(!ground(sources,"1",std::string("LOTUS-482\0invented",18),false));
    puts("PASS grounded memory: project/path/negative-state evidence, credential exclusion, source IDs, no invented quotes, preserves entire status/permission source");
}
