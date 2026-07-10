import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:visibility_detector/visibility_detector.dart';

/// TableConfig contract: THead cells render with [TableConfig.headerStyle]
/// and TBody cells with [TableConfig.bodyStyle] (regression test for the
/// bug where TBodyNode read headerStyle, leaving bodyStyle dead).
void main() {
  const markdown = '''
| colA | colB |
| ---- | ---- |
| bodyCellOne | bodyCellTwo |
''';

  double? effectiveFontSizeOf(WidgetTester tester, String text) {
    double? found;
    for (final w in tester.allWidgets.whereType<RichText>()) {
      void visit(InlineSpan span, TextStyle? inherited) {
        final style = inherited == null
            ? span.style
            : (span.style == null ? inherited : inherited.merge(span.style));
        if (span is TextSpan) {
          if (span.text != null && span.text!.contains(text)) {
            found = style?.fontSize;
          }
          span.children?.forEach((c) => visit(c, style));
        }
      }

      visit(w.text, null);
    }
    return found;
  }

  testWidgets('THead uses headerStyle and TBody uses bodyStyle',
      (tester) async {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MarkdownWidget(
          data: markdown,
          config: MarkdownConfig(configs: [
            TableConfig(
              headerStyle: const TextStyle(fontSize: 21),
              bodyStyle: const TextStyle(fontSize: 15),
            ),
          ]),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(effectiveFontSizeOf(tester, 'colA'), 21,
        reason: 'header cells must render with headerStyle');
    expect(effectiveFontSizeOf(tester, 'bodyCellOne'), 15,
        reason: 'body cells must render with bodyStyle, not headerStyle');
  });
}
