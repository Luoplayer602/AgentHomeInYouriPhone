#include "../core/context/Search.hpp"
#include <cassert>
#include <cstdio>
int main() {
    using ahsearch::score;
    assert(score("project lotus-482",{"project"},"project_id")>0);
    assert(score("project lotus-482",{"lotus","482"},"lotus-482")>score("diagnostic",{"lotus","482"},"lotus-482"));
    assert(score("build not done",{"not done"},"pending")>0);
    assert(score("other unrelated text",{"project"},"project") == 0);
    puts("PASS memory search ranking: project aliases, exact IDs, pending state, unrelated text");
}
