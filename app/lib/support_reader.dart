import 'package:flutter/material.dart';
import 'package:newsletter_studio_flutter/newsletter_studio_flutter.dart';
import 'package:source_sidebar_flutter/source_sidebar_flutter.dart';

class SupportReader extends StatelessWidget {
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
  static const _style = SourceSidebarStyle();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final message in thread.messages) ...[
        SizedBox(height: _style.gapLarge),
        Text(message.from, style: Theme.of(context).textTheme.titleSmall),
        Text(
          'À : ${message.to}${message.cc.isEmpty ? '' : '\nCc : ${message.cc}'}',
        ),
        if (message.date != null) Text('${message.date!.toLocal()}'),
        SizedBox(height: _style.gapSmall),
        SupportMessageBody(message: message, onOpenLink: onOpenLink),
        for (final attachment in message.attachments)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.download_outlined),
              label: Text('${attachment.name} · ${attachment.size} octets'),
              onPressed: busy ? null : () => onDownload(message, attachment),
            ),
          ),
        SizedBox(height: _style.gapSmall),
        const Divider(),
      ],
    ],
  );
}
