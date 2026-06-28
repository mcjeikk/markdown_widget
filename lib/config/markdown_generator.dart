import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as m;

import '../widget/blocks/leaf/heading.dart';
import '../widget/span_node.dart';
import '../widget/widget_visitor.dart';
import 'configs.dart';
import 'toc.dart';

typedef HeadingNodeFilter = bool Function(HeadingNode toc);

///use [MarkdownGenerator] to transform markdown data to [Widget] list, so you can render it by any type of [ListView]
class MarkdownGenerator {
  final Iterable<m.InlineSyntax> inlineSyntaxList;
  final Iterable<m.BlockSyntax> blockSyntaxList;
  final EdgeInsets linesMargin;
  final List<SpanNodeGeneratorWithTag> generators;
  final SpanNodeAcceptCallback? onNodeAccepted;
  final m.ExtensionSet? extensionSet;
  final TextNodeGenerator? textGenerator;
  final SpanNodeBuilder? spanNodeBuilder;
  final RichTextBuilder? richTextBuilder;
  final RegExp? splitRegExp;
  final HeadingNodeFilter headingNodeFilter;

  /// Use [headingNodeFilter] to filter the levels of headings you want to show.
  /// e.g.
  /// ```dart
  /// (HeadingNode node) => {'h1', 'h2'}.contains(node.headingConfig.tag)
  /// ```
  MarkdownGenerator(
      {this.inlineSyntaxList = const [],
      this.blockSyntaxList = const [],
      this.linesMargin = const EdgeInsets.symmetric(vertical: 8),
      this.generators = const [],
      this.onNodeAccepted,
      this.extensionSet,
      this.textGenerator,
      this.spanNodeBuilder,
      this.richTextBuilder,
      this.splitRegExp,
      headingNodeFilter})
      : headingNodeFilter = headingNodeFilter ?? allowAll;

  ///Parse [data] into a markdown AST — the expensive step.
  ///
  ///Split out from [buildWidgets] so callers can cache the AST and reuse it
  ///across re-builds with the same [data] (e.g. search highlighting, font or
  ///theme changes) instead of re-parsing the whole document every time.
  List<m.Node> parseNodes(String data) {
    final m.Document document = m.Document(
      extensionSet: extensionSet ?? m.ExtensionSet.gitHubFlavored,
      encodeHtml: false,
      inlineSyntaxes: inlineSyntaxList,
      blockSyntaxes: blockSyntaxList,
    );
    final regExp = splitRegExp ?? WidgetVisitor.defaultSplitRegExp;
    final List<String> lines = data.split(regExp);
    return document.parseLines(lines);
  }

  ///Visit an already-parsed AST ([nodes]) and return the per-block [SpanNode]s
  ///(plus the [Toc] list via [onTocList]).
  ///
  ///Split from [buildFromNodes] so callers can build each block's widget
  ///lazily (only when it scrolls into view) instead of materialising every
  ///block up front — important for large documents.
  List<SpanNode> visitNodes(List<m.Node> nodes,
      {ValueCallback<List<Toc>>? onTocList, MarkdownConfig? config}) {
    final mdConfig = config ?? MarkdownConfig.defaultConfig;
    final regExp = splitRegExp ?? WidgetVisitor.defaultSplitRegExp;
    final List<Toc> tocList = [];
    final visitor = WidgetVisitor(
        config: mdConfig,
        generators: generators,
        textGenerator: textGenerator,
        richTextBuilder: richTextBuilder,
        splitRegExp: regExp,
        onNodeAccepted: (node, index) {
          onNodeAccepted?.call(node, index);
          if (node is HeadingNode && headingNodeFilter(node)) {
            final listLength = tocList.length;
            tocList.add(
                Toc(node: node, widgetIndex: index, selfIndex: listLength));
          }
        });
    final spans = visitor.visit(nodes);
    onTocList?.call(tocList);
    return spans;
  }

  ///Build a single block widget from one [span]. Used by the lazy item builder.
  Widget buildSpanWidget(SpanNode span) {
    final textSpan = spanNodeBuilder?.call(span) ?? span.build();
    final richText = richTextBuilder?.call(textSpan) ?? Text.rich(textSpan);
    return Padding(padding: linesMargin, child: richText);
  }

  ///Build widgets from an already-parsed AST ([nodes]).
  ///[onTocList] can provide the [Toc] list.
  List<Widget> buildFromNodes(List<m.Node> nodes,
      {ValueCallback<List<Toc>>? onTocList, MarkdownConfig? config}) {
    return visitNodes(nodes, onTocList: onTocList, config: config)
        .map(buildSpanWidget)
        .toList();
  }

  ///convert [data] to widgets (parse + build)
  ///[onTocList] can provider [Toc] list
  List<Widget> buildWidgets(String data,
      {ValueCallback<List<Toc>>? onTocList, MarkdownConfig? config}) {
    return buildFromNodes(parseNodes(data),
        onTocList: onTocList, config: config);
  }

  static bool allowAll(HeadingNode toc) => true;
}

typedef SpanNodeBuilder = TextSpan Function(SpanNode spanNode);

typedef RichTextBuilder = Widget Function(InlineSpan span);
