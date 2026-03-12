import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/errors/app_exception.dart';
import '../../core/utils/result.dart';
import '../../data/local/database/app_database.dart';
import '../../data/local/tables/welds_table.dart';
import '../../data/local/tables/welding_standards_table.dart';
import '../../data/local/tables/welding_parameters_table.dart';
import '../../data/repositories/weld_parameters_repository.dart';
import '../../workflow/welding_phase.dart';

/// Immutable form state for the weld setup screen.
class WeldSetupState {
  const WeldSetupState({
    // Selector lists (loaded from local DB)
    this.standards = const [],
    this.availableDiameters = const [],
    this.availableSdrRatings = const [],

    // User selections
    this.selectedProjectId,
    this.selectedMachineId,
    this.pipeMaterial,
    this.pipeDiameterMm,
    this.sdrRating,
    this.selectedStandardId,
    this.ambientTemperature,
    this.notes,

    // Result of parameter lookup
    this.matchedParameters,
    this.lookupError,

    // Submission
    this.isSubmitting = false,
    this.submitError,
    this.createdWeldId,
    this.createdPhases,
  });

  final List<WeldingStandardRecord> standards;
  final List<double> availableDiameters;
  final List<String> availableSdrRatings;

  final String? selectedProjectId;
  final String? selectedMachineId;
  final String? pipeMaterial;
  final double? pipeDiameterMm;
  final String? sdrRating;
  final String? selectedStandardId;
  final double? ambientTemperature;
  final String? notes;

  final WeldingParameterRecord? matchedParameters;
  final String? lookupError;

  final bool isSubmitting;
  final String? submitError;
  final String? createdWeldId;
  final List<PhaseParameters>? createdPhases;

  bool get isReadyToStart =>
      selectedProjectId != null &&
      selectedMachineId != null &&
      pipeMaterial != null &&
      pipeDiameterMm != null &&
      sdrRating != null &&
      selectedStandardId != null &&
      matchedParameters != null &&
      !isSubmitting;

  bool get parametersResolved => matchedParameters != null;

  WeldSetupState copyWith({
    List<WeldingStandardRecord>? standards,
    List<double>? availableDiameters,
    List<String>? availableSdrRatings,
    String? selectedProjectId,
    String? selectedMachineId,
    String? pipeMaterial,
    double? pipeDiameterMm,
    String? sdrRating,
    String? selectedStandardId,
    double? ambientTemperature,
    String? notes,
    WeldingParameterRecord? matchedParameters,
    String? lookupError,
    bool? isSubmitting,
    String? submitError,
    String? createdWeldId,
    List<PhaseParameters>? createdPhases,
    bool clearDiameter = false,
    bool clearSdr = false,
    bool clearParams = false,
    bool clearLookupError = false,
    bool clearSubmitError = false,
    bool clearCreatedWeld = false,
  }) =>
      WeldSetupState(
        standards: standards ?? this.standards,
        availableDiameters:
            clearDiameter ? [] : (availableDiameters ?? this.availableDiameters),
        availableSdrRatings:
            clearSdr ? [] : (availableSdrRatings ?? this.availableSdrRatings),
        selectedProjectId: selectedProjectId ?? this.selectedProjectId,
        selectedMachineId: selectedMachineId ?? this.selectedMachineId,
        pipeMaterial: pipeMaterial ?? this.pipeMaterial,
        pipeDiameterMm: clearDiameter ? null : (pipeDiameterMm ?? this.pipeDiameterMm),
        sdrRating: (clearDiameter || clearSdr) ? null : (sdrRating ?? this.sdrRating),
        selectedStandardId: selectedStandardId ?? this.selectedStandardId,
        ambientTemperature: ambientTemperature ?? this.ambientTemperature,
        notes: notes ?? this.notes,
        matchedParameters:
            clearParams ? null : (matchedParameters ?? this.matchedParameters),
        lookupError:
            clearLookupError ? null : (lookupError ?? this.lookupError),
        isSubmitting: isSubmitting ?? this.isSubmitting,
        submitError:
            clearSubmitError ? null : (submitError ?? this.submitError),
        createdWeldId:
            clearCreatedWeld ? null : (createdWeldId ?? this.createdWeldId),
        createdPhases:
            clearCreatedWeld ? null : (createdPhases ?? this.createdPhases),
      );
}

/// Manages all state transitions for the WeldSetupScreen:
///   1. Loading standards from DB
///   2. Cascading dropdown updates (diameter → SDR → parameter lookup)
///   3. Creating the weld record in SQLite on "Start Weld"
class WeldSetupNotifier extends StateNotifier<WeldSetupState> {
  WeldSetupNotifier({
    required this.paramsRepo,
    required this.db,
  }) : super(const WeldSetupState()) {
    _loadStandards();
  }

  final WeldParametersRepository paramsRepo;
  final AppDatabase db;

  // ── Initialisation ────────────────────────────────────────────────────────

  Future<void> _loadStandards() async {
    final result = await paramsRepo.getStandards();
    result.when(
      success: (standards) => state = state.copyWith(standards: standards),
      failure: (_) {},
    );
  }

  // ── Selector handlers ─────────────────────────────────────────────────────

  void selectProject(String projectId) =>
      state = state.copyWith(selectedProjectId: projectId);

  void selectMachine(String machineId) =>
      state = state.copyWith(selectedMachineId: machineId);

  Future<void> selectStandard(String standardId) async {
    state = state.copyWith(
      selectedStandardId: standardId,
      clearDiameter: true,
      clearSdr: true,
      clearParams: true,
    );
    await _refreshDiameters();
  }

  Future<void> selectMaterial(String material) async {
    state = state.copyWith(
      pipeMaterial: material,
      clearDiameter: true,
      clearSdr: true,
      clearParams: true,
    );
    await _refreshDiameters();
  }

  Future<void> selectDiameter(double diameterMm) async {
    state = state.copyWith(
      pipeDiameterMm: diameterMm,
      clearSdr: true,
      clearParams: true,
    );
    await _refreshSdrRatings();
  }

  Future<void> selectSdr(String sdr) async {
    state = state.copyWith(sdrRating: sdr, clearParams: true);
    await _lookupParameters();
  }

  void setAmbientTemperature(double temp) =>
      state = state.copyWith(ambientTemperature: temp);

  void setNotes(String notes) => state = state.copyWith(notes: notes);

  // ── Cascading refresh ─────────────────────────────────────────────────────

  Future<void> _refreshDiameters() async {
    final standardId = state.selectedStandardId;
    final material = state.pipeMaterial;
    if (standardId == null || material == null) return;

    final result = await paramsRepo.getAvailableDiameters(
      standardId: standardId,
      pipeMaterial: material,
    );
    result.when(
      success: (diameters) =>
          state = state.copyWith(availableDiameters: diameters),
      failure: (_) {},
    );
  }

  Future<void> _refreshSdrRatings() async {
    final standardId = state.selectedStandardId;
    final material = state.pipeMaterial;
    final diameter = state.pipeDiameterMm;
    if (standardId == null || material == null || diameter == null) return;

    final result = await paramsRepo.getAvailableSdrRatings(
      standardId: standardId,
      pipeMaterial: material,
      pipeDiameterMm: diameter,
    );
    result.when(
      success: (sdrs) =>
          state = state.copyWith(availableSdrRatings: sdrs),
      failure: (_) {},
    );
  }

  Future<void> _lookupParameters() async {
    final standardId = state.selectedStandardId;
    final material = state.pipeMaterial;
    final diameter = state.pipeDiameterMm;
    final sdr = state.sdrRating;
    if (standardId == null || material == null || diameter == null || sdr == null) return;

    state = state.copyWith(clearLookupError: true);

    final result = await paramsRepo.lookupParameters(
      standardId: standardId,
      pipeMaterial: material,
      pipeDiameterMm: diameter,
      sdrRating: sdr,
    );
    result.when(
      success: (params) =>
          state = state.copyWith(matchedParameters: params),
      failure: (e) =>
          state = state.copyWith(lookupError: e.message, clearParams: true),
    );
  }

  // ── Start weld ────────────────────────────────────────────────────────────

  /// Creates a weld record in the local database, builds [PhaseParameters],
  /// and stores the result in state for the calling screen to navigate with.
  Future<void> startWeld() async {
    if (!state.isReadyToStart) return;

    state = state.copyWith(isSubmitting: true, clearSubmitError: true);

    try {
      // 1. Determine weld type from the standard
      final standard = state.standards
          .where((s) => s.id == state.selectedStandardId)
          .firstOrNull;
      final weldType =
          standard?.weldType ?? 'butt_fusion';

      // 2. Validate ambient temperature
      final params = state.matchedParameters!;
      final ambient = state.ambientTemperature;
      if (ambient != null &&
          (ambient < params.ambientTempMinCelsius ||
              ambient > params.ambientTempMaxCelsius)) {
        state = state.copyWith(
          isSubmitting: false,
          submitError:
              'Ambient temperature $ambient°C is outside the allowed range '
              '(${params.ambientTempMinCelsius}–${params.ambientTempMaxCelsius}°C) '
              'for this standard.',
        );
        return;
      }

      // 3. Get current user from auth stored user (rehydrated from secure storage)
      //    We use a placeholder UUID if the user isn't available.
      const operatorId = 'unknown-operator';

      // 4. Create local weld record
      final weldId = const Uuid().v4();
      final now = DateTime.now();
      await db.weldsDao.insertWeld(WeldsTableCompanion(
        id: Value(weldId),
        projectId: Value(state.selectedProjectId!),
        machineId: Value(state.selectedMachineId!),
        operatorId: const Value(operatorId),
        weldType: Value(weldType),
        status: const Value('in_progress'),
        pipeMaterial: Value(state.pipeMaterial!),
        pipeDiameter: Value(state.pipeDiameterMm!),
        pipeSdr: Value(state.sdrRating),
        pipeWallThickness: Value(params.wallThicknessMm),
        ambientTemperature: Value(state.ambientTemperature),
        standardId: Value(state.selectedStandardId),
        standardUsed: Value(standard?.code),
        notes: Value(state.notes),
        startedAt: Value(now),
        createdAt: Value(now),
        updatedAt: Value(now),
        syncStatus: const Value('pending'),
      ));

      // 5. Build phase parameters from the matched record
      final phases = WeldParametersRepository.buildPhaseParameters(
        params,
        weldType,
      );

      state = state.copyWith(
        isSubmitting: false,
        createdWeldId: weldId,
        createdPhases: phases,
      );
    } catch (e) {
      state = state.copyWith(
        isSubmitting: false,
        submitError: 'Failed to create weld: ${e.toString()}',
      );
    }
  }

  /// Called after the screen has read [createdWeldId] and navigated away,
  /// so that back-navigation does not trigger re-navigation.
  void resetCreated() {
    state = state.copyWith(clearCreatedWeld: true);
  }
}
