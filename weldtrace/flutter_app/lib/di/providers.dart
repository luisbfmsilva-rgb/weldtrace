import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local/database/app_database.dart';
import '../data/remote/auth_remote_data_source.dart';
import '../data/remote/sync_remote_data_source.dart';
import '../data/repositories/auth_repository.dart';
import '../data/repositories/sync_repository.dart';
import '../data/repositories/weld_parameters_repository.dart';
import '../services/sync/sync_service.dart';
import '../services/sensor/sensor_service.dart';
import '../core/network/api_client.dart';
import '../presentation/welding/weld_setup_notifier.dart';

// ── Database ──────────────────────────────────────────────────────────────────

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

// ── API client ─────────────────────────────────────────────────────────────────

final apiClientProvider = Provider<ApiClient>((ref) {
  // Note: forward reference is safe because authRepositoryProvider only
  // reads apiClientProvider lazily; Riverpod handles circular deps via lazy eval.
  return ApiClient(
    tokenProvider: () => ref.read(authRepositoryProvider).getAccessToken(),
  );
});

// ── Auth repository ────────────────────────────────────────────────────────────

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final db = ref.watch(databaseProvider);
  final api = ref.watch(apiClientProvider);
  return AuthRepository(
    remoteDataSource: AuthRemoteDataSource(api),
    db: db,
  );
});

// ── Sync ───────────────────────────────────────────────────────────────────────

final syncRepositoryProvider = Provider<SyncRepository>((ref) {
  final db = ref.watch(databaseProvider);
  final api = ref.watch(apiClientProvider);
  return SyncRepository(
    remoteDataSource: SyncRemoteDataSource(api),
    db: db,
  );
});

final syncServiceProvider = Provider<SyncService>((ref) {
  final repo = ref.watch(syncRepositoryProvider);
  final service = SyncService(repository: repo);
  ref.onDispose(service.dispose);
  return service;
});

// ── Sensor ─────────────────────────────────────────────────────────────────────

final sensorServiceProvider = Provider<SensorService>((ref) {
  final db = ref.watch(databaseProvider);
  final service = SensorService(db: db);
  ref.onDispose(service.dispose);
  return service;
});

// ── Welding parameters ─────────────────────────────────────────────────────────

final weldParametersRepositoryProvider =
    Provider<WeldParametersRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return WeldParametersRepository(db: db);
});

/// Per-screen StateNotifier that drives the weld setup form.
/// Use [weldSetupProvider] in WeldSetupScreen only.
final weldSetupProvider =
    StateNotifierProvider.autoDispose<WeldSetupNotifier, WeldSetupState>((ref) {
  return WeldSetupNotifier(
    paramsRepo: ref.watch(weldParametersRepositoryProvider),
    db: ref.watch(databaseProvider),
  );
});

// ── Auth state notifier ────────────────────────────────────────────────────────

class AuthState {
  const AuthState({
    this.user,
    this.isLoading = false,
    this.error,
  });

  final dynamic user;     // AuthUser | null
  final bool isLoading;
  final String? error;

  bool get isAuthenticated => user != null;

  AuthState copyWith({
    dynamic user,
    bool? isLoading,
    String? error,
    bool clearUser = false,
    bool clearError = false,
  }) =>
      AuthState(
        user: clearUser ? null : (user ?? this.user),
        isLoading: isLoading ?? this.isLoading,
        error: clearError ? null : (error ?? this.error),
      );
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this._repo) : super(const AuthState()) {
    _restoreSession();
  }

  final AuthRepository _repo;

  Future<void> _restoreSession() async {
    state = state.copyWith(isLoading: true);
    final user = await _repo.getStoredUser();
    state = AuthState(user: user);
  }

  Future<void> login({required String email, required String password}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    final result = await _repo.login(email: email, password: password);
    result.when(
      success: (user) => state = AuthState(user: user),
      failure: (e) => state = AuthState(error: e.message),
    );
  }

  Future<void> logout() async {
    await _repo.logout();
    state = const AuthState();
  }

  Future<void> refreshUser() async {
    if (!state.isAuthenticated) return;
    final result = await _repo.fetchCurrentUser();
    result.when(
      success: (user) => state = state.copyWith(user: user),
      failure: (_) {},
    );
  }

  /// Sends a password-reset email to [email].
  ///
  /// Stub — delegates to [AuthRepository.requestPasswordReset].
  /// The UI shows a confirmation snackbar regardless of outcome so that
  /// valid email addresses are not enumerated to an attacker.
  Future<void> requestPasswordReset(String email) async {
    await _repo.requestPasswordReset(email);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref.watch(authRepositoryProvider));
});
