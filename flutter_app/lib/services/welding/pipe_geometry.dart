import 'dart:math' as math;

/// Pure-static utility for thermoplastic pipe geometry.
///
/// All formulas follow ISO 4427 / EN 12201 conventions:
///
///   SDR  = OD / e              (Standard Dimension Ratio)
///   e    = OD / SDR            (wall thickness)
///   A_ann = π × (OD − e) × e  (annular end-face area — receives interfacial pressure)
///   A_cs  = π × OD² / 4       (full circular cross-section area)
///
/// Units: millimetres [mm], square millimetres [mm²].
class PipeGeometry {
  PipeGeometry._();

  // ── SDR parsing ──────────────────────────────────────────────────────────────

  /// Parses a human-readable SDR rating string to a numeric SDR value.
  ///
  /// Accepted formats:
  ///   'SDR11', 'sdr11', 'SDR 11', '11', '17.6'
  ///
  /// Throws [FormatException] when the numeric part cannot be parsed.
  static double parseSdr(String sdrRating) {
    // Strip any leading 'SDR' prefix (case-insensitive) and whitespace.
    final cleaned = sdrRating.trim().replaceAll(RegExp(r'sdr\s*', caseSensitive: false), '');
    final value = double.tryParse(cleaned);
    if (value == null || value <= 1) {
      throw FormatException(
          'Invalid SDR rating: "$sdrRating". Expected a number > 1.');
    }
    return value;
  }

  // ── Geometry functions ───────────────────────────────────────────────────────

  /// Wall thickness:  e = OD / SDR  [mm]
  ///
  /// [diameter] — nominal outer diameter OD [mm]
  /// [sdr]      — Standard Dimension Ratio (dimensionless)
  static double wallThickness(double diameter, double sdr) {
    assert(diameter > 0, 'Diameter must be positive');
    assert(sdr > 1, 'SDR must be > 1');
    return diameter / sdr;
  }

  /// Annular end-face area:  A = π × (OD − e) × e  [mm²]
  ///
  /// This is the area that receives interfacial (face) pressure
  /// during butt-fusion welding.
  ///
  /// [diameter]      — OD [mm]
  /// [wallThick]     — wall thickness e [mm]
  static double pipeAnnulusArea(double diameter, double wallThick) {
    assert(diameter > 0);
    assert(wallThick > 0 && wallThick < diameter / 2);
    return math.pi * (diameter - wallThick) * wallThick;
  }

  /// Full circular cross-section area:  A = π × OD² / 4  [mm²]
  ///
  /// Used for calculating pipe cross-section loads; not typically
  /// needed for butt-fusion pressure calculations.
  ///
  /// [diameter] — OD [mm]
  static double pipeCrossSectionArea(double diameter) {
    assert(diameter > 0);
    return math.pi * diameter * diameter / 4.0;
  }

  // ── Convenience all-in-one ───────────────────────────────────────────────────

  /// Returns [wallThickness] and [pipeAnnulusArea] in one call.
  ///
  /// [diameter]  — OD [mm]
  /// [sdrRating] — SDR string (e.g. 'SDR11', '17.6')
  static ({double wallThicknessMm, double annulusAreaMm2}) geometry(
      double diameter, String sdrRating) {
    final sdr = parseSdr(sdrRating);
    final e = wallThickness(diameter, sdr);
    return (wallThicknessMm: e, annulusAreaMm2: pipeAnnulusArea(diameter, e));
  }
}
