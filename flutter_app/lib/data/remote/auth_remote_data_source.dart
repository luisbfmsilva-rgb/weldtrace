import '../../core/network/api_client.dart';
import '../../core/utils/result.dart';
import '../models/auth_models.dart';

/// Remote data source for all authentication API calls.
class AuthRemoteDataSource {
  const AuthRemoteDataSource(this._api);

  final ApiClient _api;

  Future<Result<LoginResponse>> login({
    required String email,
    required String password,
  }) =>
      _api.post(
        '/auth/login',
        {'email': email, 'password': password},
        (json) => LoginResponse.fromJson(json as Map<String, dynamic>),
      );

  Future<Result<AuthUser>> me() =>
      _api.get(
        '/auth/me',
        (json) => AuthUser.fromJson(
          (json as Map<String, dynamic>)['user'] as Map<String, dynamic>,
        ),
      );

  Future<Result<Map<String, dynamic>>> refresh({
    required String refreshToken,
  }) =>
      _api.post(
        '/auth/refresh',
        {'refreshToken': refreshToken},
        (json) => json as Map<String, dynamic>,
      );

  Future<Result<void>> logout() =>
      _api.post('/auth/logout', {}, (_) {});
}
