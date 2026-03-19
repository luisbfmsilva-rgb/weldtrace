import 'package:logger/logger.dart';

import '../../core/errors/app_exception.dart';
import '../../core/utils/result.dart';
import '../local/database/app_database.dart';
import '../../workflow/welding_phase.dart';

/// Provides read access to welding standards and parameter records stored
/// locally in SQLite (populated via the sync download endpoint).
///
/// Also converts a [WeldingParameterRecord] into the list of
/// [PhaseParameters] consumed by the [WeldWorkflowEngine].
class WeldParametersRepository {
  WeldParametersRepository({required this.db, Logger? logger})
      : _logger = logger ?? Logger();

  final AppDatabase db;
  final Logger _logger;

  // ── Standards ─────────────────────────────────────────────────────────────

  Future<Result<List<WeldingStandardRecord>>> getStandards() async {
    try {
      final rows = await db.weldingParametersDao.getAllStandards();
      return Success(rows);
    } catch (e) {
      _logger.e('[WeldParams] Failed to load standards', error: e);
      return Failure(DatabaseException('Could not load welding standards', e));
    }
  }

  // ── Cascading selectors ───────────────────────────────────────────────────

  Future<Result<List<double>>> getAvailableDiameters({
    required String standardId,
    required String pipeMaterial,
  }) async {
    try {
      final diameters = await db.weldingParametersDao.getAvailableDiameters(
        standardId: standardId,
        pipeMaterial: pipeMaterial,
      );
      return Success(diameters);
    } catch (e) {
      return Failure(DatabaseException('Could not load diameters', e));
    }
  }

  Future<Result<List<String>>> getAvailableSdrRatings({
    required String standardId,
    required String pipeMaterial,
    required double pipeDiameterMm,
  }) async {
    try {
      final ratings = await db.weldingParametersDao.getAvailableSdrRatings(
        standardId: standardId,
        pipeMaterial: pipeMaterial,
        pipeDiameterMm: pipeDiameterMm,
      );
      return Success(ratings);
    } catch (e) {
      return Failure(DatabaseException('Could not load SDR ratings', e));
    }
  }

  // ── Parameter lookup ──────────────────────────────────────────────────────

  Future<Result<WeldingParameterRecord>> lookupParameters({
    required String standardId,
    required String pipeMaterial,
    required double pipeDiameterMm,
    required String sdrRating,
  }) async {
    try {
      final record = await db.weldingParametersDao.lookupParameters(
        standardId: standardId,
        pipeMaterial: pipeMaterial,
        pipeDiameterMm: pipeDiameterMm,
        sdrRating: sdrRating,
      );
      if (record == null) {
        return const Failure(WeldValidationException(
          'No parameters found for this pipe specification and standard. '
          'Contact your supervisor to add parameters to the system.',
        ));
      }
      return Success(record);
    } catch (e) {
      return Failure(DatabaseException('Parameter lookup failed', e));
    }
  }

  // ── Phase conversion ──────────────────────────────────────────────────────

  /// Converts a [WeldingParameterRecord] into ordered [PhaseParameters]
  /// ready for the [WeldWorkflowEngine].
  ///
  /// For butt-fusion standards (DVS 2207, ISO 21307, ASTM F2620) this
  /// produces 6 phases: heating-up → heating → changeover → build-up
  ///                      → fusion → cooling.
  ///
  /// For electrofusion standards: clamping → welding → cooling.
  static List<PhaseParameters> buildPhaseParameters(
    WeldingParameterRecord r,
    String weldType,
  ) {
    if (weldType == 'electrofusion') {
      return _buildElectrofusionPhases(r);
    }
    return _buildButtFusionPhases(r);
  }

  static List<PhaseParameters> _buildButtFusionPhases(
      WeldingParameterRecord r) {
    const defaultTol = 0.1; // 10 % tolerance used when min/max not stored

    return [
      // 1. Heating-up ─────────────────────────────────────────────────────
      PhaseParameters(
        phase: WeldingPhase.heatingUp,
        nominalDuration: (r.heatingUpTimeS ?? 30).toDouble(),
        minDuration: 0,
        maxDuration: ((r.heatingUpTimeS ?? 30) * 1.5).toDouble(),
        nominalPressureBar: r.heatingUpPressureBar,
        minPressureBar: r.heatingUpPressureBar != null
            ? r.heatingUpPressureBar! * (1 - defaultTol)
            : null,
        maxPressureBar: r.heatingUpPressureBar != null
            ? r.heatingUpPressureBar! * (1 + defaultTol)
            : null,
      ),

      // 2. Heating ────────────────────────────────────────────────────────
      PhaseParameters(
        phase: WeldingPhase.heating,
        nominalDuration: (r.heatingTimeS ?? 60).toDouble(),
        minDuration: ((r.heatingTimeS ?? 60) * 0.9).toDouble(),
        maxDuration: ((r.heatingTimeS ?? 60) * 1.1).toDouble(),
        nominalPressureBar: r.heatingPressureBar,
        minPressureBar: r.heatingPressureBar != null
            ? r.heatingPressureBar! * (1 - defaultTol)
            : null,
        maxPressureBar: r.heatingPressureBar != null
            ? r.heatingPressureBar! * (1 + defaultTol)
            : null,
        nominalTemperatureCelsius: r.heatingTempNominalCelsius,
        minTemperatureCelsius: r.heatingTempMinCelsius,
        maxTemperatureCelsius: r.heatingTempMaxCelsius,
      ),

      // 3. Changeover ─────────────────────────────────────────────────────
      PhaseParameters(
        phase: WeldingPhase.changeover,
        nominalDuration: 0,
        minDuration: 0,
        maxDuration: (r.changeoverTimeMaxS ?? 10).toDouble(),
      ),

      // 4. Pressure build-up ──────────────────────────────────────────────
      PhaseParameters(
        phase: WeldingPhase.buildup,
        nominalDuration: (r.buildupTimeS ?? 15).toDouble(),
        minDuration: 0,
        maxDuration: ((r.buildupTimeS ?? 15) * 2.0).toDouble(),
        nominalPressureBar: r.fusionPressureBar,
        minPressureBar: null,                    // ramping — no lower bound
        maxPressureBar: r.fusionPressureMaxBar,
      ),

      // 5. Fusion ─────────────────────────────────────────────────────────
      PhaseParameters(
        phase: WeldingPhase.fusion,
        nominalDuration: (r.fusionTimeS ?? 120).toDouble(),
        minDuration: ((r.fusionTimeS ?? 120) * 0.95).toDouble(),
        maxDuration: ((r.fusionTimeS ?? 120) * 1.05).toDouble(),
        nominalPressureBar: r.fusionPressureBar,
        minPressureBar: r.fusionPressureMinBar ??
            (r.fusionPressureBar != null
                ? r.fusionPressureBar! * (1 - defaultTol)
                : null),
        maxPressureBar: r.fusionPressureMaxBar ??
            (r.fusionPressureBar != null
                ? r.fusionPressureBar! * (1 + defaultTol)
                : null),
      ),

      // 6. Cooling ────────────────────────────────────────────────────────
      PhaseParameters(
        phase: WeldingPhase.cooling,
        nominalDuration: (r.coolingTimeS ?? 300).toDouble(),
        minDuration: ((r.coolingTimeS ?? 300) * 0.95).toDouble(),
        maxDuration: ((r.coolingTimeS ?? 300) * 1.2).toDouble(),
        nominalPressureBar: r.coolingPressureBar ?? r.fusionPressureBar,
        minPressureBar: r.coolingPressureBar != null
            ? r.coolingPressureBar! * (1 - defaultTol)
            : null,
        maxPressureBar: r.coolingPressureBar != null
            ? r.coolingPressureBar! * (1 + defaultTol)
            : null,
      ),
    ];
  }

  static List<PhaseParameters> _buildElectrofusionPhases(
      WeldingParameterRecord r) {
    return [
      PhaseParameters(
        phase: WeldingPhase.efClamping,
        nominalDuration: 60,
        minDuration: 30,
        maxDuration: 300,
      ),
      PhaseParameters(
        phase: WeldingPhase.efWelding,
        nominalDuration: (r.efWeldingTimeS ?? 60).toDouble(),
        minDuration: ((r.efWeldingTimeS ?? 60) * 0.98).toDouble(),
        maxDuration: ((r.efWeldingTimeS ?? 60) * 1.02).toDouble(),
      ),
      PhaseParameters(
        phase: WeldingPhase.efCooling,
        nominalDuration: (r.efCoolingTimeS ?? 180).toDouble(),
        minDuration: ((r.efCoolingTimeS ?? 180) * 0.95).toDouble(),
        maxDuration: ((r.efCoolingTimeS ?? 180) * 1.2).toDouble(),
      ),
    ];
  }
}
