import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/errors/app_exception.dart';
import '../../core/utils/result.dart';
import '../models/auth_models.dart';
import '../remote/auth_remote_data_source.dart';
import '../local/database/app_database.dart';
import 'package:drift/drift.dart';

/// Manages authentication state:
///   1. Calls the API
///   2. Stores tokens in secure storage
///   3. Seeds local DB with the user's assigned projects
class AuthRepository {
  AuthRepository({
    required this.remoteDataSource,
    required this.db,
    FlutterSecureStorage? secureStorage,
  }) : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final AuthRemoteDataSource remoteDataSource;
  final AppDatabase db;
  final FlutterSecureStorage _secureStorage;

  // Secure storage keys
  static const _keyAccessToken = 'wt_access_token';
  static const _keyRefreshToken = 'wt_refresh_token';
  static const _keyUser = 'wt_user';

  // ── Auth operations ───────────────────────────────────────────────────────

  Future<Result<AuthUser>> login({
    required String email,
    required String password,
  }) async {
    final result = await remoteDataSource.login(email: email, password: password);

    return result.when(
      success: (response) async {
        await _storeTokens(
          accessToken: response.accessToken,
          refreshToken: response.refreshToken,
        );
        await _storeUser(response.user);
        await _seedAssignedProjects(response.user.assignedProjects);
        return Success(response.user);
      },
      failure: (e) => Failure(e),
    );
  }

  Future<Result<AuthUser>> fetchCurrentUser() async {
    final result = await remoteDataSource.me();
    return result.when(
      success: (user) async {
        await _storeUser(user);
        await _seedAssignedProjects(user.assignedProjects);
        return Success(user);
      },
      failure: (e) => Failure(e),
    );
  }

  Future<Result<void>> logout() async {
    await remoteDataSource.logout();
    await _clearTokens();
    return const Success(null);
  }

  /// Requests a password-reset email for [email].
  ///
  /// Stub — the actual API integration (Supabase password reset) will be
  /// wired in a later sprint when the auth remote data source is extended.
  /// Returns [Success(null)] unconditionally so the UI can always show
  /// a confirmation message without leaking whether the address is registered.
  Future<Result<void>> requestPasswordReset(String email) async {
    return const Success(null);
  }

  Future<Result<String?>> refreshAccessToken() async {
    final refreshToken = await getRefreshToken();
    if (refreshToken == null) {
      return const Failure(AuthException('No refresh token stored'));
    }

    final result = await remoteDataSource.refresh(refreshToken: refreshToken);
    return result.when(
      success: (data) async {
        final newAccess = data['accessToken'] as String?;
        final newRefresh = data['refreshToken'] as String?;
        if (newAccess != null) {
          await _storeTokens(
            accessToken: newAccess,
            refreshToken: newRefresh ?? refreshToken,
          );
        }
        return Success(newAccess);
      },
      failure: (e) => Failure(e),
    );
  }

  // ── Token accessors ───────────────────────────────────────────────────────

  Future<String?> getAccessToken() =>
      _secureStorage.read(key: _keyAccessToken);

  Future<String?> getRefreshToken() =>
      _secureStorage.read(key: _keyRefreshToken);

  Future<AuthUser?> getStoredUser() async {
    final json = await _secureStorage.read(key: _keyUser);
    if (json == null) return null;
    try {
      return AuthUser.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<bool> isAuthenticated() async {
    final token = await getAccessToken();
    return token != null;
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  Future<void> _storeTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await Future.wait([
      _secureStorage.write(key: _keyAccessToken, value: accessToken),
      _secureStorage.write(key: _keyRefreshToken, value: refreshToken),
    ]);
  }

  Future<void> _storeUser(AuthUser user) =>
      _secureStorage.write(key: _keyUser, value: jsonEncode(user.toJson()));

  Future<void> _clearTokens() async {
    await Future.wait([
      _secureStorage.delete(key: _keyAccessToken),
      _secureStorage.delete(key: _keyRefreshToken),
      _secureStorage.delete(key: _keyUser),
    ]);
  }

  Future<void> _seedAssignedProjects(List<AssignedProject> projects) async {
    final rows = projects.map((p) => ProjectsTableCompanion(
          id: Value(p.id),
          companyId: const Value(''),    // filled from /projects call
          name: Value(p.name),
          status: Value(p.status),
          location: Value(p.location),
          syncStatus: const Value('synced'),
          lastSyncedAt: Value(DateTime.now()),
        )).toList();

    await db.projectsDao.upsertAll(rows);
  }
}
