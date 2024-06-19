// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;

import '_functions_io.dart' if (dart.library.html) '_functions_web.dart';
import 'style_sheet.dart';
import 'widget.dart';

const List<String> _kBlockTags = <String>[
  'p',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'li',
  'blockquote',
  'pre',
  'ol',
  'ul',
  'hr',
  'table',
  'thead',
  'tbody',
  'tr',
  'tabs'
];

const _aReg =
    "http[s]?://(?:[a-zA-Z]|[0-9]|[\$-_@.&#+]|[!*\(\),]|(?:%[0-9a-fA-F][0-9a-fA-F]))+";
const List<String> _kListTags = <String>['ul', 'ol'];

const List<String> kImgType = [
  'png',
  'jpg',
  'JPEG',
  'gif',
  'jpeg',
];
const List<String> kVideoType = ['mp4', 'flv', 'avi'];

bool _isBlockTag(String? tag) => _kBlockTags.contains(tag);

bool _isListTag(String tag) => _kListTags.contains(tag);

class _BlockElement {
  _BlockElement(this.tag, {this.label});

  final String? tag;
  final String? label;
  final List<Widget> children = <Widget>[];

  int nextListIndex = 0;
}

class _TableElement {
  final List<TableRow> rows = <TableRow>[];
}

class _TabsElement {
  final List<_TabsRow> rows = <_TabsRow>[];
}

/// A collection of widgets that should be placed adjacent to (inline with)
/// other inline elements in the same parent block.
///
/// Inline elements can be textual (a/em/strong) represented by [RichText]
/// widgets or images (img) represented by [Image.network] widgets.
///
/// Inline elements can be nested within other inline elements, inheriting their
/// parent's style along with the style of the block they are in.
///
/// When laying out inline widgets, first, any adjacent RichText widgets are
/// merged, then, all inline widgets are enclosed in a parent [Wrap] widget.
class _InlineElement {
  _InlineElement(this.tag, {this.style});

  final String? tag;

  /// Created by merging the style defined for this element's [tag] in the
  /// delegate's [MarkdownStyleSheet] with the style of its parent.
  final TextStyle? style;

  final List<Widget> children = <Widget>[];
}

/// A delegate used by [MarkdownBuilder] to control the widgets it creates.
abstract class MarkdownBuilderDelegate {
  /// Returns a gesture recognizer to use for an `a` element with the given
  /// text, `href` attribute, and title.
  GestureRecognizer createLink(String text, String? href, String title);

  /// Returns formatted text to use to display the given contents of a `pre`
  /// element.
  ///
  /// The `styleSheet` is the value of [MarkdownBuilder.styleSheet].
  TextSpan formatText(MarkdownStyleSheet styleSheet, String code);
}

/// Builds a [Widget] tree from parsed Markdown.
///
/// See also:
///
///  * [Markdown], which is a widget that parses and displays Markdown.
class MarkdownBuilder implements md.NodeVisitor {
  /// Creates an object that builds a [Widget] tree from parsed Markdown.
  MarkdownBuilder(
      {required this.delegate,
      required this.selectable,
      required this.styleSheet,
      required this.imageDirectory,
      required this.imageBuilder,
      required this.checkboxBuilder,
      required this.bulletBuilder,
      required this.builders,
      required this.listItemCrossAxisAlignment,
      this.fitContent = false,
      this.maxWidth,
      this.onTapText,
      this.softLineBreakPattern = false});
  final bool softLineBreakPattern;

  final double? maxWidth;

  /// A delegate that controls how link and `pre` elements behave.
  final MarkdownBuilderDelegate delegate;

  /// If true, the text is selectable.
  ///
  /// Defaults to false.
  final bool selectable;

  /// Defines which [TextStyle] objects to use for each type of element.
  final MarkdownStyleSheet styleSheet;

  /// The base directory holding images referenced by Img tags with local or network file paths.
  final String? imageDirectory;

  /// Call when build an image widget.
  final MarkdownImageBuilder? imageBuilder;

  /// Call when build a checkbox widget.
  final MarkdownCheckboxBuilder? checkboxBuilder;

  /// Called when building a custom bullet.
  final MarkdownBulletBuilder? bulletBuilder;

  /// Call when build a custom widget.
  final Map<String, MarkdownElementBuilder> builders;

  /// Whether to allow the widget to fit the child content.
  final bool fitContent;

  /// Controls the cross axis alignment for the bullet and list item content
  /// in lists.
  ///
  /// Defaults to [MarkdownListItemCrossAxisAlignment.baseline], which
  /// does not allow for intrinsic height measurements.
  final MarkdownListItemCrossAxisAlignment listItemCrossAxisAlignment;

  /// Default tap handler used when [selectable] is set to true
  final VoidCallback? onTapText;

  final List<String> _listIndents = <String>[];
  final List<_BlockElement> _blocks = <_BlockElement>[];
  final List<_TableElement> _tables = <_TableElement>[];
  final List<_TabsElement> _tabs = <_TabsElement>[];

  final List<_InlineElement> _inlines = <_InlineElement>[];
  final List<GestureRecognizer> _linkHandlers = <GestureRecognizer>[];
  String? _currentBlockTag;
  String? _lastTag;
  bool _isInBlockquote = false;

  /// Returns widgets that display the given Markdown nodes.
  ///
  /// The returned widgets are typically used as children in a [ListView].
  List<Widget> build(List<md.Node> nodes) {
    _listIndents.clear();
    _blocks.clear();
    _tables.clear();
    _tabs.clear();
    _inlines.clear();
    _linkHandlers.clear();
    _isInBlockquote = false;

    _blocks.add(_BlockElement(null));
    nodes.forEach((element) {
      forEachElement(element, children: nodes);
    });
    forEachTabs(nodes);
    var i = 0;
    while (i < nodes.length) {
      var end = i;

      final curNote = nodes[i];
      for (var j = i; j < nodes.length; j++) {
        final node = nodes[j];

        if (node is md.Element &&
            node.tag == 'pre' &&
            (node as dynamic).label != null &&
            (node as dynamic).label!.isNotEmpty) {
          end += 1;
        } else {
          break;
        }
      }
      if (curNote is md.Element) {
        forEachElement(curNote);
      }
      if (end - i > 1) {
        final item = md.Element('tabs', nodes.sublist(i, end));
        nodes.replaceRange(i, end, [item]);
      }
      i += 1;
    }
    for (final md.Node node in nodes) {
      assert(_blocks.length == 1);
      node.accept(this);
    }

    assert(_tables.isEmpty);
    assert(_inlines.isEmpty);
    assert(!_isInBlockquote);
    return _blocks.single.children;
  }

  forEachTabs(List<md.Node>? children) {
    if (children == null || children.length == 0) {
      return;
    }
    var i = 0;
    while (i < children.length) {
      var end = i;

      final curNote = children[i];
      if (curNote is md.Element) {
        forEachTabs(curNote.children);
      }
      for (var j = i; j < children.length; j++) {
        final node = children[j];

        if (node is md.Element &&
            node.tag == 'pre' &&
            (node as dynamic).label != null &&
            (node as dynamic).label!.isNotEmpty) {
          end += 1;
        } else {
          break;
        }
      }
      if (curNote is md.Element) {
        forEachElement(curNote);
      }
      if (end - i > 1) {
        final item = md.Element('tabs', children.sublist(i, end));
        children.replaceRange(i, end, [item]);
      }
      i += 1;
    }
  }

  forEachElement(md.Node node, {List<md.Node>? children}) {
    if (node is md.Element) {
      if (node.children == null ||
          node.children?.length == 0 ||
          node.tag == 'pre' ||
          node.tag == 'a') {
        final str = node.textContent;
        List<md.Node> nodes = [];
        if ([...kVideoType, ...kImgType].contains(str.split('.').last)) {
          nodes.add(md.Element('img', null)
            ..attributes.addAll({'src': str, 'alt': ''}));
          final i = children?.indexOf(node) ?? -1;

          if (i >= 0) {
            children?[i] = nodes.first;
          }
        }
      } else {
        for (var item in node.children!) {
          forEachElement(item, children: node.children);
        }
      }
    } else if (node is md.Text) {
      final str = node.textContent;

      final iReg = '/upload.*?.(${[...kImgType, ...kVideoType].join("|")})';

      List<md.Node> nodes = [];
      var index = 0;
      bool isChange = false;
      RegExp('($_aReg)|($iReg)').allMatches(str).forEach((element) {
        isChange = true;
        final start = element.start;
        final end = element.end;

        if (index != start) {
          nodes.add(md.Text(str.substring(index, start)));
        }
        final s = str.substring(start, end).replaceAll(' ', '');

        if ([...kImgType, ...kVideoType].contains(s.split('.').last)) {
          nodes.add(md.Element('img', null)
            ..attributes.addAll({'src': s, 'alt': ''}));
        } else {
          nodes.add(md.Element('a', [md.Text(s)])
            ..attributes.addAll({
              'href': s,
            }));
        }
        index = end;
      });

      if (isChange) {
        if (str.length > index) {
          nodes.add(md.Text(str.substring(index, str.length)));
        }
        final i = children?.indexOf(node) ?? -1;
        if (nodes.length > 1) {
          children?[i] = md.Element('', nodes);
        } else if (nodes.length == 1) {
          children?[i] = nodes.first;
        }
      }
    }
  }

  @override
  bool visitElementBefore(md.Element element) {
    final String tag = element.tag;
    _currentBlockTag ??= tag;

    if (builders.containsKey(tag)) {
      builders[tag]!.visitElementBefore(element);
    }

    int? start;
    if (_isBlockTag(tag)) {
      _addAnonymousBlockIfNeeded();
      if (_isListTag(tag)) {
        _listIndents.add(tag);
        if (element.attributes['start'] != null)
          start = int.parse(element.attributes['start']!) - 1;
      } else if (tag == 'blockquote') {
        _isInBlockquote = true;
      } else if (tag == 'tabs') {
        _tabs.add(_TabsElement());
      } else if (tag == 'table') {
        _tables.add(_TableElement());
      } else if (tag == 'tr') {
        final int length = _tables.single.rows.length;
        BoxDecoration? decoration =
            styleSheet.tableCellsDecoration as BoxDecoration?;
        if (length == 0 || length.isOdd) {
          decoration = null;
        }
        _tables.single.rows.add(TableRow(
          decoration: decoration,
          children: <Widget>[],
        ));
      }
      final _BlockElement bElement = _BlockElement(tag);
      if (start != null) {
        bElement.nextListIndex = start;
      }
      _blocks.add(bElement);
    } else {
      if (tag == 'a') {
        final String? text = extractTextFromElement(element);
        // Don't add empty links
        if (text == null) {
          return false;
        }
        final String? destination = element.attributes['href'];
        final String title = element.attributes['title'] ?? '';

        _linkHandlers.add(
          delegate.createLink(text, destination, title),
        );
      }

      _addParentInlineIfNeeded(_blocks.last.tag);

      // The Markdown parser passes empty table data tags for blank
      // table cells. Insert a text node with an empty string in this
      // case for the table cell to get properly created.
      if (element.tag == 'td' &&
          element.children != null &&
          element.children!.isEmpty) {
        element.children!.add(md.Text(''));
      }

      final TextStyle parentStyle = _inlines.last.style!;
      _inlines.add(_InlineElement(
        tag,
        style: parentStyle.merge(styleSheet.styles[tag]),
      ));
    }

    return true;
  }

  /// Returns the text, if any, from [element] and its descendants.
  String? extractTextFromElement(md.Node element) {
    return element is md.Element && (element.children?.isNotEmpty ?? false)
        ? element.children!
            .map((md.Node e) =>
                e is md.Text ? e.text : extractTextFromElement(e))
            .join('')
        : (element is md.Element && (element.attributes.isNotEmpty)
            ? element.attributes['alt']
            : '');
  }

  @override
  void visitText(md.Text text) {
    // Don't allow text directly under the root.
    if (_blocks.last.tag == null) {
      return;
    }

    _addParentInlineIfNeeded(_blocks.last.tag);

    // Define trim text function to remove spaces from text elements in
    // accordance with Markdown specifications.
    String trimText(String text) {
      // The leading spaces pattern is used to identify spaces
      // at the beginning of a line of text.
      final RegExp _leadingSpacesPattern = RegExp(r'^ *');

      // The soft line break pattern is used to identify the spaces at the end of a
      // line of text and the leading spaces in the immediately following the line
      // of text. These spaces are removed in accordance with the Markdown
      // specification on soft line breaks when lines of text are joined.
      final RegExp _softLineBreakPattern = RegExp(r' ?\n *');

      // Leading spaces following a hard line break are ignored.
      // https://github.github.com/gfm/#example-657
      if (_lastTag == 'br') {
        text = text.replaceAll(_leadingSpacesPattern, '');
      }

      if (softLineBreakPattern) {
        return text;
      }
      // Spaces at end of the line and beginning of the next line are removed.
      // https://github.github.com/gfm/#example-670
      return text.replaceAll(_softLineBreakPattern, ' ');
    }

    Widget? child;
    if (_blocks.isNotEmpty && builders.containsKey(_blocks.last.tag)) {
      child = builders[_blocks.last.tag!]!
          .visitText(text, styleSheet.styles[_blocks.last.tag!]);
    } else if (_blocks.last.tag == 'pre') {
      child = Scrollbar(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: styleSheet.codeblockPadding,
          child: _buildRichText(delegate.formatText(styleSheet, text.text)),
        ),
      );
    } else {
      child = _buildRichText(
        TextSpan(
          style: _isInBlockquote
              ? styleSheet.blockquote!.merge(_inlines.last.style)
              : _inlines.last.style,
          text: _isInBlockquote ? text.text : trimText(text.text),
          recognizer: _linkHandlers.isNotEmpty ? _linkHandlers.last : null,
        ),
        textAlign: _textAlignForBlockTag(_currentBlockTag),
      );
    }
    if (child != null) {
      _inlines.last.children.add(child);
    }
  }

  @override
  void visitElementAfter(md.Element element) {
    final String tag = element.tag;

    if (_isBlockTag(tag)) {
      _addAnonymousBlockIfNeeded();

      final _BlockElement current = _blocks.removeLast();
      Widget child;

      if (current.children.isNotEmpty) {
        child = Column(
          crossAxisAlignment: fitContent
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.stretch,
          children: current.children,
        );
      } else {
        child = const SizedBox();
      }

      if (_isListTag(tag)) {
        assert(_listIndents.isNotEmpty);
        _listIndents.removeLast();
      } else if (tag == 'li') {
        if (_listIndents.isNotEmpty) {
          if (element.children!.isEmpty) {
            element.children!.add(md.Text(''));
          }
          Widget bullet;
          final dynamic el = element.children![0];
          if (el is md.Element && el.attributes['type'] == 'checkbox') {
            final bool val = el.attributes['checked'] != 'false';
            bullet = _buildCheckbox(val);
          } else {
            bullet = _buildBullet(_listIndents.last);
          }
          child = Row(
            textBaseline: listItemCrossAxisAlignment ==
                    MarkdownListItemCrossAxisAlignment.start
                ? null
                : TextBaseline.alphabetic,
            crossAxisAlignment: listItemCrossAxisAlignment ==
                    MarkdownListItemCrossAxisAlignment.start
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.baseline,
            children: <Widget>[
              SizedBox(
                width: styleSheet.listIndent! +
                    styleSheet.listBulletPadding!.left +
                    styleSheet.listBulletPadding!.right,
                child: bullet,
              ),
              Expanded(child: child)
            ],
          );
        }
      } else if (tag == 'tabs') {
        child = _TabsMarkdownWidget(
          _tabs.removeLast().rows,
          textStyle: styleSheet.h3,
          dividerColor: styleSheet.tableBorder?.bottom.color,
        );
      } else if (tag == 'table') {
        final _rows = _tables.removeLast().rows;

        var count = 1;
        _rows.forEach((element) {
          final l = element.children.length;
          if (l > count) count = l;
        });
        final _w = (maxWidth ??
                (MediaQueryData.fromWindow(ui.window).size.width - 30)) -
            count * 10;
        child = Scrollbar(
          child: SingleChildScrollView(
            padding: EdgeInsets.zero,
            scrollDirection: Axis.horizontal,
            child: Table(
              defaultColumnWidth: count <= 2
                  ? FixedColumnWidth(_w / count)
                  : MinColumnWidth(
                      FixedColumnWidth(180), IntrinsicColumnWidth()),
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              border: styleSheet.tableBorder,
              children: _rows,
            ),
          ),
        );
      } else if (tag == 'blockquote') {
        _isInBlockquote = false;
        child = DecoratedBox(
          decoration: styleSheet.blockquoteDecoration!,
          child: Padding(
            padding: styleSheet.blockquotePadding!,
            child: child,
          ),
        );
      } else if (tag == 'pre') {
        if ((element as dynamic).label != null &&
            (element as dynamic).label!.isNotEmpty &&
            _tabs.length > 0) {
          _tabs.last.rows.add(_TabsRow(
              (element as dynamic).label!,
              DecoratedBox(
                decoration: styleSheet.codeblockDecoration!,
                child: child,
              )));
        } else {
          child = DecoratedBox(
            decoration: styleSheet.codeblockDecoration!,
            child: child,
          );
        }
      } else if (tag == 'hr') {
        child = Container(decoration: styleSheet.horizontalRuleDecoration);
      }

      _addBlockChild(child);
    } else {
      final _InlineElement current = _inlines.removeLast();
      final _InlineElement parent = _inlines.last;

      if (builders.containsKey(tag)) {
        final Widget? child =
            builders[tag]!.visitElementAfter(element, styleSheet.styles[tag]);
        if (child != null) {
          current.children[0] = child;
        }
      } else if (tag == 'img') {
        // create an image widget for this image
        current.children.add(_buildImage(
          element.attributes['src']!,
          element.attributes['title'],
          element.attributes['alt'],
        ));
      } else if (tag == 'br') {
        current.children.add(_buildRichText(const TextSpan(text: '\n')));
      } else if (tag == 'th' || tag == 'td') {
        TextAlign? align;
        final String? style = element.attributes['style'];
        if (style == null) {
          align = tag == 'th' ? styleSheet.tableHeadAlign : TextAlign.left;
        } else {
          final RegExp regExp = RegExp(r'text-align: (left|center|right)');
          final Match match = regExp.matchAsPrefix(style)!;
          switch (match[1]) {
            case 'left':
              align = TextAlign.left;
              break;
            case 'center':
              align = TextAlign.center;
              break;
            case 'right':
              align = TextAlign.right;
              break;
          }
        }
        final Widget child = _buildTableCell(
          _mergeInlineChildren(current.children, align),
          textAlign: align,
        );
        _tables.single.rows.last.children.add(child);
      } else if (tag == 'a') {
        _linkHandlers.removeLast();
      }

      if (current.children.isNotEmpty) {
        parent.children.addAll(current.children);
      }
    }
    if (_currentBlockTag == tag) {
      _currentBlockTag = null;
    }
    _lastTag = tag;
  }

  Widget _buildImage(String src, String? title, String? alt) {
    final List<String> parts = src.split('#');
    if (parts.isEmpty) {
      return const SizedBox();
    }

    final String path = parts.first;
    double? width;
    double? height;
    if (parts.length == 2) {
      final List<String> dimensions = parts.last.split('x');
      if (dimensions.length == 2) {
        width = double.parse(dimensions[0]);
        height = double.parse(dimensions[1]);
      }
    }

    final Uri uri = Uri.parse(path);
    Widget child;
    if (imageBuilder != null) {
      child = imageBuilder!(uri, title, alt);
    } else {
      child = kDefaultImageBuilder(uri, imageDirectory, width, height);
    }

    if (_linkHandlers.isNotEmpty) {
      final TapGestureRecognizer recognizer =
          _linkHandlers.last as TapGestureRecognizer;
      return GestureDetector(child: child, onTap: recognizer.onTap);
    } else {
      return child;
    }
  }

  Widget _buildCheckbox(bool checked) {
    if (checkboxBuilder != null) {
      return checkboxBuilder!(checked);
    }
    return Padding(
      padding: styleSheet.listBulletPadding!,
      child: Icon(
        checked ? Icons.check_box : Icons.check_box_outline_blank,
        size: styleSheet.checkbox!.fontSize,
        color: styleSheet.checkbox!.color,
      ),
    );
  }

  Widget _buildBullet(String listTag) {
    final int index = _blocks.last.nextListIndex;
    final bool isUnordered = listTag == 'ul';

    if (bulletBuilder != null) {
      return Padding(
        padding: styleSheet.listBulletPadding!,
        child: bulletBuilder!(index,
            isUnordered ? BulletStyle.unorderedList : BulletStyle.orderedList),
      );
    }

    if (isUnordered) {
      return Padding(
        padding: styleSheet.listBulletPadding!,
        child: Text(
          '•',
          textAlign: TextAlign.center,
          style: styleSheet.listBullet,
        ),
      );
    }

    return Padding(
      padding: styleSheet.listBulletPadding!,
      child: Text(
        '${index + 1}.',
        textAlign: TextAlign.right,
        style: styleSheet.listBullet,
      ),
    );
  }

  Widget _buildTableCell(List<Widget?> children, {TextAlign? textAlign}) {
    return TableCell(
      child: Padding(
        padding: styleSheet.tableCellsPadding!,
        child: DefaultTextStyle(
          style: styleSheet.tableBody!,
          textAlign: textAlign,
          child: Wrap(children: children as List<Widget>),
        ),
      ),
    );
  }

  void _addParentInlineIfNeeded(String? tag) {
    if (_inlines.isEmpty) {
      _inlines.add(_InlineElement(
        tag,
        style: styleSheet.styles[tag!],
      ));
    }
  }

  void _addBlockChild(Widget child) {
    final _BlockElement parent = _blocks.last;
    if (parent.children.isNotEmpty) {
      parent.children.add(SizedBox(height: styleSheet.blockSpacing));
    }
    parent.children.add(child);
    parent.nextListIndex += 1;
  }

  void _addAnonymousBlockIfNeeded() {
    if (_inlines.isEmpty) {
      return;
    }

    WrapAlignment blockAlignment = WrapAlignment.start;
    TextAlign textAlign = TextAlign.start;
    if (_isBlockTag(_currentBlockTag)) {
      blockAlignment = _wrapAlignmentForBlockTag(_currentBlockTag);
      textAlign = _textAlignForBlockTag(_currentBlockTag);
    }

    final _InlineElement inline = _inlines.single;
    if (inline.children.isNotEmpty) {
      final List<Widget> mergedInlines = _mergeInlineChildren(
        inline.children,
        textAlign,
      );
      final Wrap wrap = Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: mergedInlines,
        alignment: blockAlignment,
      );
      _addBlockChild(wrap);
      _inlines.clear();
    }
  }

  /// Merges adjacent [TextSpan] children
  List<Widget> _mergeInlineChildren(
    List<Widget> children,
    TextAlign? textAlign,
  ) {
    final List<Widget> mergedTexts = <Widget>[];
    for (final Widget child in children) {
      if (mergedTexts.isNotEmpty &&
          mergedTexts.last is RichText &&
          child is RichText) {
        final RichText previous = mergedTexts.removeLast() as RichText;
        final TextSpan previousTextSpan = previous.text as TextSpan;
        final List<TextSpan> children = previousTextSpan.children != null
            ? List<TextSpan>.from(previousTextSpan.children!)
            : <TextSpan>[previousTextSpan];
        children.add(child.text as TextSpan);
        final TextSpan? mergedSpan = _mergeSimilarTextSpans(children);
        mergedTexts.add(_buildRichText(
          mergedSpan,
          textAlign: textAlign,
        ));
      } else if (mergedTexts.isNotEmpty &&
          mergedTexts.last is SelectableText &&
          child is SelectableText) {
        final SelectableText previous =
            mergedTexts.removeLast() as SelectableText;
        final TextSpan previousTextSpan = previous.textSpan!;
        final List<TextSpan> children = previousTextSpan.children != null
            ? List<TextSpan>.from(previousTextSpan.children!)
            : <TextSpan>[previousTextSpan];
        if (child.textSpan != null) {
          children.add(child.textSpan!);
        }
        final TextSpan? mergedSpan = _mergeSimilarTextSpans(children);
        mergedTexts.add(
          _buildRichText(
            mergedSpan,
            textAlign: textAlign,
          ),
        );
      } else {
        mergedTexts.add(child);
      }
    }
    return mergedTexts;
  }

  TextAlign _textAlignForBlockTag(String? blockTag) {
    final WrapAlignment wrapAlignment = _wrapAlignmentForBlockTag(blockTag);
    switch (wrapAlignment) {
      case WrapAlignment.start:
        return TextAlign.start;
      case WrapAlignment.center:
        return TextAlign.center;
      case WrapAlignment.end:
        return TextAlign.end;
      case WrapAlignment.spaceAround:
        return TextAlign.justify;
      case WrapAlignment.spaceBetween:
        return TextAlign.justify;
      case WrapAlignment.spaceEvenly:
        return TextAlign.justify;
    }
  }

  WrapAlignment _wrapAlignmentForBlockTag(String? blockTag) {
    switch (blockTag) {
      case 'p':
        return styleSheet.textAlign;
      case 'h1':
        return styleSheet.h1Align;
      case 'h2':
        return styleSheet.h2Align;
      case 'h3':
        return styleSheet.h3Align;
      case 'h4':
        return styleSheet.h4Align;
      case 'h5':
        return styleSheet.h5Align;
      case 'h6':
        return styleSheet.h6Align;
      case 'ul':
        return styleSheet.unorderedListAlign;
      case 'ol':
        return styleSheet.orderedListAlign;
      case 'blockquote':
        return styleSheet.blockquoteAlign;
      case 'pre':
        return styleSheet.codeblockAlign;
      case 'hr':
        // print('Markdown did not handle hr for alignment');
        break;
      case 'li':
        // print('Markdown did not handle li for alignment');
        break;
    }
    return WrapAlignment.start;
  }

  /// Combine text spans with equivalent properties into a single span.
  TextSpan? _mergeSimilarTextSpans(List<TextSpan>? textSpans) {
    if (textSpans == null || textSpans.length < 2) {
      return TextSpan(children: textSpans);
    }

    final List<TextSpan> mergedSpans = <TextSpan>[textSpans.first];

    for (int index = 1; index < textSpans.length; index++) {
      final TextSpan nextChild = textSpans[index];
      if (nextChild is TextSpan &&
          nextChild.recognizer == mergedSpans.last.recognizer &&
          nextChild.semanticsLabel == mergedSpans.last.semanticsLabel &&
          nextChild.style == mergedSpans.last.style) {
        final TextSpan previous = mergedSpans.removeLast();
        mergedSpans.add(TextSpan(
          text: previous.toPlainText() + nextChild.toPlainText(),
          recognizer: previous.recognizer,
          semanticsLabel: previous.semanticsLabel,
          style: previous.style,
        ));
      } else {
        mergedSpans.add(nextChild);
      }
    }

    // When the mergered spans compress into a single TextSpan return just that
    // TextSpan, otherwise bundle the set of TextSpans under a single parent.
    return mergedSpans.length == 1
        ? mergedSpans.first
        : TextSpan(children: mergedSpans);
  }

  Widget _buildRichText(TextSpan? text, {TextAlign? textAlign}) {
    if (selectable) {
      return SelectableText.rich(
        text!,
        textScaleFactor: styleSheet.textScaleFactor,
        textAlign: textAlign ?? TextAlign.start,
        onTap: onTapText,
      );
    } else {
      return RichText(
        text: text!,
        textScaleFactor: styleSheet.textScaleFactor!,
        textAlign: textAlign ?? TextAlign.start,
      );
    }
  }
}

class TabsMarkdownElement implements MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    return Container();
  }

  @override
  void visitElementBefore(md.Element element) {}

  @override
  Widget? visitText(md.Text text, TextStyle? preferredStyle) {
    return Container();
  }
}

class _TabsRow {
  final String label;
  final Widget child;
  _TabsRow(this.label, this.child);
}

class _TabsMarkdownWidget extends StatefulWidget {
  final Color? lineColor;
  final TextStyle? textStyle;
  final Color? dividerColor;

  final List<_TabsRow> rows;
  _TabsMarkdownWidget(this.rows,
      {this.lineColor, this.textStyle, this.dividerColor});
  @override
  State<StatefulWidget> createState() => _TabsMarkdownWidgetState();
}

class _TabsMarkdownWidgetState extends State<_TabsMarkdownWidget> {
  var index = 0;
  @override
  Widget build(BuildContext context) {
    final dividerColor = widget.dividerColor ?? Theme.of(context).dividerColor;
    final backgroundColor = Theme.of(context).colorScheme.surface;

    return Column(
      children: [
        DefaultTabController(
            length: widget.rows.length,
            child: Stack(
              children: [
                Positioned(
                    left: 0,
                    bottom: 5,
                    right: 0,
                    height: 1,
                    child: Container(
                      decoration: BoxDecoration(
                          border: Border(
                              bottom:
                                  BorderSide(width: 1, color: dividerColor))),
                    )),
                Container(
                  height: 38,
                  width: double.infinity,
                  margin: EdgeInsets.only(bottom: 5),
                  child: TabBar(
                      isScrollable: true,
                      labelPadding: EdgeInsets.zero,
                      labelStyle: widget.textStyle,
                      labelColor: widget.textStyle?.color,
                      indicatorWeight: 0,
                      indicator: BoxDecoration(
                          border: Border(
                              bottom: BorderSide(
                                  width: 1, color: backgroundColor))),
                      padding: EdgeInsets.only(left: 8, right: 8),
                      tabAlignment: TabAlignment.start,
                      onTap: (i) => setState(() {
                            index = i;
                          }),
                      tabs: List.generate(widget.rows.length, (i) {
                        final seleted = i == index;
                        final element = widget.rows[i];
                        final side = BorderSide(width: 1, color: dividerColor);
                        return Tab(
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                height: 40,
                                decoration: BoxDecoration(
                                    color: backgroundColor,
                                    borderRadius: BorderRadius.vertical(
                                        top: Radius.circular(5)),
                                    border: seleted
                                        ? Border(
                                            top: side,
                                            left: side,
                                            right: side,
                                          )
                                        : Border(
                                            bottom: BorderSide(
                                                width: 1,
                                                color: dividerColor))),
                                padding: EdgeInsets.symmetric(horizontal: 10),
                                alignment: Alignment.center,
                                child: Text(
                                    '${element.label.substring(0, 1).toUpperCase()}${element.label.substring(1, element.label.length).toLowerCase()}'),
                              ),
                            ],
                          ),
                        );
                      }).toList()),
                ),
              ],
            )),
        widget.rows[index].child
      ],
    );
  }
}
