import '../../core/network/api_client.dart';
import '../../core/utils/result.dart';
import '../models/sync_models.dart';

/// Remote data source for the sync endpoints.
class SyncRemoteDataSource {
  const SyncRemoteDataSource(this._api);

  final ApiClient _api;

  /// Push all pending local records to the cloud.
  Future<Result<SyncUploadResult>> upload(SyncUploadPayload payload) =>
      _api.post(
        '/sync/upload',
        payload.toJson(),
        (json) => SyncUploadResult.fromJson(json as Map<String, dynamic>),
      );

  /// Pull updates from the cloud since [since] timestamp.
  Future<Result<SyncUpdatesResponse>> getUpdates({
    required DateTime since,
    String? projectId,
  }) =>
      _api.get(
        '/sync/updates',
        (json) => SyncUpdatesResponse.fromJson(json as Map<String, dynamic>),
        queryParams: {
          'since': since.toUtc().toIso8601String(),
          if (projectId != null) 'projectId': projectId,
        },
      );
}
