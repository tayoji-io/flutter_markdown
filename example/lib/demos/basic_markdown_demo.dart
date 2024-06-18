// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../shared/markdown_demo_widget.dart';
import '../shared/markdown_extensions.dart';

// ignore_for_file: public_member_api_docs

const String _notes =
    "m\n| head1 | head2 | head3 |\n| ------ | ------ | ------ |\n| column1 | column2 | column3 |\n| column1 | column2 | column3 |";

class BasicMarkdownDemo extends StatefulWidget implements MarkdownDemoWidget {
  const BasicMarkdownDemo({Key? key}) : super(key: key);

  static const String _title = 'Basic Markdown Demo';

  @override
  String get title => BasicMarkdownDemo._title;

  @override
  String get description => 'Shows the effect the four Markdown extension sets '
      'have on basic and extended Markdown tagged elements.';

  @override
  Future<String> get data =>
      rootBundle.loadString('assets/markdown_test_page.md');

  @override
  Future<String> get notes => Future<String>.value(_notes);

  @override
  _BasicMarkdownDemoState createState() => _BasicMarkdownDemoState();
}

class _BasicMarkdownDemoState extends State<BasicMarkdownDemo> {
  MarkdownExtensionSet _extensionSet = MarkdownExtensionSet.githubFlavored;

  final Map<String, MarkdownExtensionSet> _menuItems =
      Map<String, MarkdownExtensionSet>.fromIterables(
    MarkdownExtensionSet.values.map((MarkdownExtensionSet e) => e.displayTitle),
    MarkdownExtensionSet.values,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<String>(
        future: Future.value(_notes),
        builder: (BuildContext context, AsyncSnapshot<String> snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            return Column(
              children: <Widget>[
                // DropdownMenu<MarkdownExtensionSet>(
                //   items: _menuItems,
                //   label: 'Extension Set:',
                //   initialValue: _extensionSet,
                //   onChanged: (MarkdownExtensionSet? value) {
                //     if (value != _extensionSet) {
                //       setState(() {
                //         _extensionSet = value!;
                //       });
                //     }
                //   },
                // ),
                Expanded(
                  child: Markdown(
                    key: Key(_extensionSet.name),
                    data: snapshot.data!,
                    extensionSet: _extensionSet.value,
                    onTapLink: (String text, String? href, String title) =>
                        linkOnTapHandler(context, text, href, title),
                  ),
                ),
              ],
            );
          } else {
            return const CircularProgressIndicator();
          }
        },
      ),
    );
  }

  // Handle the link. The [href] in the callback contains information
  // from the link. The url_launcher package or other similar package
  // can be used to execute the link.
  Future<void> linkOnTapHandler(
    BuildContext context,
    String text,
    String? href,
    String title,
  ) async {
    showDialog<Widget>(
      context: context,
      builder: (BuildContext context) =>
          _createDialog(context, text, href, title),
    );
  }

  Widget _createDialog(
          BuildContext context, String text, String? href, String title) =>
      AlertDialog(
        title: const Text('Reference Link'),
        content: SingleChildScrollView(
          child: ListBody(
            children: <Widget>[
              Text(
                'See the following link for more information:',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Link text: $text',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Link destination: $href',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Link title: $title',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          )
        ],
      );
}
