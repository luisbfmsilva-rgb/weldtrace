import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme/app_colors.dart';
import '../../data/local/database/app_database.dart';
import '../../di/providers.dart';

/// Full-screen form for creating or editing a project.
class ProjectFormScreen extends ConsumerStatefulWidget {
  const ProjectFormScreen({super.key, this.existing});

  /// Pass an existing record to enter edit mode.
  final ProjectRecord? existing;

  @override
  ConsumerState<ProjectFormScreen> createState() => _ProjectFormScreenState();
}

class _ProjectFormScreenState extends ConsumerState<ProjectFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _client;
  late final TextEditingController _location;
  late final TextEditingController _description;
  late final TextEditingController _contract;
  String _status = 'active';
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _name = TextEditingController(text: p?.name ?? '');
    _client = TextEditingController(text: p?.clientName ?? '');
    _location = TextEditingController(text: p?.location ?? '');
    _description = TextEditingController(text: p?.description ?? '');
    _contract = TextEditingController(text: p?.contractNumber ?? '');
    _status = p?.status ?? 'active';
  }

  @override
  void dispose() {
    _name.dispose();
    _client.dispose();
    _location.dispose();
    _description.dispose();
    _contract.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final db = ref.read(databaseProvider);
    final auth = ref.read(authProvider);
    final now = DateTime.now().toUtc();
    final id = _isEdit ? widget.existing!.id : const Uuid().v4();

    try {
      await db.projectsDao.upsert(ProjectsTableCompanion(
        id: Value(id),
        companyId: Value(auth.user?.companyId ?? ''),
        name: Value(_name.text.trim()),
        clientName: Value(_client.text.trim().isEmpty ? null : _client.text.trim()),
        location: Value(_location.text.trim().isEmpty ? null : _location.text.trim()),
        description: Value(_description.text.trim().isEmpty ? null : _description.text.trim()),
        contractNumber: Value(_contract.text.trim().isEmpty ? null : _contract.text.trim()),
        status: Value(_status),
        createdAt: Value(_isEdit ? widget.existing!.createdAt : now),
        updatedAt: Value(now),
        syncStatus: const Value('pending'),
      ));
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightGray,
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit Project' : 'New Project'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _card([
              _field('Project Name *', _name, required: true),
              const SizedBox(height: 14),
              _field('Client', _client),
              const SizedBox(height: 14),
              _field('Location', _location),
              const SizedBox(height: 14),
              _field('Contract Number', _contract),
              const SizedBox(height: 14),
              _field('Description', _description, maxLines: 3),
            ]),
            const SizedBox(height: 12),
            _card([
              const Text('Status', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'active', label: Text('Active')),
                  ButtonSegment(value: 'inactive', label: Text('Inactive')),
                  ButtonSegment(value: 'completed', label: Text('Completed')),
                ],
                selected: {_status},
                onSelectionChanged: (s) => setState(() => _status = s.first),
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.resolveWith(
                    (s) => s.contains(WidgetState.selected) ? AppColors.sertecRed : null,
                  ),
                  foregroundColor: WidgetStateProperty.resolveWith(
                    (s) => s.contains(WidgetState.selected) ? Colors.white : null,
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.sertecRed,
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(_isEdit ? 'Save Changes' : 'Create Project',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(List<Widget> children) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  Widget _field(
    String label,
    TextEditingController ctrl, {
    bool required = false,
    int maxLines = 1,
  }) =>
      TextFormField(
        controller: ctrl,
        maxLines: maxLines,
        decoration: InputDecoration(labelText: label),
        validator: required
            ? (v) => (v == null || v.trim().isEmpty) ? 'Required field' : null
            : null,
      );
}
