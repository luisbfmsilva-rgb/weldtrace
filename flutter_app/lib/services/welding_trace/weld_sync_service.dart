import 'weld_certificate.dart';
import 'weld_registry.dart';

// ── SyncResult ────────────────────────────────────────────────────────────────

/// The outcome of a single synchronisation attempt.
///
/// Use the factory constructors to create instances:
///
/// ```dart
/// SyncResult.offline()          // no network — device or sync disabled
/// SyncResult.success()          // record accepted by remote API
/// SyncResult.failure('reason')  // network or server error
/// ```
class SyncResult {
  const SyncResult._({
    required this.success,
    required this.offline,
    this.message,
  });

  /// Constructs a result representing disabled or unavailable synchronisation.
  ///
  /// [success] is `false`; [offline] is `true`.
  factory SyncResult.offline() => const SyncResult._(
        success: false,
        offline: true,
        message: 'Sync is offline or disabled.',
      );

  /// Constructs a successful synchronisation result.
  ///
  /// [success] is `true`; [offline] is `false`.
  factory SyncResult.success([String? message]) => SyncResult._(
        success: true,
        offline: false,
        message: message,
      );

  /// Constructs a failure result (network or server error).
  ///
  /// [success] is `false`; [offline] is `false`.
  factory SyncResult.failure(String message) => SyncResult._(
        success: false,
        offline: false,
        message: message,
      );

  /// `true` if the remote API accepted the upload.
  final bool success;

  /// `true` if synchronisation is disabled or the device is offline.
  ///
  /// When `offline` is `true` the caller must **not** treat this as an error —
  /// the operation should be queued for retry when connectivity is restored.
  final bool offline;

  /// Human-readable description of the outcome.  May be `null` on success.
  final String? message;

  @override
  String toString() =>
      'SyncResult(success=$success, offline=$offline, message=$message)';
}

// ── WeldSyncService ───────────────────────────────────────────────────────────

/// Uploads weld artefacts to the remote WeldTrace SaaS registry.
///
/// The default implementation is **offline-first**: every method returns
/// [SyncResult.offline()] without making any network call.  This keeps the
/// application fully functional without network connectivity.
///
/// When SaaS synchronisation is enabled in a future release, inject a
/// configured instance via dependency injection and override the methods
/// to perform the actual HTTP calls.
///
/// ### Usage
///
/// ```dart
/// final sync   = WeldSyncService();
/// final result = await sync.uploadCertificate(cert);
/// if (!result.offline && !result.success) {
///   // handle error — queue for retry
/// }
/// ```
class WeldSyncService {
  const WeldSyncService();

  /// Uploads [cert] to the remote certificates endpoint.
  ///
  /// Returns [SyncResult.offline()] in the default implementation.
  /// The caller **must not** block weld completion on this result.
  Future<SyncResult> uploadCertificate(WeldCertificate cert) async {
    return SyncResult.offline();
  }

  /// Uploads [entry] to the remote registry endpoint.
  ///
  /// Returns [SyncResult.offline()] in the default implementation.
  /// The caller **must not** block weld completion on this result.
  Future<SyncResult> uploadRegistryEntry(WeldRegistryEntry entry) async {
    return SyncResult.offline();
  }
}
