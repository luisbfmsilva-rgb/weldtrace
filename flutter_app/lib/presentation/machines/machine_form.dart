import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme/app_colors.dart';
import '../../data/local/database/app_database.dart';
import '../../di/providers.dart';

/// Full-screen form for creating or editing a machine.
class MachineFormScreen extends ConsumerStatefulWidget {
  const MachineFormScreen({super.key, this.existing});

  final MachineRecord? existing;

  @override
  ConsumerState<MachineFormScreen> createState() => _MachineFormScreenState();
}

class _MachineFormScreenState extends ConsumerState<MachineFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _manufacturer;
  late final TextEditingController _model;
  late final TextEditingController _serial;
  late final TextEditingController _area;
  late final TextEditingController _notes;
  late final TextEditingController _calDate;
  late final TextEditingController _calNext;
  String _type = 'butt_fusion';
  bool _isApproved = false;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final m = widget.existing;
    _manufacturer = TextEditingController(text: m?.manufacturer ?? '');
    _model = TextEditingController(text: m?.model ?? '');
    _serial = TextEditingController(text: m?.serialNumber ?? '');
    _area = TextEditingController(text: m?.hydraulicCylinderAreaMm2?.toStringAsFixed(2) ?? '');
    _notes = TextEditingController(text: m?.notes ?? '');
    _calDate = TextEditingController(text: m?.lastCalibrationDate ?? '');
    _calNext = TextEditingController(text: m?.nextCalibrationDate ?? '');
    _type = m?.type ?? 'butt_fusion';
    _isApproved = m?.isApproved ?? false;

    // Auto-fill next calibration date whenever last calibration date changes.
    _calDate.addListener(_autoFillNextCalDate);
  }

  void _autoFillNextCalDate() {
    final text = _calDate.text.trim();
    final date = DateTime.tryParse(text);
    if (date == null) return;
    // Only auto-fill when the next date field is empty or was previously auto-filled.
    final nextYear = DateTime(date.year + 1, date.month, date.day);
    final formatted = '${nextYear.year.toString().padLeft(4, '0')}-'
        '${nextYear.month.toString().padLeft(2, '0')}-'
        '${nextYear.day.toString().padLeft(2, '0')}';
    if (_calNext.text.isEmpty || _calNext.text == _prevAutoCalNext) {
      _calNext.text = formatted;
      _prevAutoCalNext = formatted;
    }
  }

  String _prevAutoCalNext = '';

  @override
  void dispose() {
    _calDate.removeListener(_autoFillNextCalDate);
    for (final c in [_manufacturer, _model, _serial, _area, _notes, _calDate, _calNext]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate(TextEditingController ctrl) async {
    final initial = DateTime.tryParse(ctrl.text) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      ctrl.text = '${picked.year.toString().padLeft(4, '0')}-'
          '${picked.month.toString().padLeft(2, '0')}-'
          '${picked.day.toString().padLeft(2, '0')}';
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final db = ref.read(databaseProvider);
    final auth = ref.read(authProvider);
    final now = DateTime.now().toUtc();
    final id = _isEdit ? widget.existing!.id : const Uuid().v4();
    final area = double.tryParse(_area.text.replaceAll(',', '.'));

    try {
      await db.machinesDao.upsert(MachinesTableCompanion(
        id: Value(id),
        companyId: Value(auth.user?.companyId ?? ''),
        manufacturer: Value(_manufacturer.text.trim()),
        model: Value(_model.text.trim()),
        serialNumber: Value(_serial.text.trim()),
        hydraulicCylinderAreaMm2: Value(area),
        type: Value(_type),
        isApproved: Value(_isApproved),
        isActive: const Value(true),
        notes: Value(_notes.text.trim().isEmpty ? null : _notes.text.trim()),
        lastCalibrationDate: Value(_calDate.text.trim().isEmpty ? null : _calDate.text.trim()),
        nextCalibrationDate: Value(_calNext.text.trim().isEmpty ? null : _calNext.text.trim()),
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
      appBar: AppBar(title: Text(_isEdit ? 'Edit Machine' : 'New Machine')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Identity ────────────────────────────────────────────────
            _card('Identity', [
              _field('Manufacturer / Brand *', _manufacturer, required: true),
              const SizedBox(height: 14),
              _field('Model *', _model, required: true),
              const SizedBox(height: 14),
              _field('Serial Number *', _serial, required: true),
            ]),
            const SizedBox(height: 12),

            // ── Type ────────────────────────────────────────────────────
            _card('Welding Type', [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'butt_fusion', label: Text('Butt Fusion')),
                  ButtonSegment(value: 'electrofusion', label: Text('Electrofusion')),
                  ButtonSegment(value: 'universal', label: Text('Universal')),
                ],
                selected: {_type},
                onSelectionChanged: (s) => setState(() => _type = s.first),
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
            const SizedBox(height: 12),

            // ── Hydraulic ───────────────────────────────────────────────
            _card('Hydraulic Cylinder', [
              const Text(
                'Critical for pressure calculations. Found on the machine data plate or calibration certificate.',
                style: TextStyle(fontSize: 12, color: AppColors.neutralGray),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _area,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d,.]'))],
                decoration: const InputDecoration(
                  labelText: 'Hydraulic Cylinder Area (mm²)',
                  suffixText: 'mm²',
                  helperText: 'e.g. 491.00 for Ø25mm piston',
                ),
              ),
            ]),
            const SizedBox(height: 12),

            // ── Calibration ─────────────────────────────────────────────
            _card('Calibração', [
              const Text(
                'A data da próxima calibração é preenchida automaticamente (1 ano após a última).',
                style: TextStyle(fontSize: 12, color: AppColors.neutralGray),
              ),
              const SizedBox(height: 12),
              _datePicker('Última Calibração', _calDate),
              const SizedBox(height: 14),
              _datePicker('Próxima Calibração', _calNext),
            ]),
            const SizedBox(height: 12),

            // ── Status ──────────────────────────────────────────────────
            _card('Status', [
              SwitchListTile(
                title: const Text('Machine Approved',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Approved machines can be used in welds'),
                value: _isApproved,
                onChanged: (v) => setState(() => _isApproved = v),
                activeColor: AppColors.sertecRed,
                contentPadding: EdgeInsets.zero,
              ),
            ]),
            const SizedBox(height: 12),

            // ── Notes ───────────────────────────────────────────────────
            _card('Notes', [_field('Notes', _notes, maxLines: 3)]),
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
                  : Text(_isEdit ? 'Save Changes' : 'Register Machine',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(String title, List<Widget> children) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.sertecRed)),
          const SizedBox(height: 12),
          ...children,
        ]),
      );

  Widget _datePicker(String label, TextEditingController ctrl) => TextFormField(
        controller: ctrl,
        readOnly: true,
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
        ),
        onTap: () => _pickDate(ctrl),
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
