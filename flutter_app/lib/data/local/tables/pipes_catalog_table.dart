import 'package:drift/drift.dart';

/// Local catalog of pipe dimensional data.
///
/// Each row represents one (de × SDR) combination.
/// Values match the Geotubos catalog spreadsheet provided during project setup.
///
/// Columns:
///   de             — nominal outer diameter [mm]
///   sdr            — SDR ratio (e.g. 6, 7.4, 11, 17)
///   wallThickness  — wall thickness [mm] = de / sdr
///   pipeArea       — annular cross-section area [mm²]
///                    = π × (de² − (de − 2e)²) / 4
@DataClassName('PipeCatalogRecord')
class PipesCatalogTable extends Table {
  @override
  String get tableName => 'pipes_catalog';

  IntColumn get id           => integer().autoIncrement()();
  RealColumn get de          => real()();
  RealColumn get sdr         => real()();
  RealColumn get wallThickness => real()();
  RealColumn get pipeArea    => real()();
}
