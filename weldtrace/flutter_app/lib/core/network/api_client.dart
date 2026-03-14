import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

import '../constants/app_constants.dart';
import '../errors/app_exception.dart';
import '../utils/result.dart';
import '../../data/local/database/app_database.dart';

/// HTTP client wrapper that:
/// - Injects Bearer token from the local auth store
/// - Handles JSON encoding/decoding
/// - Maps HTTP errors to typed [AppException]s
class ApiClient {
  ApiClient({
    required this.tokenProvider,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final Future<String?> Function() tokenProvider;
  final http.Client _http;
  final String _baseUrl = AppConstants.apiBaseUrl;

  // ── Request helpers ───────────────────────────────────────────────────────

  Future<Map<String, String>> _headers() async {
    final token = await tokenProvider();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<Result<T>> get<T>(
    String path,
    T Function(dynamic json) fromJson, {
    Map<String, String?>? queryParams,
  }) async {
    try {
      final uri = _buildUri(path, queryParams);
      final response = await _http.get(uri, headers: await _headers());
      return _handleResponse(response, fromJson);
    } on SocketException catch (e) {
      return Failure(NetworkException('No internet connection', e));
    } catch (e) {
      return Failure(NetworkException('Request failed: $path', e));
    }
  }

  Future<Result<T>> post<T>(
    String path,
    Map<String, dynamic> body,
    T Function(dynamic json) fromJson,
  ) async {
    try {
      final uri = _buildUri(path, null);
      final response = await _http.post(
        uri,
        headers: await _headers(),
        body: jsonEncode(body),
      );
      return _handleResponse(response, fromJson);
    } on SocketException catch (e) {
      return Failure(NetworkException('No internet connection', e));
    } catch (e) {
      return Failure(NetworkException('Request failed: $path', e));
    }
  }

  Future<Result<T>> patch<T>(
    String path,
    Map<String, dynamic> body,
    T Function(dynamic json) fromJson,
  ) async {
    try {
      final uri = _buildUri(path, null);
      final response = await _http.patch(
        uri,
        headers: await _headers(),
        body: jsonEncode(body),
      );
      return _handleResponse(response, fromJson);
    } on SocketException catch (e) {
      return Failure(NetworkException('No internet connection', e));
    } catch (e) {
      return Failure(NetworkException('Request failed: $path', e));
    }
  }

  // ── Internal helpers ──────────────────────────────────────────────────────

  Uri _buildUri(String path, Map<String, String?>? queryParams) {
    final base = Uri.parse('$_baseUrl$path');
    if (queryParams == null) return base;
    final filtered = {
      for (final e in queryParams.entries)
        if (e.value != null) e.key: e.value!,
    };
    return base.replace(queryParameters: {...base.queryParameters, ...filtered});
  }

  Result<T> _handleResponse<T>(
    http.Response response,
    T Function(dynamic json) fromJson,
  ) {
    final body = response.body.isNotEmpty
        ? jsonDecode(response.body) as dynamic
        : null;

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return Success(fromJson(body));
    }

    final errorMsg = (body is Map ? body['error'] as String? : null) ??
        'HTTP ${response.statusCode}';

    if (response.statusCode == 401) {
      return Failure(AuthException(errorMsg));
    }
    return Failure(ApiException(errorMsg, statusCode: response.statusCode));
  }
}
