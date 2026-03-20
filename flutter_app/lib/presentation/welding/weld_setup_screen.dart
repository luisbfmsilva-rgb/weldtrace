import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/local/database/app_database.dart';
import '../../services/welding/welding_table.dart';
import '../../di/providers.dart';
import 'weld_setup_notifier.dart';
import 'welding_session_screen.dart';

/// Entry point for a new weld session.
///
/// The welder must configure:
///   Project → Machine → Pipe material → Standard →
///   Diameter (cascades from DB) → SDR (cascades from DB) →
///   Ambient temperature (optional) → Notes (optional)
///
/// After "Start Weld" the local SQLite weld record is created and the
/// WeldingSessionScreen is pushed with the new weld ID and phase list.
class WeldSetupScreen extends ConsumerStatefulWidget {
  const WeldSetupScreen({super.key, this.preselectedProjectId});

  final String? preselectedProjectId;

  @override
  ConsumerState<WeldSetupScreen> createState() => _WeldSetupScreenState();
}

class _WeldSetupScreenState extends ConsumerState<WeldSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _ambientController       = TextEditingController();
  final _dragPressureController  = TextEditingController();
  final _notesController         = TextEditingController();
  final _operatorNameController  = TextEditingController();
  final _operatorIdController    = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Pre-select project if navigated from ProjectsScreen
      if (widget.preselectedProjectId != null) {
        ref
            .read(weldSetupProvider.notifier)
            .selectProject(widget.preselectedProjectId!);
      }
      // Auto-fill operator fields when the logged-in user is a welder
      final user = ref.read(authProvider).user;
      if (user != null && user.role == 'welder') {
        _operatorNameController.text = user.displayName;
        _operatorIdController.text   =
            user.welderCertificationNumber ?? user.id.substring(0, 8);
        ref.read(weldSetupProvider.notifier).setOperatorName(user.displayName);
        ref
            .read(weldSetupProvider.notifier)
            .setOperatorId(_operatorIdController.text);
      }
    });
  }

  @override
  void dispose() {
    _ambientController.dispose();
    _dragPressureController.dispose();
    _notesController.dispose();
    _operatorNameController.dispose();
    _operatorIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final setup = ref.watch(weldSetupProvider);
    final db = ref.watch(databaseProvider);
    final theme = Theme.of(context);

    // Navigate when weld is created
    ref.listen<WeldSetupState>(weldSetupProvider, (_, next) {
      if (next.createdWeldId != null && next.createdPhases != null) {
        // Prefer data from the DVS-computed welding table
        final table = next.weldingTable;
        final row   = table?.row;
        final wt    = next.catalogWallThickness ?? row?.wallThicknessMm ?? 0.0;
        final wallStr = wt > 0 ? '${wt.toStringAsFixed(2)} mm' : '';

        // Fusion pressure = joining/cooling phase nominal pressure
        final fusionBar = row?.fusionPressureBar ?? 0.0;
        final heatingS  = (row?.heatingTimeS ?? 0).toDouble();
        final coolingS  = (row?.coolingTimeS ?? 0).toDouble();
        final beadMm    = row?.minBeadHeightMm ?? 0.0;

        context.go(
          '/weld/preparation',
          extra: WeldSessionArgs(
            weldId:                  next.createdWeldId!,
            phases:                  next.createdPhases!,
            projectName:             next.projectName,
            machineId:               next.selectedMachineId ?? '',
            machineName:             next.machineName,
            machineModel:            next.machineModel,
            machineSerialNumber:     next.machineSerialNumber,
            hydraulicCylinderAreaMm2: next.machineHydraulicAreaMm2 ?? 0.0,
            operatorName:            next.operatorName,
            operatorId:              next.operatorId,
            pipeMaterial:            next.pipeMaterial ?? '',
            pipeDiameter:            next.pipeDiameterMm ?? 0.0,
            pipeSdr:                 next.sdrRating ?? '',
            wallThicknessStr:        wallStr,
            standardUsed:            next.standardUsed,
            fusionPressureBar:       fusionBar,
            heatingTimeSec:          heatingS,
            coolingTimeSec:          coolingS,
            beadHeightMm:            beadMm,
            dragPressureBar:         next.dragPressureBar,
            wallThicknessMm:         wt,
            outerDiameterMm:         next.pipeDiameterMm ?? 0.0,
          ),
        );
        // Reset notifier so back-navigation does not re-navigate
        ref.read(weldSetupProvider.notifier).resetCreated();
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('New Weld Setup')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Section: Location ────────────────────────────────────────
            _SectionHeader(title: 'Location & Equipment'),

            // Project selector
            _SectionLabel(label: 'Project'),
            StreamBuilder<List<ProjectRecord>>(
              stream: db.projectsDao.watchAll(),
              builder: (ctx, snap) {
                final projects = snap.data ?? [];
                return _DropdownField<String>(
                  hint: 'Select project',
                  value: setup.selectedProjectId,
                  items: projects
                      .map((p) => DropdownMenuItem(
                            value: p.id,
                            child: Text(p.name,
                                overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      ref.read(weldSetupProvider.notifier).selectProject(v);
                    }
                  },
                  validator: (v) =>
                      v == null ? 'Select a project' : null,
                );
              },
            ),
            const SizedBox(height: 14),

            // Machine selector (approved only)
            _SectionLabel(label: 'Machine'),
            StreamBuilder<List<MachineRecord>>(
              stream: db.machinesDao.watchAll(),
              builder: (ctx, snap) {
                final machines = (snap.data ?? [])
                    .where((m) => m.isApproved && m.isActive)
                    .toList();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DropdownField<String>(
                      hint: machines.isEmpty
                          ? 'No approved machines — sync first'
                          : 'Select machine',
                      value: setup.selectedMachineId,
                      items: machines
                          .map((m) => DropdownMenuItem(
                                value: m.id,
                                child: Text(
                                  '${m.manufacturer} ${m.model} · ${m.serialNumber}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ))
                          .toList(),
                      onChanged: machines.isEmpty
                          ? null
                          : (v) {
                              if (v != null) {
                                ref
                                    .read(weldSetupProvider.notifier)
                                    .selectMachine(v)
                                    .ignore();
                              }
                            },
                      validator: (v) =>
                          v == null ? 'Select an approved machine' : null,
                    ),
                    if (machines.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Sync first to load approved machines.',
                          style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.error),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),

            // ── Section: Pipe specification ──────────────────────────────
            _SectionHeader(title: 'Pipe Specification'),

            // Pipe material
            _SectionLabel(label: 'Pipe Material'),
            _DropdownField<String>(
              hint: 'Select material',
              value: setup.pipeMaterial,
              items: const [
                DropdownMenuItem(value: 'PE80',  child: Text('PE80 — Polyethylene 80')),
                DropdownMenuItem(value: 'PE100', child: Text('PE100 — Polyethylene 100')),
                DropdownMenuItem(value: 'PP',    child: Text('PP — Polypropylene')),
              ],
              onChanged: (v) {
                if (v != null) {
                  ref.read(weldSetupProvider.notifier).selectMaterial(v);
                }
              },
              validator: (v) =>
                  v == null ? 'Select pipe material' : null,
            ),
            const SizedBox(height: 24),

            // ── Section: Welding standard (optional — for reference) ─────
            _SectionHeader(title: 'Welding Standard (Optional)'),

            _SectionLabel(label: 'Welding Standard'),
            setup.standards.isEmpty
                ? _NoDataWarning(
                    message:
                        'No welding standards configured. '
                        'DVS 2207-1 formulas applied by default.',
                  )
                : _DropdownField<String>(
                    hint: 'Select standard (optional)',
                    value: setup.selectedStandardId,
                    items: setup.standards
                        .map((s) => DropdownMenuItem(
                              value: s.id,
                              child: Text(
                                  '${s.name} (${s.weldType.replaceAll('_', ' ')})'),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      // Check if the selected standard is ASTM or ISO
                      final selected = setup.standards
                          .firstWhere((s) => s.id == v,
                              orElse: () => setup.standards.first);
                      final code = selected.code.toLowerCase();
                      if (code.contains('iso') || code.contains('astm')) {
                        showDialog(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('Standard Not Yet Available'),
                            content: Text(
                              '${selected.name} has not been implemented yet.\n\n'
                              'Only DVS 2207-1 parameters are currently supported. '
                              'Please select DVS 2207 or leave the field empty to '
                              'use DVS defaults.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: const Text('OK'),
                              ),
                            ],
                          ),
                        );
                        return; // do NOT update the selection
                      }
                      ref
                          .read(weldSetupProvider.notifier)
                          .selectStandard(v);
                    },
                  ),
            const SizedBox(height: 14),

            // Pipe diameter (from catalog — no prerequisites)
            _SectionLabel(label: 'Pipe Diameter (DN)'),
            _buildDiameterSelector(setup, ref),
            const SizedBox(height: 14),

            // SDR rating (from catalog for selected diameter)
            _SectionLabel(label: 'SDR Rating'),
            _buildSdrSelector(setup, ref),
            const SizedBox(height: 24),

            // ── Drag pressure input (machine with known cylinder area) ────
            if (setup.machineHasCylinderArea) ...[
              _SectionHeader(title: 'Machine Pressure Calculation'),
              _SectionLabel(label: 'Measured Drag Pressure (bar)'),
              TextFormField(
                controller: _dragPressureController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d{0,3}(\.\d{0,2})?')),
                ],
                decoration: InputDecoration(
                  hintText: 'e.g. 0.25',
                  suffixText: 'bar',
                  helperText:
                      'Hydraulic pressure to move the carriage with no load '
                      '(friction only). Read from the machine gauge before welding.',
                  helperMaxLines: 2,
                ),
                onChanged: (v) {
                  final d = double.tryParse(v);
                  ref
                      .read(weldSetupProvider.notifier)
                      .setDragPressure(d ?? 0.0);
                },
                validator: (v) {
                  if (v == null || v.isEmpty) return null;
                  final d = double.tryParse(v);
                  if (d == null || d < 0) return 'Enter a non-negative number';
                  if (d > 20) return 'Drag pressure seems too high (> 20 bar)';
                  return null;
                },
              ),
              const SizedBox(height: 8),
            ],

            // ── Parameter preview ────────────────────────────────────────
            if (setup.weldingTable != null)
              _WeldingTableCard(table: setup.weldingTable!)
            else if (setup.matchedParameters != null)
              _ParameterPreviewCard(params: setup.matchedParameters!),
            if (setup.parametersFromFallback)
              _FallbackWarningBadge(),
            if (setup.lookupError != null)
              _ErrorCard(message: setup.lookupError!),

            const SizedBox(height: 8),

            // ── Section: Optional fields ─────────────────────────────────
            _SectionHeader(title: 'Optional'),

            // Operator name (optional)
            _SectionLabel(label: 'Operator Name'),
            TextFormField(
              controller: _operatorNameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                hintText: 'e.g. João Silva',
              ),
              onChanged: (v) =>
                  ref.read(weldSetupProvider.notifier).setOperatorName(v),
            ),
            const SizedBox(height: 14),

            // Operator ID (optional)
            _SectionLabel(label: 'Operator ID / Badge Number'),
            TextFormField(
              controller: _operatorIdController,
              decoration: const InputDecoration(
                hintText: 'e.g. OP-1042',
              ),
              onChanged: (v) =>
                  ref.read(weldSetupProvider.notifier).setOperatorId(v),
            ),
            const SizedBox(height: 14),

            // Ambient temperature
            _SectionLabel(label: 'Ambient Temperature (°C)'),
            TextFormField(
              controller: _ambientController,
              keyboardType: const TextInputType.numberWithOptions(
                  signed: true, decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^-?\d{0,3}(\.\d{0,1})?')),
              ],
              decoration: const InputDecoration(
                hintText: 'e.g. 18.5',
                suffixText: '°C',
              ),
              onChanged: (v) {
                final d = double.tryParse(v);
                if (d != null) {
                  ref
                      .read(weldSetupProvider.notifier)
                      .setAmbientTemperature(d);
                }
              },
              validator: (v) {
                if (v == null || v.isEmpty) return null;
                final d = double.tryParse(v);
                if (d == null) return 'Enter a valid number';
                if (d < -50 || d > 80) return 'Temperature out of range';
                return null;
              },
            ),
            const SizedBox(height: 14),

            _SectionLabel(label: 'Notes'),
            TextFormField(
              controller: _notesController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Optional weld notes…',
              ),
              onChanged: (v) =>
                  ref.read(weldSetupProvider.notifier).setNotes(v),
            ),
            const SizedBox(height: 24),

            // ── Submit error ─────────────────────────────────────────────
            if (setup.submitError != null)
              _ErrorCard(message: setup.submitError!),

            // ── Start Weld button ────────────────────────────────────────
            const SizedBox(height: 8),
            ElevatedButton.icon(
              icon: setup.isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.play_arrow),
              label: Text(setup.isSubmitting
                  ? 'Creating weld…'
                  : 'Start Weld'),
              style: ElevatedButton.styleFrom(
                backgroundColor: setup.isReadyToStart
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline,
              ),
              onPressed: setup.isReadyToStart
                  ? () async {
                      if (_formKey.currentState!.validate()) {
                        await ref
                            .read(weldSetupProvider.notifier)
                            .startWeld();
                      }
                    }
                  : null,
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ── Diameter selector ─────────────────────────────────────────────────────

  Widget _buildDiameterSelector(WeldSetupState setup, WidgetRef ref) {
    if (setup.availableDiameters.isEmpty) {
      return _DisabledDropdownHint(hint: 'Loading pipe catalog…');
    }
    return _DropdownField<double>(
      hint: 'Select diameter',
      value: setup.pipeDiameterMm,
      items: setup.availableDiameters
          .map((d) => DropdownMenuItem(
                value: d,
                child: Text('DN ${d.toStringAsFixed(0)} mm'),
              ))
          .toList(),
      onChanged: (v) {
        if (v != null) {
          ref.read(weldSetupProvider.notifier).selectDiameter(v);
        }
      },
      validator: (v) => v == null ? 'Select pipe diameter' : null,
    );
  }

  // ── SDR selector ──────────────────────────────────────────────────────────

  Widget _buildSdrSelector(WeldSetupState setup, WidgetRef ref) {
    if (setup.pipeDiameterMm == null) {
      return _DisabledDropdownHint(hint: 'Select diameter first');
    }
    if (setup.availableSdrRatings.isEmpty) {
      return _DisabledDropdownHint(hint: 'No SDR ratings found for this diameter');
    }
    return _DropdownField<String>(
      hint: 'Select SDR',
      value: setup.sdrRating,
      items: setup.availableSdrRatings
          .map((s) => DropdownMenuItem(
                value: s,
                child: Text('SDR $s'),
              ))
          .toList(),
      onChanged: (v) {
        if (v != null) {
          ref.read(weldSetupProvider.notifier).selectSdr(v);
        }
      },
      validator: (v) => v == null ? 'Select SDR rating' : null,
    );
  }
}

// ── Shared UI components ──────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          Divider(
            height: 1,
            color: theme.colorScheme.primary.withOpacity(0.2),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withOpacity(0.6),
              ),
        ),
      );
}

class _DropdownField<T> extends StatelessWidget {
  const _DropdownField({
    required this.hint,
    required this.value,
    required this.items,
    required this.onChanged,
    this.validator,
  });

  final String hint;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final void Function(T?)? onChanged;
  final String? Function(T?)? validator;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      value: value,
      hint: Text(hint),
      items: items,
      onChanged: onChanged,
      validator: validator,
      isExpanded: true,
      decoration: const InputDecoration(),
    );
  }
}

class _DisabledDropdownHint extends StatelessWidget {
  const _DisabledDropdownHint({required this.hint});
  final String hint;

  @override
  Widget build(BuildContext context) => InputDecorator(
        decoration: const InputDecoration(),
        child: Text(
          hint,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withOpacity(0.4),
              ),
        ),
      );
}

class _NoDataWarning extends StatelessWidget {
  const _NoDataWarning({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber, color: Colors.amber, size: 18),
          const SizedBox(width: 8),
          Expanded(
              child: Text(message,
                  style: const TextStyle(fontSize: 13, color: Colors.amber))),
        ],
      ),
    );
  }
}

/// Yellow warning badge shown when welding parameters were computed by the
/// offline fallback engine rather than loaded from certified database records.
class _FallbackWarningBadge extends StatelessWidget {
  const _FallbackWarningBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.shade700),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded,
              color: Colors.amber.shade800, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Parameters generated automatically — verify against official standard.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.amber.shade900,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline,
              color: theme.colorScheme.onErrorContainer, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style:
                    TextStyle(color: theme.colorScheme.onErrorContainer, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

/// Displays the computed [WeldingTable] with machine gauge pressures
/// when the machine's hydraulic cylinder area is known.
class _WeldingTableCard extends StatelessWidget {
  const _WeldingTableCard({required this.table});
  final WeldingTable table;

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF0052CC);
    final row = table.row;
    final pipe = table.pipeSpec;
    final machine = table.machineSpec;
    final hasMachine = row.isMachinePressure;

    String fmtBar(double? v) =>
        v != null ? '${v.toStringAsFixed(2)} bar' : '—';
    String fmtMm(double v) => '${v.toStringAsFixed(2)} mm';
    String fmtMm2(double v) => '${v.toStringAsFixed(0)} mm²';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: blue.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: blue.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: blue.withOpacity(0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
            ),
            child: Row(
              children: [
                const Icon(Icons.calculate_outlined, color: blue, size: 16),
                const SizedBox(width: 8),
                Text(
                  hasMachine
                      ? 'Machine Gauge Pressures — Calculated'
                      : 'Interfacial Pressures (no cylinder area on file)',
                  style: const TextStyle(
                      color: blue, fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Geometry ─────────────────────────────────────────────
                _TableSection(label: 'Pipe geometry'),
                _ParamRow('OD', '${pipe.outerDiameterMm.toStringAsFixed(0)} mm'),
                _ParamRow('SDR', pipe.sdrRatio.toStringAsFixed(1)),
                _ParamRow('Wall thickness  e', fmtMm(row.wallThicknessMm)),
                _ParamRow('Pipe annulus area  A', fmtMm2(row.pipeAnnulusAreaMm2)),
                _ParamRow('Min bead height', fmtMm(row.minBeadHeightMm)),
                const SizedBox(height: 12),

                // ── DVS 2207 ratio ────────────────────────────────────────
                if (hasMachine) ...[
                  _TableSection(label: 'DVS 2207 calculation'),
                  _ParamRow('Cylinder area  A_cyl',
                      fmtMm2(machine.hydraulicCylinderAreaMm2!)),
                  _ParamRow('Pipe area  A_pipe',
                      fmtMm2(row.pipeAnnulusAreaMm2)),
                  _ParamRow('Ratio  RA = A_pipe / A_cyl',
                      (row.pipeAnnulusAreaMm2 / machine.hydraulicCylinderAreaMm2!)
                          .toStringAsFixed(4)),
                  _ParamRow('Drag pressure',
                      fmtBar(machine.dragPressureBar)),
                  const SizedBox(height: 12),
                ],

                // ── Phase pressures ───────────────────────────────────────
                _TableSection(
                    label: hasMachine
                        ? 'Machine gauge pressures'
                        : 'Interfacial pressures'),
                if (row.heatingUpPressureBar != null)
                  _ParamRow('Heating-up', fmtBar(row.heatingUpPressureBar)),
                if (row.heatingPressureBar != null)
                  _ParamRow('Heating', fmtBar(row.heatingPressureBar)),
                if (row.fusionPressureBar != null) ...[
                  _ParamRow('Fusion (nominal)', fmtBar(row.fusionPressureBar)),
                  if (row.fusionPressureMinBar != null)
                    _ParamRow('  — min',
                        fmtBar(row.fusionPressureMinBar),
                        dimLabel: true),
                  if (row.fusionPressureMaxBar != null)
                    _ParamRow('  — max',
                        fmtBar(row.fusionPressureMaxBar),
                        dimLabel: true),
                ],
                if (row.coolingPressureBar != null)
                  _ParamRow('Cooling', fmtBar(row.coolingPressureBar)),
                const SizedBox(height: 12),

                // ── Phase times ───────────────────────────────────────────
                _TableSection(label: 'Phase durations'),
                _ParamRow('Heating-up', '${row.heatingUpTimeS} s'),
                _ParamRow('Heating', '${row.heatingTimeS} s'),
                _ParamRow('Changeover (max)', '${row.changeoverTimeMaxS} s'),
                _ParamRow('Build-up', '${row.buildupTimeS} s'),
                _ParamRow('Fusion', '${row.fusionTimeS} s'),
                _ParamRow('Cooling', '${row.coolingTimeS} s'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TableSection extends StatelessWidget {
  const _TableSection({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.45),
          ),
        ),
      );
}

/// Displays a summary of the resolved welding parameters
/// so the welder can confirm before starting (interfacial fallback).
class _ParameterPreviewCard extends StatelessWidget {
  const _ParameterPreviewCard({required this.params});
  final WeldingParameterRecord params;

  @override
  Widget build(BuildContext context) {
    const weldTraceGreen = Color(0xFF2E7D32);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: weldTraceGreen.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: weldTraceGreen.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle, color: weldTraceGreen, size: 18),
              const SizedBox(width: 8),
              Text(
                'Parameters resolved',
                style: TextStyle(
                    color: weldTraceGreen,
                    fontWeight: FontWeight.w700,
                    fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (params.heatingTimeS != null)
            _ParamRow('Heating time', '${params.heatingTimeS} s'),
          if (params.heatingUpPressureBar != null)
            _ParamRow('Heating pressure',
                '${params.heatingUpPressureBar!.toStringAsFixed(2)} bar'),
          if (params.changeoverTimeMaxS != null)
            _ParamRow('Changeover (max)', '${params.changeoverTimeMaxS} s'),
          if (params.fusionPressureBar != null)
            _ParamRow('Fusion pressure',
                '${params.fusionPressureBar!.toStringAsFixed(2)} bar'),
          if (params.fusionTimeS != null)
            _ParamRow('Fusion time', '${params.fusionTimeS} s'),
          if (params.coolingTimeS != null)
            _ParamRow('Cooling time', '${params.coolingTimeS} s'),
          if (params.wallThicknessMm != null)
            _ParamRow('Wall thickness',
                '${params.wallThicknessMm!.toStringAsFixed(1)} mm'),
          _ParamRow(
            'Ambient range',
            '${params.ambientTempMinCelsius.toStringAsFixed(0)}°C '
                'to ${params.ambientTempMaxCelsius.toStringAsFixed(0)}°C',
          ),
        ],
      ),
    );
  }
}

class _ParamRow extends StatelessWidget {
  const _ParamRow(this.label, this.value, {this.dimLabel = false});
  final String label;
  final String value;
  final bool dimLabel;

  @override
  Widget build(BuildContext context) {
    final dimColor = Theme.of(context).colorScheme.onSurface.withOpacity(0.55);
    final veryDimColor = Theme.of(context).colorScheme.onSurface.withOpacity(0.38);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: dimLabel ? veryDimColor : dimColor,
                  ),
            ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: dimLabel ? FontWeight.w400 : FontWeight.w600,
                  color: dimLabel ? veryDimColor : null,
                ),
          ),
        ],
      ),
    );
  }
}
