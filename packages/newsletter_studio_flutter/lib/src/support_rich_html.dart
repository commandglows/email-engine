import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;

import 'support_models.dart';

const _blockedElements = {
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

final _lengthAttribute = RegExp(r'^\d{1,4}(px|%)?$');
final _colorAttribute = RegExp(
  r'^(#[0-9a-f]{3,8}|[a-z]{3,20})$',
  caseSensitive: false,
);
final _alignAttribute = RegExp(
  r'^(left|center|right|justify)$',
  caseSensitive: false,
);
final _valignAttribute = RegExp(
  r'^(top|middle|bottom|baseline)$',
  caseSensitive: false,
);
final _countAttribute = RegExp(r'^\d{1,3}$');
final _sizeAttribute = RegExp(r'^[1-7]$');
final _unsafeStyle = RegExp(
  r'url\s*\(|expression\s*\(|javascript:|@import|behavior'
  r'|-moz-binding|[\\<>]|/\*',
  caseSensitive: false,
);

/// Defense in depth for email HTML: no scripts, forms, embedded views, style
/// sheets, CSS URLs or non-HTTPS resources, even if a backend returns more.
String safeEmailHtml(String html) {
  final document = parser.parseFragment(html);
  for (final element in document.querySelectorAll('*').toList()) {
    if (_blockedElements.contains(element.localName)) {
      element.remove();
      continue;
    }
    final kept = <String, String>{};
    element.attributes.forEach((name, value) {
      final cleaned = _cleanAttribute(
        element.localName,
        name.toString(),
        value,
      );
      if (cleaned != null) kept[name.toString()] = cleaned;
    });
    element.attributes.clear();
    kept.forEach((name, value) => element.attributes[name] = value);
    if (element.localName == 'img' && !kept.containsKey('src')) {
      element.remove();
    }
  }
  return document.outerHtml;
}

String? _cleanAttribute(String? tag, String name, String value) {
  final text = value.trim();
  switch (name) {
    case 'style':
      final safe = text.length <= 500 && !_unsafeStyle.hasMatch(text);
      return safe ? text : null;
    case 'src':
      return tag == 'img' && _isHttps(text) ? text : null;
    case 'href':
      return tag == 'a' && _isHttps(text) ? text : null;
    case 'alt':
      if (tag != 'img') return null;
      return text.length > 300 ? text.substring(0, 300) : text;
    case 'align':
      return _alignAttribute.hasMatch(text) ? text : null;
    case 'valign':
      return _valignAttribute.hasMatch(text) ? text : null;
    case 'bgcolor':
    case 'color':
      return _colorAttribute.hasMatch(text) ? text : null;
    case 'width':
    case 'height':
      return _lengthAttribute.hasMatch(text) ? text : null;
    case 'border':
    case 'cellpadding':
    case 'cellspacing':
    case 'colspan':
    case 'rowspan':
      return _countAttribute.hasMatch(text) ? text : null;
    case 'size':
      return _sizeAttribute.hasMatch(text) ? text : null;
    default:
      return null;
  }
}

bool _isHttps(String value) {
  final uri = Uri.tryParse(value);
  return uri != null &&
      uri.scheme == 'https' &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty;
}

/// Renders sanitized email HTML natively: text, layout and HTTPS images.
/// Links open only after confirmation, and only when [onOpenLink] is given.
class SupportRichHtml extends StatelessWidget {
  const SupportRichHtml({super.key, required this.html, this.onOpenLink});

  final String html;
  final Future<void> Function(Uri)? onOpenLink;

  @override
  Widget build(BuildContext context) => SelectionArea(
    child: HtmlWidget(
      safeEmailHtml(html),
      textStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5),
      customWidgetBuilder: _imageBuilder,
      onTapUrl: (value) => _openLink(context, value),
    ),
  );

  Widget? _imageBuilder(dom.Element element) {
    if (element.localName != 'img') return null;
    final alt = element.attributes['alt'] ?? '';
    final label = alt.isEmpty ? '[Image]' : '[Image : $alt]';
    final src = Uri.tryParse(element.attributes['src'] ?? '');
    if (src == null || src.scheme != 'https') return Text(label);
    return Image.network(
      src.toString(),
      width: double.tryParse(element.attributes['width'] ?? ''),
      height: double.tryParse(element.attributes['height'] ?? ''),
      semanticLabel: alt.isEmpty ? null : alt,
      errorBuilder: (context, error, stackTrace) => Text(label),
    );
  }

  Future<bool> _openLink(BuildContext context, String value) async {
    final uri = Uri.tryParse(value);
    final open = onOpenLink;
    if (open == null ||
        uri == null ||
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
    if (confirmed == true) await open(uri);
    return true;
  }
}

/// Body of one message: rich layout when HTML exists, with a plain-text switch.
class SupportMessageBody extends StatefulWidget {
  const SupportMessageBody({super.key, required this.message, this.onOpenLink});

  final SupportMessage message;
  final Future<void> Function(Uri)? onOpenLink;

  @override
  State<SupportMessageBody> createState() => _SupportMessageBodyState();
}

class _SupportMessageBodyState extends State<SupportMessageBody> {
  bool _plain = false;

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final theme = Theme.of(context);
    final text = SelectableText(
      message.text.isEmpty ? 'Aucun contenu texte disponible.' : message.text,
      style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
    );
    final html = message.html;
    if (html == null || html.trim().isEmpty) return text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => setState(() => _plain = !_plain),
            child: Text(_plain ? 'Mise en page' : 'Texte seul'),
          ),
        ),
        if (_plain)
          text
        else
          SupportRichHtml(html: html, onOpenLink: widget.onOpenLink),
      ],
    );
  }
}
