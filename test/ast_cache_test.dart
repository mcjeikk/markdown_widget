import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_widget/markdown_widget.dart';

/// Verifies the parse/build split + AST reuse used by [MarkdownWidgetState]
/// to avoid re-parsing the document on every rebuild (search, theme, fonts).
void main() {
  const data = '''
# Title

Some **bold** and _italic_ text with `inline code`.

- item one
- item two

> a blockquote

## Section

\`\`\`dart
final x = 1;
\`\`\`
''';

  test('buildWidgets equals parseNodes + buildFromNodes', () {
    final gen = MarkdownGenerator();
    final viaBuildWidgets = gen.buildWidgets(data);
    final viaNodes = gen.buildFromNodes(gen.parseNodes(data));
    expect(viaNodes, isNotEmpty);
    expect(viaNodes.length, viaBuildWidgets.length);
  });

  test('the parsed AST can be reused across builds without mutation', () {
    final gen = MarkdownGenerator();
    final nodes = gen.parseNodes(data);
    final first = gen.buildFromNodes(nodes);
    final second = gen.buildFromNodes(nodes);
    final third = gen.buildFromNodes(nodes);
    expect(first, isNotEmpty);
    // Re-visiting the same AST must yield identical block counts each time,
    // proving the visitor does not mutate the nodes (the basis of the cache).
    expect(second.length, first.length);
    expect(third.length, first.length);
  });

  test('TOC is produced consistently from a reused AST', () {
    final gen = MarkdownGenerator();
    final nodes = gen.parseNodes(data);
    var firstCount = -1;
    var secondCount = -2;
    gen.buildFromNodes(nodes, onTocList: (t) => firstCount = t.length);
    gen.buildFromNodes(nodes, onTocList: (t) => secondCount = t.length);
    expect(firstCount, 2); // "Title" (h1) + "Section" (h2)
    expect(secondCount, firstCount);
  });
}
