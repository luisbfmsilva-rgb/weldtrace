import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/providers.dart';

// ── Simple user model ────────────────────────────────────────────────────────

class _User {
  _User({
    required this.id,
    required this.email,
    required this.role,
    required this.firstName,
    required this.lastName,
    required this.isActive,
    this.welderCertificationNumber,
    this.certificationExpiry,
  });

  final String  id;
  final String  email;
  String        role;
  String        firstName;
  String        lastName;
  bool          isActive;
  String?       welderCertificationNumber;
  String?       certificationExpiry;

  String get displayName => '$firstName $lastName'.trim();

  factory _User.fromJson(Map<String, dynamic> j) => _User(
        id:                        j['id'] as String,
        email:                     j['email'] as String,
        role:                      j['role'] as String,
        firstName:                 (j['firstName'] as String?) ?? '',
        lastName:                  (j['lastName']  as String?) ?? '',
        isActive:                  (j['isActive']  as bool?)   ?? true,
        welderCertificationNumber: j['welderCertificationNumber'] as String?,
        certificationExpiry:       j['certificationExpiry']       as String?,
      );
}

// ── Screen ───────────────────────────────────────────────────────────────────

class UsersScreen extends ConsumerStatefulWidget {
  const UsersScreen({super.key});

  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<UsersScreen> {
  List<_User> _users = [];
  bool        _loading = true;
  String?     _error;

  static const _roles = ['manager', 'supervisor', 'welder', 'auditor'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final api = ref.read(apiClientProvider);
    final result = await api.get<List<_User>>(
      '/users',
      (json) => (json['users'] as List)
          .map((e) => _User.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
    if (!mounted) return;
    result.when(
      success: (users) => setState(() { _users = users; _loading = false; }),
      failure: (e)     => setState(() { _error = e.message; _loading = false; }),
    );
  }

  // ── Add user ────────────────────────────────────────────────────────────

  Future<void> _showAddDialog() async {
    final formKey  = GlobalKey<FormState>();
    final firstName = TextEditingController();
    final lastName  = TextEditingController();
    final email     = TextEditingController();
    final password  = TextEditingController();
    final certNum   = TextEditingController();
    var   role      = 'welder';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Add User'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _field(firstName, 'First Name'),
                  const SizedBox(height: 8),
                  _field(lastName, 'Last Name'),
                  const SizedBox(height: 8),
                  _field(email, 'Email', keyboard: TextInputType.emailAddress),
                  const SizedBox(height: 8),
                  _field(password, 'Password', obscure: true, minLen: 8),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: role,
                    decoration: const InputDecoration(
                      labelText: 'Role',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: _roles
                        .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                        .toList(),
                    onChanged: (v) => setLocal(() => role = v ?? role),
                  ),
                  const SizedBox(height: 8),
                  _field(certNum, 'Cert. Number (optional)', required: false),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) {
                  Navigator.of(ctx).pop(true);
                }
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    final authState = ref.read(authProvider);
    final companyId = authState.user?.companyId as String?;
    if (companyId == null) return;

    final api = ref.read(apiClientProvider);
    final result = await api.post<Map<String, dynamic>>(
      '/auth/register',
      {
        'firstName':  firstName.text.trim(),
        'lastName':   lastName.text.trim(),
        'email':      email.text.trim(),
        'password':   password.text,
        'role':       role,
        'companyId':  companyId,
        if (certNum.text.trim().isNotEmpty)
          'welderCertificationNumber': certNum.text.trim(),
      },
      (json) => json as Map<String, dynamic>,
    );

    if (!mounted) return;
    result.when(
      success: (_) { _load(); _snack('User created'); },
      failure: (e) => _snack('Error: ${e.message}', error: true),
    );
  }

  // ── Edit user ────────────────────────────────────────────────────────────

  Future<void> _showEditDialog(_User user) async {
    final formKey  = GlobalKey<FormState>();
    final firstName = TextEditingController(text: user.firstName);
    final lastName  = TextEditingController(text: user.lastName);
    final certNum   = TextEditingController(text: user.welderCertificationNumber ?? '');
    var   role      = user.role;
    var   isActive  = user.isActive;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('Edit ${user.displayName}'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _field(firstName, 'First Name'),
                  const SizedBox(height: 8),
                  _field(lastName, 'Last Name'),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: role,
                    decoration: const InputDecoration(
                      labelText: 'Role',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: _roles
                        .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                        .toList(),
                    onChanged: (v) => setLocal(() => role = v ?? role),
                  ),
                  const SizedBox(height: 8),
                  _field(certNum, 'Cert. Number (optional)', required: false),
                  const SizedBox(height: 4),
                  SwitchListTile(
                    title: const Text('Active'),
                    value: isActive,
                    onChanged: (v) => setLocal(() => isActive = v),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) {
                  Navigator.of(ctx).pop(true);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    final api = ref.read(apiClientProvider);
    final result = await api.put<Map<String, dynamic>>(
      '/users/${user.id}',
      {
        'firstName': firstName.text.trim(),
        'lastName':  lastName.text.trim(),
        'role':      role,
        'isActive':  isActive,
        'welderCertificationNumber':
            certNum.text.trim().isEmpty ? null : certNum.text.trim(),
      },
      (json) => json as Map<String, dynamic>,
    );

    if (!mounted) return;
    result.when(
      success: (_) { _load(); _snack('User updated'); },
      failure: (e) => _snack('Error: ${e.message}', error: true),
    );
  }

  // ── Delete user ──────────────────────────────────────────────────────────

  Future<void> _confirmDelete(_User user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete User'),
        content: Text(
          'Are you sure you want to permanently delete ${user.displayName} '
          '(${user.email})? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final api = ref.read(apiClientProvider);
    final result = await api.delete<bool>('/users/${user.id}', (_) => true);

    if (!mounted) return;
    result.when(
      success: (_) { _load(); _snack('User deleted'); },
      failure: (e) => _snack('Error: ${e.message}', error: true),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red : null,
    ));
  }

  static Widget _field(
    TextEditingController ctrl,
    String label, {
    TextInputType keyboard = TextInputType.text,
    bool obscure  = false,
    bool required = true,
    int  minLen   = 1,
  }) =>
      TextFormField(
        controller: ctrl,
        keyboardType: keyboard,
        obscureText: obscure,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        validator: required
            ? (v) {
                if (v == null || v.trim().length < minLen) {
                  return minLen > 1
                      ? 'Min $minLen characters'
                      : 'Required';
                }
                return null;
              }
            : null,
      );

  Color _roleColor(String role) => switch (role) {
        'manager'    => Colors.purple,
        'supervisor' => Colors.blue,
        'welder'     => Colors.green,
        'auditor'    => Colors.orange,
        _            => Colors.grey,
      };

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Users'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDialog,
        icon: const Icon(Icons.person_add),
        label: const Text('Add User'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline,
                            size: 48, color: Colors.red),
                        const SizedBox(height: 12),
                        Text(_error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.red)),
                        const SizedBox(height: 16),
                        FilledButton(
                            onPressed: _load,
                            child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : _users.isEmpty
                  ? const Center(
                      child: Text('No users found. Tap + to add one.'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: _users.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 4),
                      itemBuilder: (ctx, i) {
                        final u = _users[i];
                        return Card(
                          margin: EdgeInsets.zero,
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor:
                                  _roleColor(u.role).withValues(alpha: 0.15),
                              child: Text(
                                '${u.firstName.isNotEmpty ? u.firstName[0] : '?'}'
                                '${u.lastName.isNotEmpty  ? u.lastName[0]  : '?'}',
                                style: TextStyle(
                                    color: _roleColor(u.role),
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                            title: Text(u.displayName),
                            subtitle: Text(u.email,
                                style: const TextStyle(fontSize: 12)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Chip(
                                  label: Text(u.role,
                                      style: const TextStyle(fontSize: 11)),
                                  backgroundColor:
                                      _roleColor(u.role).withValues(alpha: 0.12),
                                  side: BorderSide.none,
                                  padding: EdgeInsets.zero,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                if (!u.isActive) ...[
                                  const SizedBox(width: 4),
                                  const Icon(Icons.block,
                                      size: 16, color: Colors.grey),
                                ],
                                IconButton(
                                  icon: const Icon(Icons.delete_outline,
                                      color: Colors.red, size: 20),
                                  onPressed: () => _confirmDelete(u),
                                ),
                              ],
                            ),
                            onTap: () => _showEditDialog(u),
                          ),
                        );
                      },
                    ),
    );
  }
}
