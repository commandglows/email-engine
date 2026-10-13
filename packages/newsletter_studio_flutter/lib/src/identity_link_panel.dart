import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'email_cockpit_tokens.dart';
import 'identity_link_models.dart';

/// Links this account to another app account with a one-time code.
///
/// The email address is never used as proof of identity. Codes and raw errors
/// are never logged or shown; failures display French copy keyed by code.
class IdentityLinkPanel extends StatefulWidget {
  const IdentityLinkPanel({
    super.key,
    required this.gateway,
    required this.providerLabel,
    required this.otherAppLabel,
    this.clock = DateTime.now,
  });

  final IdentityLinkGateway gateway;

  /// Name of the app hosting this panel, for example "ShipGlows".
  final String providerLabel;

  /// Name of the app holding the code, for example "ContentGlows".
  final String otherAppLabel;

  /// Injected time source for expiry display, so tests stay deterministic.
  final DateTime Function() clock;

  @override
  State<IdentityLinkPanel> createState() => _IdentityLinkPanelState();
}

class _IdentityLinkPanelState extends State<IdentityLinkPanel> {
  final _codeField = TextEditingController();
  IdentityLinkStatus? _status;
  IdentityLinkCode? _issued;
  String? _errorCode;
  bool _loading = true;
  bool _busy = false;
  bool _entering = false;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _codeField.dispose();
    super.dispose();
  }

  static String _codeOf(Object error) => switch (error) {
    CodedFailure(:final code) => code,
    _ => 'unavailable',
  };

  String _messageFor(String code) => switch (code) {
    'authentication_required' =>
      'Votre session a expiré. Reconnectez-vous à ${widget.providerLabel}, puis réessayez.',
    'link_code_invalid' =>
      'Ce code est invalide, déjà utilisé ou expiré. Générez un nouveau code dans ${widget.otherAppLabel}.',
    'identity_link_conflict' =>
      'Cette association est déjà utilisée par un autre compte. Vérifiez les comptes concernés avant de réessayer.',
    'identity_not_provisioned' =>
      'Votre compte ${widget.providerLabel} n’est pas encore prêt pour l’association. Réessayez plus tard.',
    'identity_link_unavailable' =>
      'L’association est momentanément indisponible. Réessayez dans un instant.',
    'rate_limited' =>
      'Trop de demandes rapprochées. Patientez un instant avant de réessayer.',
    'invalid_input' => 'Saisissez le code exactement tel qu’il a été généré.',
    _ => 'Le service est momentanément indisponible. Réessayez.',
  };

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorCode = null;
    });
    try {
      final status = await widget.gateway.status();
      if (!mounted) return;
      setState(() => _status = status);
    } catch (error) {
      if (mounted) setState(() => _errorCode = _codeOf(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _generate() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _errorCode = null;
    });
    try {
      final issued = await widget.gateway.createLinkCode();
      if (!mounted) return;
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
      setState(() => _issued = issued);
    } catch (error) {
      if (mounted) setState(() => _errorCode = _codeOf(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _hideCode() {
    _ticker?.cancel();
    _ticker = null;
    setState(() => _issued = null);
  }

  Future<void> _copy(String code) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await Clipboard.setData(ClipboardData(text: code));
      if (!mounted) return;
      messenger?.showSnackBar(const SnackBar(content: Text('Code copié.')));
    } catch (_) {
      if (!mounted) return;
      messenger?.showSnackBar(
        const SnackBar(
          content: Text(
            'Copie impossible. Sélectionnez le code et copiez-le manuellement.',
          ),
        ),
      );
    }
  }

  /// Confirmation is explicit: the user must accept the dialog before any call.
  Future<void> _requestConfirm() async {
    final code = _codeField.text.trim();
    if (_busy || code.isEmpty) return;
    setState(() {
      _busy = true;
      _errorCode = null;
    });
    var decided = false;
    void decide(BuildContext dialogContext, bool value) {
      if (decided) return;
      decided = true;
      Navigator.pop(dialogContext, value);
    }

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirmer l’association'),
        content: Text(
          'Associer définitivement ce compte ${widget.providerLabel} au compte ${widget.otherAppLabel} qui a généré ce code ?',
        ),
        actions: [
          TextButton(
            onPressed: () => decide(dialogContext, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => decide(dialogContext, true),
            child: const Text('Associer'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (confirmed != true) {
      setState(() => _busy = false);
      return;
    }
    try {
      await widget.gateway.confirmLinkCode(code);
      if (!mounted) return;
      _codeField.clear();
      setState(() => _entering = false);
      await _load();
    } catch (error) {
      if (mounted) setState(() => _errorCode = _codeOf(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _two(int value) => value.toString().padLeft(2, '0');

  String _expiryText(DateTime expiresAt) {
    final local = expiresAt.toLocal();
    final remaining = expiresAt.difference(widget.clock().toUtc());
    final time = '${_two(local.hour)}:${_two(local.minute)}';
    if (remaining <= Duration.zero) return 'Ce code a expiré à $time.';
    final minutes = remaining.inMinutes;
    final seconds = remaining.inSeconds % 60;
    return 'Expire à $time · encore $minutes min ${_two(seconds)} s';
  }

  Widget _issuedCode(BuildContext context, IdentityLinkCode issued) {
    final theme = Theme.of(context);
    final expired =
        issued.expiresAt.difference(widget.clock().toUtc()) <= Duration.zero;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (expired)
          const Text('Ce code a expiré. Générez-en un nouveau.')
        else ...[
          SelectableText(issued.code, style: theme.textTheme.headlineSmall),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => unawaited(_copy(issued.code)),
            icon: const Icon(Icons.copy),
            label: const Text('Copier le code'),
          ),
        ],
        Text(_expiryText(issued.expiresAt)),
        const Text(
          'Ne partagez ce code avec personne. Il expire dans 5 minutes.',
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
            onPressed: _hideCode,
            child: const Text('Masquer le code'),
          ),
        ),
      ],
    );
  }

  Widget _unlinked(BuildContext context) {
    final issued = _issued;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Associez ce compte à votre compte ${widget.otherAppLabel} pour partager vos boîtes mail. L’adresse email ne suffit jamais.',
        ),
        if (issued != null) _issuedCode(context, issued),
        if (_entering) ...[
          TextField(
            controller: _codeField,
            enabled: !_busy,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Code d’association',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => unawaited(_requestConfirm()),
          ),
          FilledButton(
            onPressed: _busy || _codeField.text.trim().isEmpty
                ? null
                : () => unawaited(_requestConfirm()),
            child: const Text('Associer'),
          ),
        ],
        Wrap(
          spacing: EmailCockpitLayout.smallGap,
          runSpacing: EmailCockpitLayout.smallGap,
          children: [
            FilledButton.icon(
              onPressed: _busy || _loading
                  ? null
                  : () => unawaited(_generate()),
              icon: const Icon(Icons.key),
              label: const Text('Générer un code'),
            ),
            OutlinedButton(
              onPressed: _busy || _loading
                  ? null
                  : () => setState(() => _entering = true),
              child: const Text('Saisir un code'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _linked(BuildContext context, String fingerprint) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.verified_outlined, color: theme.colorScheme.primary),
            const SizedBox(width: EmailCockpitLayout.gap),
            Expanded(
              child: Text(
                'Comptes associés',
                style: theme.textTheme.titleSmall,
              ),
            ),
          ],
        ),
        Text(
          '${widget.providerLabel} et ${widget.otherAppLabel} sont associés.',
        ),
        SelectableText(
          'Empreinte : $fingerprint — elle doit être identique dans ${widget.otherAppLabel}.',
        ),
      ],
    );
  }

  Widget _errorBanner(BuildContext context, String code) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(Icons.error_outline, color: theme.colorScheme.error),
        const SizedBox(width: EmailCockpitLayout.smallGap),
        Expanded(
          child: Text(
            _messageFor(code),
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ),
        TextButton(
          onPressed: _busy || _loading ? null : () => unawaited(_load()),
          child: const Text('Réessayer'),
        ),
      ],
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) {
      return const LinearProgressIndicator(
        semanticsLabel: 'Chargement de l’association',
      );
    }
    final status = _status;
    if (status == null) return const SizedBox.shrink();
    final fingerprint = status.fingerprint;
    if (status.linked && fingerprint != null) {
      return _linked(context, fingerprint);
    }
    return _unlinked(context);
  }

  @override
  Widget build(BuildContext context) {
    final code = _errorCode;
    return Card(
      child: Padding(
        padding: EmailCockpitLayout.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Association du compte',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (code != null) _errorBanner(context, code),
            _body(context),
          ],
        ),
      ),
    );
  }
}
