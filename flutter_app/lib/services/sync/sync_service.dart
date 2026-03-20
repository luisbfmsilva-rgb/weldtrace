import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/errors/app_exception.dart';
import '../../core/utils/result.dart';
import '../../data/models/sync_models.dart';
import '../../data/repositories/sync_repository.dart';
import '../../core/constants/app_constants.dart';

/// Orchestrates offline → cloud synchronisation.
///
/// Responsibilities:
///   - Monitors connectivity via [Connectivity]
///   - Triggers [syncUpload] when connectivity is restored
///   - Triggers [syncDownload] to pull server-side updates
///   - Tracks last-sync timestamp in [SharedPreferences]
///   - Implements exponential back-off retry on failure
///
/// Usage:
///   final service = SyncService(repository: repo);
///   service.start();             // begin automatic background sync
///   await service.syncNow();     // force an immediate sync
///   service.dispose();           // stop and clean up
class SyncService {
  SyncService({
    required this.repository,
    Logger? logger,
    Connectivity? connectivity,
  })  : _logger = logger ?? Logger(),
        _connectivity = connectivity ?? Connectivity();

  final SyncRepository repository;
  final Logger _logger;
  final Connectivity _connectivity;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _isRunning = false;
  bool _isSyncing = false;

  static const _prefKeyLastSync = 'wt_last_sync_ts';

  // Sync state stream for the UI to observe
  final _statusController = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get statusStream => _statusController.stream;
  SyncStatus _currentStatus = SyncStatus.idle;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  void start() {
    if (_isRunning) return;
    _isRunning = true;

    _connectivitySub = _connectivity.onConnectivityChanged.listen(
      (results) {
        final isConnected = results.any((r) => r != ConnectivityResult.none);
        if (isConnected && !_isSyncing) {
          _logger.d('[SyncService] Connectivity restored — triggering sync');
          syncNow();
        }
      },
    );

    _logger.i('[SyncService] Started');
  }

  void dispose() {
    _connectivitySub?.cancel();
    _statusController.close();
    _isRunning = false;
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Marks every local machine and project as pending, then runs a full
  /// sync cycle. Use this once to upload pre-existing device data to the
  /// cloud, or after reinstalling to ensure nothing is missing.
  Future<SyncResult> forceSyncAll() async {
    await repository.markAllLocalAsPending();
    return syncNow();
  }

  /// Force an immediate upload + download cycle.
  /// Returns the combined result of both operations.
  Future<SyncResult> syncNow({String? projectId}) async {
    if (_isSyncing) {
      _logger.d('[SyncService] Sync already in progress — skipping');
      return const SyncResult(uploaded: null, downloaded: null);
    }

    _isSyncing = true;
    _emitStatus(SyncStatus.syncing);

    try {
      // Step 1: Upload pending local records
      final uploadResult = await _uploadWithRetry();

      // Step 2: Download updates from cloud
      final lastSync = await _getLastSyncTimestamp();
      final downloadResult = await _downloadWithRetry(
        since: lastSync,
        projectId: projectId,
      );

      // Step 3: Update last-sync timestamp
      if (downloadResult is Success<SyncUpdatesResponse>) {
        await _setLastSyncTimestamp(DateTime.now());
      }

      _emitStatus(SyncStatus.success);
      _logger.i('[SyncService] Sync complete');

      return SyncResult(uploaded: uploadResult, downloaded: downloadResult);
    } catch (e) {
      _emitStatus(SyncStatus.error);
      _logger.e('[SyncService] Sync failed', error: e);
      return SyncResult(
        uploaded: Failure(SyncException('Sync failed', e)),
        downloaded: null,
      );
    } finally {
      _isSyncing = false;
    }
  }

  // ── Upload with retry ─────────────────────────────────────────────────────

  Future<Result<SyncUploadResult>> _uploadWithRetry() async {
    int attempt = 0;
    while (attempt < AppConstants.syncRetryMaxAttempts) {
      final result = await repository.syncUpload();
      if (result is Success<SyncUploadResult>) {
        return result;
      }
      attempt++;
      if (attempt < AppConstants.syncRetryMaxAttempts) {
        final delay = AppConstants.syncRetryBaseDelayMs * (1 << attempt);
        _logger.w('[SyncService] Upload attempt $attempt failed, retrying in ${delay}ms');
        await Future.delayed(Duration(milliseconds: delay));
      }
    }
    return const Failure(SyncException('Upload failed after max retries'));
  }

  // ── Download with retry ───────────────────────────────────────────────────

  Future<Result<SyncUpdatesResponse>> _downloadWithRetry({
    required DateTime since,
    String? projectId,
  }) async {
    int attempt = 0;
    while (attempt < AppConstants.syncRetryMaxAttempts) {
      final result = await repository.syncDownload(since: since, projectId: projectId);
      if (result is Success<SyncUpdatesResponse>) return result;
      attempt++;
      if (attempt < AppConstants.syncRetryMaxAttempts) {
        final delay = AppConstants.syncRetryBaseDelayMs * (1 << attempt);
        await Future.delayed(Duration(milliseconds: delay));
      }
    }
    return const Failure(SyncException('Download failed after max retries'));
  }

  // ── Timestamp helpers ─────────────────────────────────────────────────────

  Future<DateTime> _getLastSyncTimestamp() async {
    final prefs = await SharedPreferences.getInstance();
    final ts = prefs.getString(_prefKeyLastSync);
    if (ts == null) return DateTime.fromMillisecondsSinceEpoch(0);
    return DateTime.tryParse(ts) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  Future<void> _setLastSyncTimestamp(DateTime dt) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyLastSync, dt.toUtc().toIso8601String());
  }

  // ── Status helpers ────────────────────────────────────────────────────────

  void _emitStatus(SyncStatus status) {
    _currentStatus = status;
    if (!_statusController.isClosed) {
      _statusController.add(status);
    }
  }

  SyncStatus get currentStatus => _currentStatus;
}

// ── Supporting types ──────────────────────────────────────────────────────────

enum SyncStatus { idle, syncing, success, error }

class SyncResult {
  const SyncResult({
    required this.uploaded,
    required this.downloaded,
  });

  final Result<SyncUploadResult>? uploaded;
  final Result<SyncUpdatesResponse>? downloaded;

  bool get hasErrors =>
      uploaded is Failure || downloaded is Failure;
}
