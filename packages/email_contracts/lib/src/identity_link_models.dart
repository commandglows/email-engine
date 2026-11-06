/// Public, non-secret fingerprint state for one account link.
///
/// [fingerprint] is non-null exactly when [linked] is true. Both values are
/// validated by the transport before they reach the UI.
final class IdentityLinkStatus {
  const IdentityLinkStatus({required this.linked, this.fingerprint});

  final bool linked;
  final String? fingerprint;

  @override
  bool operator ==(Object other) =>
      other is IdentityLinkStatus &&
      other.linked == linked &&
      other.fingerprint == fingerprint;

  @override
  int get hashCode => Object.hash(linked, fingerprint);

  @override
  String toString() =>
      'IdentityLinkStatus(linked: $linked, fingerprint: $fingerprint)';
}

/// One-time pairing code. The code is a credential while it is valid, so
/// [toString] deliberately omits it.
final class IdentityLinkCode {
  const IdentityLinkCode({required this.code, required this.expiresAt});

  final String code;

  /// Expiry instant in UTC.
  final DateTime expiresAt;

  @override
  bool operator ==(Object other) =>
      other is IdentityLinkCode &&
      other.code == code &&
      other.expiresAt == expiresAt;

  @override
  int get hashCode => Object.hash(code, expiresAt);

  @override
  String toString() => 'IdentityLinkCode(expiresAt: $expiresAt)';
}

/// Failure that exposes only a stable server error code, never raw text.
abstract interface class CodedFailure {
  String get code;
}

/// Port for linking this account to another app account with a one-time code.
///
/// Implementations return validated values and throw a [CodedFailure] for
/// server or transport errors.
abstract interface class IdentityLinkGateway {
  Future<IdentityLinkStatus> status();
  Future<IdentityLinkCode> createLinkCode();
  Future<IdentityLinkStatus> confirmLinkCode(String code);
}
