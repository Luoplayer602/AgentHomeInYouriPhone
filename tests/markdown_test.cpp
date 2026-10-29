#include "../core/format/MarkdownBlocks.hpp"
#include <cassert>
#include <iostream>
int main() {
    using namespace agenthome;
    auto blocks=markdownBlocks("# Hello\n\n```\nprint('chào')\n```\n\n| Name | Value |\n| :--- | ---: |\n| A | `x|y` |\n| B | c\\|d |\n\n**End**");
    assert(blocks.size()==4 && blocks[0].kind==MarkdownBlock::Text);
    assert(blocks[1].kind==MarkdownBlock::Code && blocks[1].language.empty() && blocks[1].text=="print('chào')\n");
    assert(blocks[2].kind==MarkdownBlock::Table && blocks[2].rows.size()==3 && blocks[2].align[1]==2);
    assert(blocks[2].rows[1][1]=="`x|y`" && blocks[2].rows[2][1]=="c|d");
    auto partial=markdownBlocks("~~~json\n{\"a\":1}"); assert(partial.size()==1 && partial[0].text=="{\"a\":1}" && partial[0].language=="json");
    auto nested=markdownBlocks("````\n```python\nx\n```\n````"); assert(nested.size()==1 && nested[0].text=="```python\nx\n```\n");
    auto malformed=markdownBlocks("a | b\n--- | nope\nx | y"); assert(malformed.size()==1 && malformed[0].kind==MarkdownBlock::Text);
    auto noEdges=markdownBlocks("A | B\n--- | :---:\n1 | 2"); assert(noEdges[0].kind==MarkdownBlock::Table && noEdges[0].align[1]==1);
    std::cout<<"PASS Markdown blocks: optional code language, exact copy text, streaming incomplete fence, fence length, tables, alignment, escaped pipes, invalid table fallback\n";
}
