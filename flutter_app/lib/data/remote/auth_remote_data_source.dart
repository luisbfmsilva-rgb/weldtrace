import 'package:supabase_flutter/supabase_flutter.dart'
    hide AuthException; // use app's own AuthException

import '../../core/errors/app_exception.dart';
import '../../core/utils/result.dart';
import '../models/auth_models.dart';

/// Remote data source for authentication.
///
/// Uses the Supabase Flutter client directly so authentication works
/// from the device even when the Express API cannot reach Supabase
/// (e.g. in restricted network environments such as a Replit sandbox).
class AuthRemoteDataSource {
  const AuthRemoteDataSource();

  SupabaseClient get _supabase => Supabase.instance.client;

  // ── Login ─────────────────────────────────────────────────────────────────

  Future<Result<LoginResponse>> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      final session = response.session;
      final supabaseUser = response.user;

      if (session == null || supabaseUser == null) {
        return const Failure(AuthException('Login failed: no session returned'));
      }

      final profileResult = await _fetchProfile(supabaseUser.id);
      if (profileResult is Failure<AuthUser>) {
        return Failure((profileResult as Failure<AuthUser>).exception);
      }
      final user = (profileResult as Success<AuthUser>).value;

      return Success(LoginResponse(
        accessToken: session.accessToken,
        refreshToken: session.refreshToken ?? '',
        expiresIn: session.expiresIn ?? 3600,
        user: user,
      ));
    } on GoTrueException catch (e) {
      final msg = e.message.isNotEmpty ? e.message : 'Invalid credentials';
      return Failure(AuthException(msg));
    } catch (e) {
      return Failure(NetworkException('Login failed: ${e.toString()}', e));
    }
  }

  // ── Current user ──────────────────────────────────────────────────────────

  Future<Result<AuthUser>> me() async {
    try {
      final supabaseUser = _supabase.auth.currentUser;
      if (supabaseUser == null) {
        return const Failure(AuthException('Not authenticated'));
      }
      return await _fetchProfile(supabaseUser.id);
    } catch (e) {
      return Failure(NetworkException('Failed to load profile', e));
    }
  }

  // ── Refresh ───────────────────────────────────────────────────────────────

  Future<Result<Map<String, dynamic>>> refresh({
    required String refreshToken,
  }) async {
    try {
      final response = await _supabase.auth.refreshSession();
      final session = response.session;
      if (session == null) {
        return const Failure(AuthException('Session refresh failed'));
      }
      return Success({
        'accessToken': session.accessToken,
        'refreshToken': session.refreshToken ?? '',
        'expiresIn': session.expiresIn ?? 3600,
      });
    } catch (e) {
      return Failure(NetworkException('Token refresh failed', e));
    }
  }

  // ── Logout ────────────────────────────────────────────────────────────────

  Future<Result<void>> logout() async {
    try {
      await _supabase.auth.signOut();
      return const Success(null);
    } catch (_) {
      return const Success(null); // always succeed locally
    }
  }

  // ── Private ───────────────────────────────────────────────────────────────

  Future<Result<AuthUser>> _fetchProfile(String userId) async {
    try {
      final data = await _supabase
          .from('users')
          .select(
            'id, email, role, company_id, first_name, last_name, '
            'is_active, welder_certification_number, certification_expiry',
          )
          .eq('id', userId)
          .single();

      if (!(data['is_active'] as bool? ?? true)) {
        return const Failure(
          AuthException('Account is inactive. Contact your administrator.'),
        );
      }

      // Fetch projects assigned to this user
      final projectsData = await _supabase
          .from('project_users')
          .select('role_in_project, project:projects(id, name, status, location)')
          .eq('user_id', userId);

      final assignedProjects = (projectsData as List<dynamic>).map((row) {
        final p = row['project'] as Map<String, dynamic>? ?? {};
        return AssignedProject(
          id: (p['id'] as String?) ?? '',
          name: (p['name'] as String?) ?? '',
          status: (p['status'] as String?) ?? '',
          location: p['location'] as String?,
          roleInProject: (row['role_in_project'] as String?) ?? '',
        );
      }).toList();

      return Success(AuthUser(
        id: data['id'] as String,
        email: data['email'] as String,
        role: data['role'] as String,
        companyId: (data['company_id'] as String?) ?? '',
        firstName: (data['first_name'] as String?) ?? '',
        lastName: (data['last_name'] as String?) ?? '',
        welderCertificationNumber:
            data['welder_certification_number'] as String?,
        certificationExpiry: data['certification_expiry'] as String?,
        isActive: data['is_active'] as bool? ?? true,
        assignedProjects: assignedProjects,
      ));
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST116') {
        return const Failure(
          AuthException(
            'User profile not found. Contact your administrator.',
          ),
        );
      }
      return Failure(NetworkException('Profile fetch failed: ${e.message}', e));
    } catch (e) {
      return Failure(NetworkException('Profile fetch failed', e));
    }
  }
}
