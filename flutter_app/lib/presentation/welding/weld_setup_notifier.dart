import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/local/database/app_database.dart';
import '../../data/repositories/weld_parameters_repository.dart';
import '../../services/standards/pipes_catalog_seeder.dart';
import '../../services/standards/welding_data_seeder.dart';
import '../../services/welding/welding_table.dart';
import '../../services/welding/welding_table_generator.dart';
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

    // Operator identification (entered in Optional section)
    this.operatorName = '',
    this.operatorId   = '',

    // Machine metadata (loaded when machine is selected)
    this.machineHydraulicAreaMm2,
    this.machineModel          = '',
    this.machineSerialNumber   = '',
    this.machineName           = '',
    this.machineBrand          = '',
    this.machineLastCalibration = '',
    this.machineNextCalibration = '',
    this.dragPressureBar       = 0.0,

    // Project name + location (loaded when project is selected)
    this.projectName     = '',
    this.projectLocation = '',

    // Pipe catalog data (loaded when de + sdr selected)
    this.catalogWallThickness,
    this.catalogPipeArea,

    // Standard display name (resolved from selectedStandardId)
    this.standardUsed = '',

    // Computed welding table (DVS formulas, machine gauge pressures)
    this.weldingTable,

    // Kept for backward-compat (PDF report reads fusionPressureBar etc.)
    this.matchedParameters,
    this.lookupError,
    this.parametersFromFallback = false,

    // Submission
    this.isSubmitting = false,
    this.submitError,
    this.createdWeldId,
    this.createdPhases,
    this.createdWeldNumber = 0,
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

  final String operatorName;
  final String operatorId;

  final double? machineHydraulicAreaMm2;
  final String machineModel;
  final String machineSerialNumber;
  final String machineName;
  final String machineBrand;
  final String machineLastCalibration;
  final String machineNextCalibration;
  final String projectName;
  final String projectLocation;
  final String standardUsed;
  final double dragPressureBar;

  /// Wall thickness [mm] from the pipe catalog for the selected (de, SDR).
  final double? catalogWallThickness;

  /// Annular pipe area [mm²] from the pipe catalog for the selected (de, SDR).
  final double? catalogPipeArea;

  /// Fully computed welding table with DVS 2207 machine gauge pressures.
  final WeldingTable? weldingTable;

  // Legacy fields — populated from fallback path when catalog lookup fails.
  final WeldingParameterRecord? matchedParameters;
  final String? lookupError;
  final bool parametersFromFallback;

  final bool isSubmitting;
  final String? submitError;
  final String? createdWeldId;
  final List<PhaseParameters>? createdPhases;
  final int createdWeldNumber;

  bool get machineHasCylinderArea =>
      machineHydraulicAreaMm2 != null && machineHydraulicAreaMm2! > 0;

  /// Ready to start when project + machine + material + pipe + table resolved.
  bool get isReadyToStart =>
      selectedProjectId != null &&
      selectedMachineId != null &&
      pipeMaterial != null &&
      pipeDiameterMm != null &&
      sdrRating != null &&
      weldingTable != null &&
      !isSubmitting;

  bool get parametersResolved =>
      weldingTable != null || matchedParameters != null;

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
    String? operatorName,
    String? operatorId,
    double? machineHydraulicAreaMm2,
    String? machineModel,
    String? machineSerialNumber,
    String? machineName,
    String? machineBrand,
    String? machineLastCalibration,
    String? machineNextCalibration,
    String? projectName,
    String? projectLocation,
    String? standardUsed,
    double? dragPressureBar,
    double? catalogWallThickness,
    double? catalogPipeArea,
    WeldingTable? weldingTable,
    WeldingParameterRecord? matchedParameters,
    bool? parametersFromFallback,
    String? lookupError,
    bool? isSubmitting,
    String? submitError,
    String? createdWeldId,
    List<PhaseParameters>? createdPhases,
    int? createdWeldNumber,
    bool clearDiameter = false,
    bool clearSdr = false,
    bool clearPipe = false,
    bool clearTable = false,
    bool clearLookupError = false,
    bool clearSubmitError = false,
    bool clearCreatedWeld = false,
    bool clearMachineHydraulics = false,
    // Legacy aliases kept to avoid breaking call-sites
    bool clearParams = false,
  }) =>
      WeldSetupState(
        standards: standards ?? this.standards,
        availableDiameters:
            clearDiameter ? [] : (availableDiameters ?? this.availableDiameters),
        availableSdrRatings:
            (clearDiameter || clearSdr)
                ? []
                : (availableSdrRatings ?? this.availableSdrRatings),
        selectedProjectId: selectedProjectId ?? this.selectedProjectId,
        selectedMachineId: selectedMachineId ?? this.selectedMachineId,
        pipeMaterial: pipeMaterial ?? this.pipeMaterial,
        pipeDiameterMm:
            clearDiameter ? null : (pipeDiameterMm ?? this.pipeDiameterMm),
        sdrRating: (clearDiameter || clearSdr)
            ? null
            : (sdrRating ?? this.sdrRating),
        selectedStandardId: selectedStandardId ?? this.selectedStandardId,
        ambientTemperature: ambientTemperature ?? this.ambientTemperature,
        notes: notes ?? this.notes,
        operatorName: operatorName ?? this.operatorName,
        operatorId:   operatorId   ?? this.operatorId,
        machineHydraulicAreaMm2: clearMachineHydraulics
            ? null
            : (machineHydraulicAreaMm2 ?? this.machineHydraulicAreaMm2),
        machineModel:           machineModel           ?? this.machineModel,
        machineSerialNumber:    machineSerialNumber    ?? this.machineSerialNumber,
        machineName:            machineName            ?? this.machineName,
        machineBrand:           machineBrand           ?? this.machineBrand,
        machineLastCalibration: machineLastCalibration ?? this.machineLastCalibration,
        machineNextCalibration: machineNextCalibration ?? this.machineNextCalibration,
        projectName:            projectName            ?? this.projectName,
        projectLocation:        projectLocation        ?? this.projectLocation,
        standardUsed:           standardUsed           ?? this.standardUsed,
        dragPressureBar: dragPressureBar ?? this.dragPressureBar,
        catalogWallThickness: (clearDiameter || clearSdr || clearPipe)
            ? null
            : (catalogWallThickness ?? this.catalogWallThickness),
        catalogPipeArea: (clearDiameter || clearSdr || clearPipe)
            ? null
            : (catalogPipeArea ?? this.catalogPipeArea),
        weldingTable: (clearTable || clearPipe || clearParams)
            ? null
            : (weldingTable ?? this.weldingTable),
        matchedParameters: (clearParams || clearPipe)
            ? null
            : (matchedParameters ?? this.matchedParameters),
        parametersFromFallback: clearParams
            ? false
            : (parametersFromFallback ?? this.parametersFromFallback),
        lookupError:
            clearLookupError ? null : (lookupError ?? this.lookupError),
        isSubmitting: isSubmitting ?? this.isSubmitting,
        submitError:
            clearSubmitError ? null : (submitError ?? this.submitError),
        createdWeldId:
            clearCreatedWeld ? null : (createdWeldId ?? this.createdWeldId),
        createdPhases:
            clearCreatedWeld ? null : (createdPhases ?? this.createdPhases),
        createdWeldNumber:
            clearCreatedWeld ? 0 : (createdWeldNumber ?? this.createdWeldNumber),
      );
}

/// Manages all state transitions for the WeldSetupScreen.
///
/// Flow:
///   1. Init: seed pipe catalog + load diameters from catalog
///   2. Select diameter → load SDRs from catalog
///   3. Select SDR → lookup pipe_area from catalog; compute DVS 2207 parameters
///   4. Material / Standard selectors update metadata only
///   5. Machine selection → load cylinder area; recompute DVS table
///   6. Drag pressure update → recompute DVS table
///   7. Start Weld → create DB record + navigate to session screen
class WeldSetupNotifier extends StateNotifier<WeldSetupState> {
  WeldSetupNotifier({
    required this.paramsRepo,
    required this.db,
  }) : super(const WeldSetupState()) {
    _init();
  }

  final WeldParametersRepository paramsRepo;
  final AppDatabase db;

  // ── Initialisation ────────────────────────────────────────────────────────

  Future<void> _init() async {
    // Seed both catalogs on first launch
    await PipesCatalogSeeder.seedIfNeeded(db);
    await WeldingDataSeeder.seedIfNeeded(db);

    // Load standards (for reference / display only)
    final stdResult = await paramsRepo.getStandards();
    stdResult.when(
      success: (standards) => state = state.copyWith(standards: standards),
      failure: (_) {},
    );

    // Load diameters from pipe catalog immediately — no prerequisites
    await _refreshDiameters();
  }

  // ── Selector handlers ─────────────────────────────────────────────────────

  Future<void> selectProject(String projectId) async {
    state = state.copyWith(selectedProjectId: projectId);
    final project = await db.projectsDao.getById(projectId);
    if (project != null) {
      state = state.copyWith(
        projectName:     project.name,
        projectLocation: project.location ?? '',
      );
    }
  }

  Future<void> selectMachine(String machineId) async {
    state = state.copyWith(
      selectedMachineId: machineId,
      clearMachineHydraulics: true,
      clearTable: true,
    );
    final machine = await db.machinesDao.getById(machineId);
    if (machine != null) {
      final displayName = '${machine.manufacturer} ${machine.model}'.trim();
      state = state.copyWith(
        machineHydraulicAreaMm2: machine.hydraulicCylinderAreaMm2,
        machineModel:            machine.model,
        machineSerialNumber:     machine.serialNumber,
        machineName:             displayName,
        machineBrand:            machine.manufacturer,
        machineLastCalibration:  machine.lastCalibrationDate ?? '',
        machineNextCalibration:  machine.nextCalibrationDate ?? '',
      );
    }
    _recomputeDvsTable();
  }

  /// Updates selected welding standard (metadata only — does not affect
  /// diameter/SDR lists which come from the pipe catalog).
  Future<void> selectStandard(String standardId) async {
    state = state.copyWith(selectedStandardId: standardId);
  }

  /// Updates selected material (metadata only — does not affect pipe selection).
  Future<void> selectMaterial(String material) async {
    state = state.copyWith(pipeMaterial: material);
    _recomputeDvsTable();
  }

  Future<void> selectDiameter(double diameterMm) async {
    state = state.copyWith(
      pipeDiameterMm: diameterMm,
      clearSdr: true,
      clearPipe: true,
      clearTable: true,
    );
    await _refreshSdrRatings();
  }

  Future<void> selectSdr(String sdr) async {
    state = state.copyWith(sdrRating: sdr, clearPipe: true, clearTable: true);
    await _lookupCatalogPipe();
  }

  void setAmbientTemperature(double temp) =>
      state = state.copyWith(ambientTemperature: temp);

  void setNotes(String notes) => state = state.copyWith(notes: notes);

  void setOperatorName(String name) =>
      state = state.copyWith(operatorName: name);

  void setOperatorId(String id) => state = state.copyWith(operatorId: id);

  void setDragPressure(double bar) {
    state = state.copyWith(dragPressureBar: bar, clearTable: true);
    _recomputeDvsTable();
  }

  // ── Cascading refresh ─────────────────────────────────────────────────────

  /// Loads all available diameters from the pipe catalog.
  Future<void> _refreshDiameters() async {
    final diameters = await db.pipesCatalogDao.getDistinctDiameters();
    state = state.copyWith(availableDiameters: diameters);
  }

  /// Loads SDR values for the selected diameter from the pipe catalog.
  Future<void> _refreshSdrRatings() async {
    final diameter = state.pipeDiameterMm;
    if (diameter == null) return;

    final sdrDoubles = await db.pipesCatalogDao.getSdrsForDiameter(diameter);
    // Format as strings matching the existing convention (e.g. '11', '17.6')
    final sdrs = sdrDoubles.map((s) {
      final asInt = s.truncate();
      return s == asInt.toDouble() ? asInt.toString() : s.toString();
    }).toList();

    state = state.copyWith(availableSdrRatings: sdrs);
  }

  /// Looks up pipe_area and wall_thickness from the catalog for the selected
  /// (de, sdr) pair, then triggers DVS parameter recomputation.
  Future<void> _lookupCatalogPipe() async {
    final diameter = state.pipeDiameterMm;
    final sdr = state.sdrRating;
    if (diameter == null || sdr == null) return;

    final sdrDouble = double.tryParse(sdr);
    if (sdrDouble == null) return;

    final pipe = await db.pipesCatalogDao.getByDiameterAndSdr(diameter, sdrDouble);
    if (pipe != null) {
      state = state.copyWith(
        catalogWallThickness: pipe.wallThickness,
        catalogPipeArea:      pipe.pipeArea,
        clearLookupError:     true,
      );
    } else {
      state = state.copyWith(
        lookupError: 'Pipe DN${diameter.toStringAsFixed(0)} SDR$sdr not found in catalog.',
      );
    }
    _recomputeDvsTable();
  }

  // ── DVS 2207 table computation ────────────────────────────────────────────

  /// Recomputes the welding table using the DVS 2207-1 formulas whenever
  /// any input (pipe, machine, drag pressure, material) changes.
  void _recomputeDvsTable() {
    final de            = state.pipeDiameterMm;
    final wallThickness = state.catalogWallThickness;
    final pipeArea      = state.catalogPipeArea;
    final material      = state.pipeMaterial ?? 'PE100';
    final sdr           = state.sdrRating ?? '';

    if (de == null || wallThickness == null || pipeArea == null) return;

    final table = WeldingTableGenerator.generateFromPipeCatalog(
      de:                de,
      wallThickness:     wallThickness,
      pipeArea:          pipeArea,
      cylinderAreaMm2:   state.machineHydraulicAreaMm2,
      dragPressureBar:   state.dragPressureBar,
      pipeMaterial:      material,
      sdrRating:         sdr,
    );

    state = state.copyWith(weldingTable: table);
  }

  // ── Start weld ────────────────────────────────────────────────────────────

  Future<void> startWeld() async {
    if (!state.isReadyToStart) return;

    state = state.copyWith(isSubmitting: true, clearSubmitError: true);

    try {
      // 1. Determine weld type from standard (default = butt_fusion)
      final standard = state.standards
          .where((s) => s.id == state.selectedStandardId)
          .firstOrNull;
      final weldType = standard?.weldType ?? 'butt_fusion';

      // 2. Validate ambient temperature (DVS 2207: -5 to +40 °C for PE)
      final ambient = state.ambientTemperature;
      if (ambient != null && (ambient < -5 || ambient > 40)) {
        state = state.copyWith(
          isSubmitting: false,
          submitError:
              'Ambient temperature ${ambient.toStringAsFixed(1)} °C is outside '
              'the DVS 2207 allowed range (−5 to +40 °C).',
        );
        return;
      }

      // 3. Resolve operator ID
      final operatorId = state.operatorId.isEmpty
          ? 'unknown-operator'
          : state.operatorId;
      final resolvedStandardUsed = standard?.code ?? 'DVS_2207';

      // 4. Wall thickness (from catalog)
      final wallThickness = state.catalogWallThickness ??
          (state.pipeDiameterMm! /
              (double.tryParse(state.sdrRating ?? '11') ?? 11.0));

      // 5. Create local weld record
      final weldId = const Uuid().v4();
      final now    = DateTime.now();
      await db.weldsDao.insertWeld(WeldsTableCompanion(
        id:               Value(weldId),
        projectId:        Value(state.selectedProjectId!),
        machineId:        Value(state.selectedMachineId!),
        operatorId:       Value(operatorId),
        weldType:         Value(weldType),
        status:           const Value('in_progress'),
        pipeMaterial:     Value(state.pipeMaterial!),
        pipeDiameter:     Value(state.pipeDiameterMm!),
        pipeSdr:          Value(state.sdrRating),
        pipeWallThickness: Value(wallThickness),
        ambientTemperature: Value(state.ambientTemperature),
        standardId:       Value(state.selectedStandardId),
        standardUsed:     Value(standard?.code ?? 'DVS_2207'),
        notes:            Value(state.notes),
        startedAt:        Value(now),
        createdAt:        Value(now),
        updatedAt:        Value(now),
        syncStatus:       const Value('pending'),
      ));

      // 6. Use DVS-computed phases from the welding table
      final table  = state.weldingTable!;
      final phases = table.phases;

      // 7. Compute sequential weld number for this project (1-based)
      final projectWelds =
          await db.weldsDao.getByProject(state.selectedProjectId!);
      final weldNumber = projectWelds.length; // includes the just-inserted row

      state = state.copyWith(
        isSubmitting:      false,
        createdWeldId:     weldId,
        createdPhases:     phases,
        standardUsed:      resolvedStandardUsed,
        createdWeldNumber: weldNumber,
      );
    } catch (e) {
      state = state.copyWith(
        isSubmitting: false,
        submitError:  'Failed to create weld: ${e.toString()}',
      );
    }
  }

  /// Called after the screen has read [createdWeldId] and navigated away.
  void resetCreated() {
    state = state.copyWith(clearCreatedWeld: true);
  }
}
