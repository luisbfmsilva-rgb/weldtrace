/// Global configuration for the WeldTrace application.
///
/// All values are compile-time constants that can be overridden at
/// construction time (e.g. from remote feature flags or stored preferences).
/// The defaults keep the system fully offline and self-contained.
class WeldTraceConfig {
  const WeldTraceConfig({
    this.syncEnabled   = false,
    this.syncEndpoint,
  });

  /// When `false` (default) the synchronisation layer is dormant.
  ///
  /// No network calls are made; every [WeldSyncService] operation returns
  /// [SyncResult.offline()] immediately.  Set to `true` only when a valid
  /// [syncEndpoint] has been provided.
  final bool syncEnabled;

  /// Base URL of the remote WeldTrace API (e.g. `'https://api.weldtrace.io'`).
  ///
  /// `null` by default — the system must not attempt any network calls when
  /// this is null regardless of [syncEnabled].
  final String? syncEndpoint;

  /// Returns a copy of this configuration with the given fields replaced.
  WeldTraceConfig copyWith({
    bool?   syncEnabled,
    String? syncEndpoint,
  }) =>
      WeldTraceConfig(
        syncEnabled:  syncEnabled  ?? this.syncEnabled,
        syncEndpoint: syncEndpoint ?? this.syncEndpoint,
      );

  @override
  String toString() =>
      'WeldTraceConfig(syncEnabled=$syncEnabled, syncEndpoint=$syncEndpoint)';
}
