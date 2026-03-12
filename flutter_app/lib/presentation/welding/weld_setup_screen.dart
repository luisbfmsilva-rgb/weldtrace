import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/local/tables/projects_table.dart';
import '../../data/local/tables/machines_table.dart';
import '../../data/local/tables/welding_parameters_table.dart';
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
  final _ambientController = TextEditingController();
  final _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Pre-select project if navigated from ProjectsScreen
    if (widget.preselectedProjectId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref
            .read(weldSetupProvider.notifier)
            .selectProject(widget.preselectedProjectId!);
      });
    }
  }

  @override
  void dispose() {
    _ambientController.dispose();
    _notesController.dispose();
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
        context.go(
          '/weld/session',
          extra: WeldSessionArgs(
            weldId: next.createdWeldId!,
            phases: next.createdPhases!,
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
                                    .selectMachine(v);
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
                DropdownMenuItem(value: 'PE', child: Text('PE — Polyethylene')),
                DropdownMenuItem(
                    value: 'PP', child: Text('PP — Polypropylene')),
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

            // ── Section: Welding standard ────────────────────────────────
            _SectionHeader(title: 'Welding Standard'),

            _SectionLabel(label: 'Standard'),
            setup.standards.isEmpty
                ? _NoDataWarning(
                    message:
                        'No standards loaded. Sync to pull data from the cloud.',
                  )
                : _DropdownField<String>(
                    hint: 'Select standard',
                    value: setup.selectedStandardId,
                    items: setup.standards
                        .map((s) => DropdownMenuItem(
                              value: s.id,
                              child: Text('${s.name} (${s.weldType.replaceAll('_', ' ')})'),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) {
                        ref
                            .read(weldSetupProvider.notifier)
                            .selectStandard(v);
                      }
                    },
                    validator: (v) =>
                        v == null ? 'Select a welding standard' : null,
                  ),
            const SizedBox(height: 14),

            // Pipe diameter (cascades after standard + material selected)
            _SectionLabel(label: 'Pipe Diameter (mm)'),
            _buildDiameterSelector(setup, ref),
            const SizedBox(height: 14),

            // SDR rating (cascades after diameter selected)
            _SectionLabel(label: 'SDR Rating'),
            _buildSdrSelector(setup, ref),
            const SizedBox(height: 24),

            // ── Parameter preview ────────────────────────────────────────
            if (setup.matchedParameters != null)
              _ParameterPreviewCard(params: setup.matchedParameters!),
            if (setup.lookupError != null)
              _ErrorCard(message: setup.lookupError!),

            const SizedBox(height: 8),

            // ── Section: Optional fields ─────────────────────────────────
            _SectionHeader(title: 'Optional'),

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
    final canShow = setup.selectedStandardId != null && setup.pipeMaterial != null;
    if (!canShow) {
      return _DisabledDropdownHint(hint: 'Select standard and material first');
    }
    if (setup.availableDiameters.isEmpty) {
      return _DisabledDropdownHint(hint: 'No diameters found — sync data first');
    }
    return _DropdownField<double>(
      hint: 'Select diameter',
      value: setup.pipeDiameterMm,
      items: setup.availableDiameters
          .map((d) => DropdownMenuItem(
                value: d,
                child: Text('${d.toStringAsFixed(0)} mm'),
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
    final theme = Theme.of(context);
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

/// Displays a summary of the resolved welding parameters
/// so the welder can confirm before starting.
class _ParameterPreviewCard extends StatelessWidget {
  const _ParameterPreviewCard({required this.params});
  final WeldingParameterRecord params;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
  const _ParamRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.6))),
            ),
            Text(value,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
      );
}
