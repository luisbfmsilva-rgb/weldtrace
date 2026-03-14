-- WeldTrace: Welding Standards Seed Data
-- Covers DVS 2207, ISO 21307, and ASTM F2620
-- Parameters are representative values for PE100 and PP pipes.
-- Production deployments should expand these with full standard tables.

-- ============================================================
-- DVS 2207-1 — Butt Fusion (PE, PP)
-- ============================================================
INSERT INTO welding_standards (id, standard_code, weld_type, pipe_material, version, description, valid_from)
VALUES
    ('a1000000-0000-0000-0000-000000000001', 'DVS_2207', 'butt_fusion', 'PE', '2015', 'DVS 2207-1: Welding of thermoplastics – Heated tool butt welding of pipes, fittings and sheets made of PE', '2015-01-01'),
    ('a1000000-0000-0000-0000-000000000002', 'DVS_2207', 'electrofusion', 'PE', '2015', 'DVS 2207-1: Welding of thermoplastics – Electrofusion welding of PE pipes and fittings', '2015-01-01'),
    ('a1000000-0000-0000-0000-000000000003', 'DVS_2207', 'butt_fusion', 'PP', '2015', 'DVS 2207-11: Welding of thermoplastics – Heated tool butt welding of PP pipes and fittings', '2015-01-01');

-- ============================================================
-- ISO 21307 — Butt Fusion (PE, PA, PP)
-- ============================================================
INSERT INTO welding_standards (id, standard_code, weld_type, pipe_material, version, description, valid_from)
VALUES
    ('a2000000-0000-0000-0000-000000000001', 'ISO_21307', 'butt_fusion', 'PE', '2017', 'ISO 21307:2017 Plastics pipes and fittings — Butt fusion jointing procedures for PE pipes and fittings', '2017-01-01'),
    ('a2000000-0000-0000-0000-000000000002', 'ISO_21307', 'butt_fusion', 'PP', '2017', 'ISO 21307:2017 Plastics pipes and fittings — Butt fusion jointing procedures for PP pipes and fittings', '2017-01-01');

-- ============================================================
-- ASTM F2620 — Butt Fusion (HDPE, PE)
-- ============================================================
INSERT INTO welding_standards (id, standard_code, weld_type, pipe_material, version, description, valid_from)
VALUES
    ('a3000000-0000-0000-0000-000000000001', 'ASTM_F2620', 'butt_fusion', 'PE', '2019', 'ASTM F2620: Standard Practice for Heat Fusion Joining of Polyethylene Pipe and Fittings', '2019-01-01');

-- ============================================================
-- DVS 2207 — BUTT FUSION PARAMETERS (PE, DN 63–630, SDR 11)
-- Phase order follows DVS 2207-1 workflow
-- ============================================================

-- Phase 1: Preparation (ambient check, surface cleaning)
INSERT INTO welding_parameters (standard_id, phase_name, phase_order, parameter_name, unit, nominal_value, min_value, max_value, pipe_diameter_min, pipe_diameter_max, pipe_sdr, notes)
VALUES
    ('a1000000-0000-0000-0000-000000000001', 'preparation', 1, 'ambient_temperature', '°C', 10, -5, 40, 63, 630, 'SDR11', 'If below 5°C, windbreak and preheat required'),
    ('a1000000-0000-0000-0000-000000000001', 'preparation', 1, 'surface_cleanliness', 'visual', NULL, NULL, NULL, 63, 630, 'SDR11', 'Surface must be clean, dry, and free of contamination');

-- Phase 2: Drag Pressure measurement
INSERT INTO welding_parameters (standard_id, phase_name, phase_order, parameter_name, unit, nominal_value, min_value, max_value, pipe_diameter_min, pipe_diameter_max, pipe_sdr, notes)
VALUES
    ('a1000000-0000-0000-0000-000000000001', 'drag_pressure', 2, 'drag_pressure', 'bar', NULL, 0.05, 0.5, 63, 200, 'SDR11', 'Measured with pipe ends clamped, machine moving without pressure'),
    ('a1000000-0000-0000-0000-000000000001', 'drag_pressure', 2, 'drag_pressure', 'bar', NULL, 0.1, 0.8, 200, 630, 'SDR11', 'Larger diameter machines have higher drag');

-- Phase 3: Facing
INSERT INTO welding_parameters (standard_id, phase_name, phase_order, parameter_name, unit, nominal_value, min_value, max_value, pipe_diameter_min, pipe_diameter_max, pipe_sdr, notes)
VALUES
    ('a1000000-0000-0000-0000-000000000001', 'facing', 3, 'planarity_gap', 'mm', 0, 0, 0.3, 63, 630, 'SDR11', 'Maximum gap between faced pipe ends'),
    ('a1000000-0000-0000-0000-000000000001', 'facing', 3, 'misalignment', 'mm', 0, 0, 0.5, 63, 630, 'SDR11', 'Maximum offset between pipe wall edges');

-- Phase 4: Pre-heating
INSERT INTO welding_parameters (standard_id, phase_name, phase_order, parameter_name, unit, nominal_value, min_value, max_value, pipe_diameter_min, pipe_diameter_max, pipe_sdr, notes)
VALUES
    ('a1000000-0000-0000-0000-000000000001', 'preheating', 4, 'heating_pressure', 'bar', NULL, 0.15, 0.25, 63, 200, 'SDR11', 'Pre-heating phase: low pressure to ensure contact'),
    ('a1000000-0000-0000-0000-000000000001', 'preheating', 4, 'heating_pressure', 'bar', NULL, 0.15, 0.25, 200, 630, 'SDR11', 'Pre-heating phase: low pressure to ensure contact');

-- Phase 5: Heating (bead height targets per DN)
INSERT INTO welding_parameters (standard_id, phase_name, phase_order, parameter_name, unit, nominal_value, min_value, max_value, pipe_diameter_min, pipe_diameter_max, pipe_sdr, notes)
VALUES
    ('a1000000-0000-0000-0000-000000000001', 'heating', 5, 'heating_plate_temperature', '°C', 210, 200, 230, 63, 630, 'SDR11', 'Heating plate temperature per DVS 2207-1 for PE'),
    ('a1000000-0000-0000-0000-000000000001', 'heating', 5, 'heating_pressure', 'bar', 0.15, 0.1, 0.2, 63, 200, 'SDR11', 'Reduced to near-zero after bead forms'),
    ('a1000000-0000-0000-0000-000000000001', 'heating', 5, 'heating_time', 's', 85, 75, 95, 63, 125, 'SDR11', 'Heating time for DN63–125'),
    ('a1000000-0000-0000-0000-000000000001', 'heating', 5, 'heating_time', 's', 135, 120, 150, 125, 200, 'SDR11', 'Heating time for DN125–200'),
    ('a1000000-0000-0000-0000-000000000001', 'heating', 5, 'heating_time', 's', 210, 190, 230, 200, 315, 'SDR11', 'Heating time for DN200–315'),
    ('a1000000-0000-0000-0000-000000000001', 'heating', 5, 'heating_time', 's', 330, 295, 365, 315, 450, 'SDR11', 'Heating time for DN315–450'),
    ('a1000000-0000-0000-0000-000000000001', 'heating', 5, 'heating_time', 's', 450, 400, 500, 450, 630, 'SDR11', 'Heating time for DN450–630');

-- Phase 6: Plate Removal
INSERT INTO welding_parameters (standard_id, phase_name, phase_order, parameter_name, unit, nominal_value, min_value, max_value, pipe_diameter_min, pipe_diameter_max, pipe_sdr, notes)
VALUES
    ('a1000000-0000-0000-0000-000000000001', 'plate_removal', 6, 'changeover_time', 's', 6, 0, 10, 63, 200, 'SDR11', 'Max time from plate removal to pressure application (small DN)'),
    ('a1000000-0000-0000-0000-000000000001', 'plate_removal', 6, 'changeover_time', 's', 8, 0, 14, 200, 400, 'SDR11', 'Max changeover time for medium DN'),
    ('a1000000-0000-0000-0000-000000000001', 'plate_removal', 6, 'changeover_time', 's', 10, 0, 18, 400, 630, 'SDR11', 'Max changeover time for large DN');

-- Phase 7: Pressure Application (joining pressure)
INSERT INTO welding_parameters (standard_id, phase_name, phase_order, parameter_name, unit, nominal_value, min_value, max_value, pipe_diameter_min, pipe_diameter_max, pipe_sdr, notes)
VALUES
    ('a1000000-0000-0000-0000-000000000001', 'pressure_application', 7, 'joining_pressure', 'bar', 0.15, 0.12, 0.18, 63, 200, 'SDR11', 'Joining pressure = drag pressure + pipe area calculated pressure'),
    ('a1000000-0000-0000-0000-000000000001', 'pressure_application', 7, 'pressure_buildup_time', 's', 10, 0, 20, 63, 630, 'SDR11', 'Time to reach full joining pressure after plate removal'),
    ('a1000000-0000-0000-0000-000000000001', 'pressure_application', 7, 'joining_pressure', 'bar', 0.15, 0.12, 0.18, 200, 630, 'SDR11', 'Joining pressure maintained throughout cooling');

-- Phase 8: Cooling
INSERT INTO welding_parameters (standard_id, phase_name, phase_order, parameter_name, unit, nominal_value, min_value, max_value, pipe_diameter_min, pipe_diameter_max, pipe_sdr, notes)
VALUES
    ('a1000000-0000-0000-0000-000000000001', 'cooling', 8, 'cooling_time', 'min', 15, 12, NULL, 63, 125, 'SDR11', 'Minimum cooling time for DN63–125 under pressure'),
    ('a1000000-0000-0000-0000-000000000001', 'cooling', 8, 'cooling_time', 'min', 25, 22, NULL, 125, 200, 'SDR11', 'Minimum cooling time for DN125–200'),
    ('a1000000-0000-0000-0000-000000000001', 'cooling', 8, 'cooling_time', 'min', 40, 35, NULL, 200, 315, 'SDR11', 'Minimum cooling time for DN200–315'),
    ('a1000000-0000-0000-0000-000000000001', 'cooling', 8, 'cooling_time', 'min', 60, 55, NULL, 315, 450, 'SDR11', 'Minimum cooling time for DN315–450'),
    ('a1000000-0000-0000-0000-000000000001', 'cooling', 8, 'cooling_time', 'min', 90, 80, NULL, 450, 630, 'SDR11', 'Minimum cooling time for DN450–630'),
    ('a1000000-0000-0000-0000-000000000001', 'cooling', 8, 'cooling_pressure', 'bar', 0.15, 0.12, 0.18, 63, 630, 'SDR11', 'Joining pressure must be maintained throughout cooling');

-- Phase 9: Finalization
INSERT INTO welding_parameters (standard_id, phase_name, phase_order, parameter_name, unit, nominal_value, min_value, max_value, pipe_diameter_min, pipe_diameter_max, pipe_sdr, notes)
VALUES
    ('a1000000-0000-0000-0000-000000000001', 'finalization', 9, 'bead_symmetry', 'visual', NULL, NULL, NULL, 63, 630, 'SDR11', 'Bead must be symmetric and continuous around full circumference'),
    ('a1000000-0000-0000-0000-000000000001', 'finalization', 9, 'bead_height_ratio', 'ratio', NULL, 0.5, 1.5, 63, 630, 'SDR11', 'Ratio of actual bead height to nominal bead height');

-- ============================================================
-- DVS 2207 — ELECTROFUSION PARAMETERS (PE)
-- ============================================================
INSERT INTO welding_parameters (standard_id, phase_name, phase_order, parameter_name, unit, nominal_value, min_value, max_value, pipe_diameter_min, pipe_diameter_max, pipe_sdr, notes)
VALUES
    ('a1000000-0000-0000-0000-000000000002', 'preparation', 1, 'ambient_temperature', '°C', 10, -10, 40, 20, 630, NULL, 'Ambient temperature during electrofusion'),
    ('a1000000-0000-0000-0000-000000000002', 'preparation', 1, 'scraping_depth', 'mm', 0.2, 0.1, 0.5, 20, 630, NULL, 'Oxide layer removal depth by pipe scraper'),
    ('a1000000-0000-0000-0000-000000000002', 'preparation', 1, 'clamping_time', 'min', NULL, 30, NULL, 20, 630, NULL, 'Minimum clamping time after fusion completes'),
    ('a1000000-0000-0000-0000-000000000002', 'heating', 2, 'fusion_voltage', 'V', 40, 38, 42, 20, 630, NULL, 'Standard fusion voltage per ISO 12176-2'),
    ('a1000000-0000-0000-0000-000000000002', 'heating', 2, 'fusion_time', 's', NULL, NULL, NULL, 20, 630, NULL, 'Fusion time from fitting barcode/datamatrix'),
    ('a1000000-0000-0000-0000-000000000002', 'cooling', 3, 'cooling_time', 'min', NULL, NULL, NULL, 20, 630, NULL, 'Cooling time from fitting barcode/datamatrix'),
    ('a1000000-0000-0000-0000-000000000002', 'finalization', 4, 'indicator_pin_check', 'visual', NULL, NULL, NULL, 20, 630, NULL, 'Fusion indicator pins must be raised on both sides');

-- ============================================================
-- ISO 21307 — BUTT FUSION PARAMETERS (PE, dual-pressure method)
-- ============================================================
INSERT INTO welding_parameters (standard_id, phase_name, phase_order, parameter_name, unit, nominal_value, min_value, max_value, pipe_diameter_min, pipe_diameter_max, pipe_sdr, notes)
VALUES
    ('a2000000-0000-0000-0000-000000000001', 'preparation', 1, 'ambient_temperature', '°C', 10, -5, 40, 63, 630, 'SDR11', 'ISO 21307 preparation conditions'),
    ('a2000000-0000-0000-0000-000000000001', 'heating', 5, 'heating_plate_temperature', '°C', 210, 200, 230, 63, 630, 'SDR11', 'ISO 21307 heating plate temperature for PE'),
    ('a2000000-0000-0000-0000-000000000001', 'heating', 5, 'heating_time', 's', 85, 75, 95, 63, 125, 'SDR11', 'ISO 21307 heating time for DN63–125'),
    ('a2000000-0000-0000-0000-000000000001', 'heating', 5, 'heating_time', 's', 135, 120, 150, 125, 200, 'SDR11', 'ISO 21307 heating time for DN125–200'),
    ('a2000000-0000-0000-0000-000000000001', 'heating', 5, 'heating_time', 's', 210, 190, 230, 200, 315, 'SDR11', 'ISO 21307 heating time for DN200–315'),
    ('a2000000-0000-0000-0000-000000000001', 'plate_removal', 6, 'changeover_time', 's', 6, 0, 10, 63, 200, 'SDR11', 'ISO 21307 maximum changeover time'),
    ('a2000000-0000-0000-0000-000000000001', 'pressure_application', 7, 'joining_pressure', 'bar', 0.15, 0.12, 0.18, 63, 200, 'SDR11', 'ISO 21307 joining pressure (single pressure method)'),
    ('a2000000-0000-0000-0000-000000000001', 'cooling', 8, 'cooling_time', 'min', 15, 12, NULL, 63, 125, 'SDR11', 'ISO 21307 minimum cooling time DN63–125'),
    ('a2000000-0000-0000-0000-000000000001', 'cooling', 8, 'cooling_time', 'min', 25, 22, NULL, 125, 200, 'SDR11', 'ISO 21307 minimum cooling time DN125–200'),
    ('a2000000-0000-0000-0000-000000000001', 'cooling', 8, 'cooling_time', 'min', 40, 35, NULL, 200, 315, 'SDR11', 'ISO 21307 minimum cooling time DN200–315');

-- ============================================================
-- ASTM F2620 — BUTT FUSION PARAMETERS (HDPE/PE)
-- ============================================================
INSERT INTO welding_parameters (standard_id, phase_name, phase_order, parameter_name, unit, nominal_value, min_value, max_value, pipe_diameter_min, pipe_diameter_max, pipe_sdr, notes)
VALUES
    ('a3000000-0000-0000-0000-000000000001', 'preparation', 1, 'ambient_temperature', '°F', 50, 32, 104, 0.5, 63, 'DR11', 'ASTM F2620 ambient condition — Fahrenheit'),
    ('a3000000-0000-0000-0000-000000000001', 'heating', 5, 'heating_plate_temperature', '°F', 400, 390, 450, 0.5, 63, 'DR11', 'ASTM F2620 heater plate temperature for HDPE (≈ 204–232°C)'),
    ('a3000000-0000-0000-0000-000000000001', 'heating', 5, 'melt_bead_size', 'in', 0.125, 0.063, 0.188, 0.5, 12, 'DR11', 'Required melt bead height before plate removal'),
    ('a3000000-0000-0000-0000-000000000001', 'heating', 5, 'fusion_pressure', 'psi', 75, 60, 90, 0.5, 12, 'DR11', 'Interface fusion pressure during heating phase'),
    ('a3000000-0000-0000-0000-000000000001', 'plate_removal', 6, 'changeover_time', 's', 10, 0, 15, 0.5, 12, 'DR11', 'ASTM F2620 maximum plate removal to joining time'),
    ('a3000000-0000-0000-0000-000000000001', 'pressure_application', 7, 'joining_pressure', 'psi', 75, 60, 90, 0.5, 12, 'DR11', 'ASTM F2620 joining and cooling pressure'),
    ('a3000000-0000-0000-0000-000000000001', 'cooling', 8, 'cooling_time', 'min', 11, 9, NULL, 0.5, 4, 'DR11', 'ASTM F2620 minimum cooling time for 0.5–4 inch pipe'),
    ('a3000000-0000-0000-0000-000000000001', 'cooling', 8, 'cooling_time', 'min', 22, 18, NULL, 4, 8, 'DR11', 'ASTM F2620 minimum cooling time for 4–8 inch pipe'),
    ('a3000000-0000-0000-0000-000000000001', 'cooling', 8, 'cooling_time', 'min', 35, 30, NULL, 8, 12, 'DR11', 'ASTM F2620 minimum cooling time for 8–12 inch pipe'),
    ('a3000000-0000-0000-0000-000000000001', 'finalization', 9, 'bead_appearance', 'visual', NULL, NULL, NULL, 0.5, 63, 'DR11', 'Bead must be rolled back symmetrically, no voids or irregularities');
