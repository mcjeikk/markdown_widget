import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:markdown/markdown.dart' as m;
import 'package:markdown_widget/markdown_widget.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:visibility_detector/visibility_detector.dart';

class MarkdownWidget extends StatefulWidget {
  ///the markdown data
  final String data;

  ///if [tocController] is not null, you can use [tocListener] to get current TOC index
  final TocController? tocController;

  ///set the desired scroll physics for the markdown item list
  final ScrollPhysics? physics;

  ///set shrinkWrap to obtained [ListView] (only available when [tocController] is null)
  final bool shrinkWrap;

  /// [ListView] padding
  final EdgeInsetsGeometry? padding;

  ///make text selectable
  final bool selectable;

  ///the configs of markdown
  final MarkdownConfig? config;

  ///config for [MarkdownGenerator]
  final MarkdownGenerator? markdownGenerator;

  /// Inset (in logical pixels) from the top of the viewport that floating
  /// overlays (app bars, search bars, etc.) occupy.
  ///
  /// When set, [AutoScrollController.scrollToIndex] with
  /// [AutoScrollPosition.begin] will place the target widget below this
  /// offset instead of at the raw viewport edge.  Defaults to `0.0`.
  final double topScrollOffset;

  const MarkdownWidget({
    Key? key,
    required this.data,
    this.tocController,
    this.physics,
    this.shrinkWrap = false,
    this.selectable = true,
    this.padding,
    this.config,
    this.markdownGenerator,
    this.topScrollOffset = 0.0,
  }) : super(key: key);

  @override
  MarkdownWidgetState createState() => MarkdownWidgetState();
}

class MarkdownWidgetState extends State<MarkdownWidget> {
  ///use [markdownGenerator] to transform markdown data to [Widget] list
  late MarkdownGenerator markdownGenerator;

  ///The markdown string converted by MarkdownGenerator will be retained in the [_widgets]
  final List<Widget> _widgets = [];

  ///Cached parsed AST + the data it came from. Reused across re-builds with the
  ///same [MarkdownWidget.data] (e.g. search highlighting, font/theme changes)
  ///so the document is parsed once, not on every rebuild/keystroke.
  List<m.Node>? _cachedNodes;
  String? _cachedNodesData;

  ///Per-instance prefix so [VisibilityDetector]/[AutoScrollTag] keys don't
  ///collide across multiple simultaneously-mounted [MarkdownWidget]s (e.g.
  ///reader tabs) — [VisibilityDetector] requires globally-unique keys.
  late final String _keyPrefix = identityHashCode(this).toString();

  /// The number of rendered widget blocks in the list.
  int get widgetCount => _widgets.length;

  ///[TocController] combines [TocWidget] and [MarkdownWidget]
  TocController? _tocController;

  /// Mutable top-offset read by [controller]'s viewport boundary closure.
  double _topScrollOffset = 0.0;

  ///[AutoScrollController] provides the scroll to index mechanism
  late final AutoScrollController controller;

  ///every [VisibilityDetector]'s child which is visible will be kept with [indexTreeSet]
  final indexTreeSet = SplayTreeSet<int>((a, b) => a - b);

  ///if the [ScrollDirection] of [ListView] is [ScrollDirection.forward], [isForward] will be true
  bool isForward = true;

  @override
  void initState() {
    super.initState();
    _topScrollOffset = widget.topScrollOffset;
    controller = AutoScrollController(
      viewportBoundaryGetter: () =>
          Rect.fromLTRB(0, _topScrollOffset, 0, 0),
    );
    _tocController = widget.tocController;
    _tocController?.jumpToIndexCallback = (index) {
      controller.scrollToIndex(index, preferPosition: AutoScrollPosition.begin);
    };
    updateState();
  }

  ///when we've got the data, we need update data without setState() to avoid the flicker of the view
  void updateState() {
    indexTreeSet.clear();
    markdownGenerator = widget.markdownGenerator ?? MarkdownGenerator();
    // Reuse the cached AST when the markdown text is unchanged; only re-parse
    // when [data] actually changes. The visit/build step still runs (so e.g.
    // search highlighting and theme changes apply), but the expensive parse
    // is skipped.
    final List<m.Node> nodes;
    if (_cachedNodes != null && _cachedNodesData == widget.data) {
      nodes = _cachedNodes!;
    } else {
      nodes = markdownGenerator.parseNodes(widget.data);
      _cachedNodes = nodes;
      _cachedNodesData = widget.data;
    }
    final result = markdownGenerator.buildFromNodes(
      nodes,
      onTocList: (tocList) {
        _tocController?.setTocList(tocList);
      },
      config: widget.config,
    );
    _widgets.addAll(result);
  }

  ///this method will be called when [updateState] or [dispose]
  void clearState() {
    indexTreeSet.clear();
    _widgets.clear();
  }

  @override
  void dispose() {
    clearState();
    controller.dispose();
    _tocController?.jumpToIndexCallback = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => buildMarkdownWidget();

  ///
  Widget buildMarkdownWidget() {
    final markdownWidget = NotificationListener<UserScrollNotification>(
      onNotification: (notification) {
        final ScrollDirection direction = notification.direction;
        isForward = direction == ScrollDirection.forward;
        return true;
      },
      child: ListView.builder(
        shrinkWrap: widget.shrinkWrap,
        physics: widget.physics,
        controller: controller,
        itemBuilder: (ctx, index) => wrapByAutoScroll(
            index,
            wrapByVisibilityDetector(index, _widgets[index]),
            controller,
            _keyPrefix),
        itemCount: _widgets.length,
        padding: widget.padding,
      ),
    );
    return widget.selectable
        ? SelectionArea(child: markdownWidget)
        : markdownWidget;
  }

  ///wrap widget by [VisibilityDetector] that can know if [child] is visible
  Widget wrapByVisibilityDetector(int index, Widget child) {
    return VisibilityDetector(
      key: ValueKey('$_keyPrefix-$index'),
      onVisibilityChanged: (VisibilityInfo info) {
        final visibleFraction = info.visibleFraction;
        if (isForward) {
          visibleFraction == 0
              ? indexTreeSet.remove(index)
              : indexTreeSet.add(index);
        } else {
          visibleFraction == 1.0
              ? indexTreeSet.add(index)
              : indexTreeSet.remove(index);
        }
        if (indexTreeSet.isNotEmpty) {
          _tocController?.onIndexChanged(indexTreeSet.first);
        }
      },
      child: child,
    );
  }

  @override
  void didUpdateWidget(MarkdownWidget oldWidget) {
    _topScrollOffset = widget.topScrollOffset;
    // Only rebuild the widget list when something that affects the output
    // changed. When [data] is unchanged the rebuild reuses the cached AST
    // (see [updateState]); when nothing changed at all we skip entirely.
    if (widget.data != oldWidget.data ||
        widget.config != oldWidget.config ||
        widget.markdownGenerator != oldWidget.markdownGenerator) {
      clearState();
      updateState();
    }
    super.didUpdateWidget(widget);
  }
}

///wrap widget by [AutoScrollTag] that can use [AutoScrollController] to scrollToIndex
///
///[keyPrefix] namespaces the widget key per [MarkdownWidget] instance so keys
///don't collide when several are mounted at once. The [AutoScrollController]
///scrolls by [index] (not the key), so this is purely an identity fix.
Widget wrapByAutoScroll(int index, Widget child, AutoScrollController controller,
    [String keyPrefix = '']) {
  return AutoScrollTag(
    key: ValueKey('$keyPrefix-$index'),
    controller: controller,
    index: index,
    child: child,
    highlightColor: Colors.black.toOpacity(0.1),
  );
}
