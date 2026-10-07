import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/parser.dart' as parser;
import 'package:newsletter_studio_flutter/newsletter_studio_flutter.dart';
import 'package:source_sidebar_flutter/source_sidebar_flutter.dart';

/// Defense in depth: no scripts, remote resources, inline CSS, embedded views,
/// or active forms, even if a backend accidentally returns unfiltered HTML.
String safeEmailHtml(String html) {
  final document = parser.parseFragment(html);
  const blocked = {
    'script',
    'style',
    'iframe',
    'object',
    'embed',
    'link',
    'meta',
    'base',
    'form',
    'input',
    'button',
    'textarea',
    'select',
    'svg',
    'math',
    'audio',
    'video',
    'source',
  };
  for (final element in document.querySelectorAll('*').toList()) {
    if (blocked.contains(element.localName)) {
      element.remove();
      continue;
    }
    final href = element.attributes['href'];
    final alt = element.attributes['alt'];
    element.attributes.clear();
    if (element.localName == 'a' && href != null) {
      final uri = Uri.tryParse(href);
      if (uri != null &&
          uri.scheme == 'https' &&
          uri.host.isNotEmpty &&
          uri.userInfo.isEmpty) {
        element.attributes['href'] = uri.toString();
      }
    }
    if (element.localName == 'img' && alt != null) {
      element.attributes['alt'] = alt;
    }
  }
  return document.outerHtml;
}

class SupportReader extends StatefulWidget {
  const SupportReader({
    super.key,
    required this.thread,
    required this.busy,
    required this.onDownload,
    required this.onOpenLink,
  });
  final SupportThread thread;
  final bool busy;
  final Future<void> Function(SupportMessage, SupportAttachment) onDownload;
  final Future<void> Function(Uri) onOpenLink;
  @override
  State<SupportReader> createState() => _SupportReaderState();
}

class _SupportReaderState extends State<SupportReader> {
  bool _plain = false;
  static const _style = SourceSidebarStyle();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (widget.thread.messages.any((m) => m.html?.isNotEmpty == true))
        Wrap(
          spacing: _style.gapSmall,
          children: [
            ChoiceChip(
              label: const Text('Lecture enrichie'),
              selected: !_plain,
              onSelected: (_) => setState(() => _plain = false),
            ),
            ChoiceChip(
              label: const Text('Texte seul'),
              selected: _plain,
              onSelected: (_) => setState(() => _plain = true),
            ),
          ],
        ),
      for (final message in widget.thread.messages) ...[
        SizedBox(height: _style.gapLarge),
        Text(message.from, style: Theme.of(context).textTheme.titleSmall),
        Text(
          'À : ${message.to}${message.cc.isEmpty ? '' : '\nCc : ${message.cc}'}',
        ),
        if (message.date != null) Text('${message.date!.toLocal()}'),
        SizedBox(height: _style.gapSmall),
        if (!_plain && message.html?.isNotEmpty == true)
          SelectionArea(
            child: HtmlWidget(
              safeEmailHtml(message.html!),
              textStyle: Theme.of(context).textTheme.bodyLarge,
              customWidgetBuilder: (element) => element.localName == 'img'
                  ? Text(
                      element.attributes['alt']?.isNotEmpty == true
                          ? '[Image : ${element.attributes['alt']}]'
                          : '[Image externe masquée]',
                    )
                  : null,
              onTapUrl: (value) async {
                final uri = Uri.tryParse(value);
                if (uri == null ||
                    uri.scheme != 'https' ||
                    uri.host.isEmpty ||
                    uri.userInfo.isNotEmpty) {
                  return true;
                }
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Ouvrir ce lien externe ?'),
                    content: SelectableText(uri.toString()),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Annuler'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Ouvrir'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) await widget.onOpenLink(uri);
                return true;
              },
            ),
          )
        else
          SelectableText(message.text),
        for (final attachment in message.attachments)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.download_outlined),
              label: Text('${attachment.name} · ${attachment.size} octets'),
              onPressed: widget.busy
                  ? null
                  : () => widget.onDownload(message, attachment),
            ),
          ),
        SizedBox(height: _style.gapSmall),
        const Divider(),
      ],
    ],
  );
}
