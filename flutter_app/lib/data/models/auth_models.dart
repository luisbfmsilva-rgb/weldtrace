/// Data-layer models for authentication API responses.
/// These are plain Dart objects — no Drift, no annotation.

class LoginResponse {
  const LoginResponse({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
    required this.user,
  });

  final String accessToken;
  final String refreshToken;
  final int expiresIn;
  final AuthUser user;

  factory LoginResponse.fromJson(Map<String, dynamic> json) => LoginResponse(
        accessToken: json['accessToken'] as String,
        refreshToken: json['refreshToken'] as String,
        expiresIn: json['expiresIn'] as int,
        user: AuthUser.fromJson(json['user'] as Map<String, dynamic>),
      );
}

class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    required this.role,
    required this.companyId,
    required this.firstName,
    required this.lastName,
    this.welderCertificationNumber,
    this.certificationExpiry,
    this.isActive = true,
    this.assignedProjects = const [],
  });

  final String id;
  final String email;
  final String role;           // 'manager' | 'supervisor' | 'welder' | 'auditor'
  final String companyId;
  final String firstName;
  final String lastName;
  final String? welderCertificationNumber;
  final String? certificationExpiry;
  final bool isActive;
  final List<AssignedProject> assignedProjects;

  String get displayName => '$firstName $lastName';

  bool get isWelder => role == 'welder';
  bool get isManager => role == 'manager';
  bool get isSupervisor => role == 'supervisor';
  bool get isAuditor => role == 'auditor';

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        id: json['id'] as String,
        email: json['email'] as String,
        role: json['role'] as String,
        companyId: json['companyId'] as String,
        firstName: json['firstName'] as String,
        lastName: json['lastName'] as String,
        welderCertificationNumber: json['welderCertificationNumber'] as String?,
        certificationExpiry: json['certificationExpiry'] as String?,
        isActive: json['isActive'] as bool? ?? true,
        assignedProjects: (json['assignedProjects'] as List<dynamic>? ?? [])
            .map((e) => AssignedProject.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'role': role,
        'companyId': companyId,
        'firstName': firstName,
        'lastName': lastName,
        'welderCertificationNumber': welderCertificationNumber,
        'certificationExpiry': certificationExpiry,
        'isActive': isActive,
        'assignedProjects': assignedProjects.map((p) => p.toJson()).toList(),
      };
}

class AssignedProject {
  const AssignedProject({
    required this.id,
    required this.name,
    required this.status,
    this.location,
    required this.roleInProject,
  });

  final String id;
  final String name;
  final String status;
  final String? location;
  final String roleInProject;

  factory AssignedProject.fromJson(Map<String, dynamic> json) => AssignedProject(
        id: json['id'] as String,
        name: json['name'] as String,
        status: json['status'] as String,
        location: json['location'] as String?,
        roleInProject: json['roleInProject'] as String,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'status': status,
        'location': location,
        'roleInProject': roleInProject,
      };
}
