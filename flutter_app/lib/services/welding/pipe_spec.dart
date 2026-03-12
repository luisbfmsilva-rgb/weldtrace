import 'dart:math' as math;

/// Geometric specification of the pipe being welded.
///
/// All derived geometry is computed lazily from [outerDiameterMm] and
/// [sdrRatio], which are the two values the operator enters on the setup
/// screen (the database stores [sdrRatio] as a string such as "11" or
/// "17.6" — parse with [double.parse] before constructing).
class PipeSpec {
  const PipeSpec({
    required this.outerDiameterMm,
    required this.sdrRatio,
    required this.material,
  }) : assert(outerDiameterMm > 0, 'OD must be positive'),
       assert(sdrRatio > 1, 'SDR must be > 1');

  /// Nominal outer diameter, OD [mm].
  final double outerDiameterMm;

  /// Standard Dimension Ratio, e.g. 11.0 or 17.6.
  final double sdrRatio;

  /// Material identifier, e.g. 'PE' or 'PP'.
  final String material;

  // ── Derived geometry ────────────────────────────────────────────────────────

  /// Wall thickness:  e = OD / SDR  [mm]
  double get wallThicknessMm => outerDiameterMm / sdrRatio;

  /// Pipe annulus (end-face) area:  A = π × (OD − e) × e  [mm²]
  ///
  /// This is the area of the annular cross-section that receives the
  /// interfacial (face) pressure during butt-fusion welding.
  double get pipeAnnulusAreaMm2 {
    final e = wallThicknessMm;
    return math.pi * (outerDiameterMm - e) * e;
  }

  /// Minimum bead height per ISO 21307 Table 4 / DVS 2207 Part 1 Table 4.
  ///
  /// e ≤ 4.5 mm  →  0.5 mm
  /// 4.5 < e ≤ 7.0 mm  →  1.0 mm
  /// 7.0 < e ≤ 12.0 mm  →  1.5 mm
  /// e > 12.0 mm  →  2.0 mm
  double get minBeadHeightMm {
    final e = wallThicknessMm;
    if (e <= 4.5) return 0.5;
    if (e <= 7.0) return 1.0;
    if (e <= 12.0) return 1.5;
    return 2.0;
  }

  @override
  String toString() =>
      'PipeSpec(OD=${outerDiameterMm}mm, SDR=$sdrRatio, e=${wallThicknessMm.toStringAsFixed(2)}mm, $material)';
}

/// Hydraulic and operational spec of the welding machine being used.
///
/// The cylinder area is stamped on the machine data plate or available
/// in the calibration certificate.  It may be null for older records
/// that pre-date this field — the generator falls back gracefully.
class MachineSpec {
  const MachineSpec({
    this.hydraulicCylinderAreaMm2,
    this.dragPressureBar = 0.0,
  }) : assert(
          hydraulicCylinderAreaMm2 == null || hydraulicCylinderAreaMm2 > 0,
          'Cylinder area must be positive',
        ),
       assert(dragPressureBar >= 0, 'Drag pressure cannot be negative');

  /// Area of the hydraulic cylinder piston  [mm²].
  ///
  /// Null means the machine's cylinder area is unknown — the generator
  /// will return interfacial pressures unchanged.
  final double? hydraulicCylinderAreaMm2;

  /// Drag pressure measured just before welding  [bar].
  ///
  /// This is the hydraulic pressure required to move the carriage with no
  /// load (friction only).  It is added to every machine gauge target.
  final double dragPressureBar;

  /// True if enough data is available to convert interfacial → machine pressure.
  bool get hasHydraulicData =>
      hydraulicCylinderAreaMm2 != null && hydraulicCylinderAreaMm2! > 0;
}
