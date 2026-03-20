import { Response } from "express";
import { sendError, ApiError } from "../lib/errors.js";
import { SyncUploadBody, SyncUpdatesQuery } from "../lib/validation.js";
import type { AuthenticatedRequest } from "../middlewares/auth.js";
import type { EntitySyncResult } from "../types/index.js";

// ── Upload pending local records to cloud ─────────────────────────────────────
// Called by the Flutter Sync Service when connectivity is restored.
// Upload order matters — welds must exist before steps/errors/sensor_logs.
// Uses upsert to safely replay retried uploads (idempotent by id).

export async function upload(req: AuthenticatedRequest, res: Response): Promise<void> {
  try {
    const body = SyncUploadBody.parse(req.body);

    const results: Record<string, EntitySyncResult> = {
      machines:  { inserted: 0, errors: [] },
      projects:  { inserted: 0, errors: [] },
      welds:     { inserted: 0, errors: [] },
      weldSteps: { inserted: 0, errors: [] },
      weldErrors: { inserted: 0, errors: [] },
      weldPhotos: { inserted: 0, errors: [] },
      sensorLogs: { inserted: 0, errors: [] },
    };

    // 0a. Machines (must exist before welds that reference them)
    if (body.machines.length > 0) {
      const records = body.machines.map((m) => ({
        id:                         m.id,
        company_id:                 req.user!.companyId,
        serial_number:              m.serialNumber,
        model:                      m.model,
        manufacturer:               m.manufacturer,
        type:                       m.type,
        manufacture_year:           m.manufactureYear ?? null,
        hydraulic_cylinder_area_mm2: m.hydraulicCylinderAreaMm2 ?? null,
        is_approved:                m.isApproved,
        is_active:                  m.isActive,
        last_calibration_date:      m.lastCalibrationDate ?? null,
        next_calibration_date:      m.nextCalibrationDate ?? null,
        notes:                      m.notes ?? null,
        updated_at:                 m.updatedAt ?? new Date().toISOString(),
      }));

      const { data, error } = await req.supabaseClient!
        .from("machines")
        .upsert(records, { onConflict: "id", ignoreDuplicates: false })
        .select("id");

      results.machines.inserted = data?.length ?? 0;
      if (error) results.machines.errors.push(error.message);
    }

    // 0b. Projects (must exist before welds that reference them)
    if (body.projects.length > 0) {
      const records = body.projects.map((p) => ({
        id:              p.id,
        company_id:      req.user!.companyId,
        created_by:      req.user!.id,
        name:            p.name,
        description:     p.description ?? null,
        location:        p.location ?? null,
        status:          p.status,
        gps_lat:         p.gpsLat ?? null,
        gps_lng:         p.gpsLng ?? null,
        start_date:      p.startDate ?? null,
        end_date:        p.endDate ?? null,
        client_name:     p.clientName ?? null,
        contract_number: p.contractNumber ?? null,
        updated_at:      p.updatedAt ?? new Date().toISOString(),
      }));

      const { data, error } = await req.supabaseClient!
        .from("projects")
        .upsert(records, { onConflict: "id", ignoreDuplicates: false })
        .select("id");

      results.projects.inserted = data?.length ?? 0;
      if (error) results.projects.errors.push(error.message);
    }

    // 1. Welds (must be first among weld entities — all weld sub-entities reference weld.id)
    if (body.welds.length > 0) {
      const records = body.welds.map((w) => ({
        id: w.id,
        project_id: w.projectId,
        machine_id: w.machineId,
        operator_id: req.user!.id,
        weld_type: w.weldType,
        status: w.status,
        pipe_material: w.pipeMaterial,
        pipe_diameter: w.pipeDiameter,
        pipe_sdr: w.pipeSdr ?? null,
        pipe_wall_thickness: w.pipeWallThickness ?? null,
        ambient_temperature: w.ambientTemperature ?? null,
        gps_lat: w.gpsLat ?? null,
        gps_lng: w.gpsLng ?? null,
        standard_used: w.standardUsed ?? null,
        standard_id: w.standardId ?? null,
        is_cancelled: w.isCancelled,
        cancel_reason: w.cancelReason ?? null,
        cancel_timestamp: w.cancelTimestamp ?? null,
        notes: w.notes ?? null,
        started_at: w.startedAt,
        completed_at: w.completedAt ?? null,
      }));

      const { data, error } = await req.supabaseClient!
        .from("welds")
        .upsert(records, { onConflict: "id", ignoreDuplicates: false })
        .select("id");

      results.welds.inserted = data?.length ?? 0;
      if (error) results.welds.errors.push(error.message);
    }

    // 2. Weld steps
    if (body.weldSteps.length > 0) {
      const records = body.weldSteps.map((s) => ({
        id: s.id,
        weld_id: s.weldId,
        phase_name: s.phaseName,
        phase_order: s.phaseOrder,
        started_at: s.startedAt ?? null,
        completed_at: s.completedAt ?? null,
        nominal_value: s.nominalValue ?? null,
        actual_value: s.actualValue ?? null,
        unit: s.unit ?? null,
        validation_passed: s.validationPassed ?? null,
        notes: s.notes ?? null,
      }));

      const { data, error } = await req.supabaseClient!
        .from("weld_steps")
        .upsert(records, { onConflict: "id", ignoreDuplicates: false })
        .select("id");

      results.weldSteps.inserted = data?.length ?? 0;
      if (error) results.weldSteps.errors.push(error.message);
    }

    // 3. Weld errors
    if (body.weldErrors.length > 0) {
      const records = body.weldErrors.map((e) => ({
        id: e.id,
        weld_id: e.weldId,
        error_type: e.errorType,
        error_message: e.errorMessage,
        phase_name: e.phaseName ?? null,
        parameter_name: e.parameterName ?? null,
        actual_value: e.actualValue ?? null,
        allowed_min: e.allowedMin ?? null,
        allowed_max: e.allowedMax ?? null,
        recorded_at: e.recordedAt,
      }));

      const { data, error } = await req.supabaseClient!
        .from("weld_errors")
        .upsert(records, { onConflict: "id", ignoreDuplicates: false })
        .select("id");

      results.weldErrors.inserted = data?.length ?? 0;
      if (error) results.weldErrors.errors.push(error.message);
    }

    // 4. Weld photos (metadata only — actual files go to Supabase Storage directly)
    if (body.weldPhotos.length > 0) {
      const records = body.weldPhotos.map((p) => ({
        id: p.id,
        weld_id: p.weldId,
        storage_path: p.storagePath,
        photo_type: p.photoType,
        caption: p.caption ?? null,
        taken_at: p.takenAt,
        uploaded_by: req.user!.id,
      }));

      const { data, error } = await req.supabaseClient!
        .from("weld_photos")
        .upsert(records, { onConflict: "id", ignoreDuplicates: true })
        .select("id");

      results.weldPhotos.inserted = data?.length ?? 0;
      if (error) results.weldPhotos.errors.push(error.message);
    }

    // 5. Sensor log batches — insert only (no upsert, sensor_logs have no UPDATE policy)
    for (const batch of body.sensorLogBatches) {
      if (batch.logs.length > 200) {
        results.sensorLogs.errors.push(
          `Batch for weld ${batch.weldId} exceeds 200 records. Split into smaller batches.`,
        );
        continue;
      }

      const records = batch.logs.map((l) => ({
        weld_id: batch.weldId,
        weld_step_id: l.weldStepId ?? null,
        recorded_at: l.recordedAt,
        pressure_bar: l.pressureBar ?? null,
        temperature_celsius: l.temperatureCelsius ?? null,
        phase_name: l.phaseName ?? null,
      }));

      const { data, error } = await req.supabaseClient!
        .from("sensor_logs")
        .insert(records)
        .select("id");

      results.sensorLogs.inserted += data?.length ?? 0;
      if (error) {
        // Duplicate inserts are expected on retry — ignore duplicate errors
        if (!(error as unknown as { code: string }).code?.startsWith("23")) {
          results.sensorLogs.errors.push(`Batch weld=${batch.weldId}: ${error.message}`);
        }
      }
    }

    const hasErrors = Object.values(results).some((r) => r.errors.length > 0);

    res.status(hasErrors ? 207 : 200).json({
      results,
      syncedAt: new Date().toISOString(),
    });
  } catch (err) {
    sendError(res, err);
  }
}

// ── Download updates since last sync ──────────────────────────────────────────
// The mobile Sync Service calls this after uploading to receive any server-side
// changes: updated projects, machine approvals, new calibrations, updated standards.
// Scope can be limited to a single project for targeted syncs.

export async function getUpdates(req: AuthenticatedRequest, res: Response): Promise<void> {
  try {
    const query = SyncUpdatesQuery.parse(req.query);

    const sinceDate = new Date(query.since);
    if (isNaN(sinceDate.getTime())) {
      throw new ApiError(400, "Invalid 'since' timestamp — must be a valid ISO 8601 datetime", "VALIDATION_ERROR");
    }

    const client = req.supabaseClient!;

    // Build project and project_users queries with optional project scope
    let projectsQuery = client
      .from("projects")
      .select("id, company_id, name, description, location, status, gps_lat, gps_lng, start_date, end_date, client_name, contract_number, updated_at")
      .gt("updated_at", query.since);

    let projectUsersQuery = client
      .from("project_users")
      .select("id, project_id, user_id, role_in_project, assigned_at");

    let calibrationsQuery = client
      .from("sensor_calibrations")
      .select("id, machine_id, sensor_serial, calibration_date, offset_value, slope_value, reference_device")
      .gt("created_at", query.since);

    if (query.projectId) {
      projectsQuery = projectsQuery.eq("id", query.projectId);
      projectUsersQuery = projectUsersQuery.eq("project_id", query.projectId);
    }

    // Execute all queries in parallel
    const [
      projectsResult,
      projectUsersResult,
      machinesResult,
      calibrationsResult,
      standardsResult,
      parametersResult,
    ] = await Promise.all([
      projectsQuery,
      projectUsersQuery,
      client
        .from("machines")
        .select("id, company_id, serial_number, model, manufacturer, type, is_approved, is_active, hydraulic_cylinder_area_mm2, last_calibration_date, next_calibration_date, notes, updated_at")
        .gt("updated_at", query.since),
      calibrationsQuery,
      client
        .from("welding_standards")
        .select("id, standard_code, weld_type, pipe_material, version, is_active")
        .eq("is_active", true),
      client
        .from("welding_parameters")
        .select("id, standard_id, phase_name, phase_order, parameter_name, unit, nominal_value, min_value, max_value, pipe_diameter_min, pipe_diameter_max, pipe_sdr"),
    ]);

    // Collect any query errors
    const queryErrors: string[] = [];
    if (projectsResult.error) queryErrors.push(`projects: ${projectsResult.error.message}`);
    if (projectUsersResult.error) queryErrors.push(`project_users: ${projectUsersResult.error.message}`);
    if (machinesResult.error) queryErrors.push(`machines: ${machinesResult.error.message}`);
    if (calibrationsResult.error) queryErrors.push(`sensor_calibrations: ${calibrationsResult.error.message}`);
    if (standardsResult.error) queryErrors.push(`welding_standards: ${standardsResult.error.message}`);
    if (parametersResult.error) queryErrors.push(`welding_parameters: ${parametersResult.error.message}`);

    res.json({
      projects: projectsResult.data ?? [],
      projectUsers: projectUsersResult.data ?? [],
      machines: machinesResult.data ?? [],
      sensorCalibrations: calibrationsResult.data ?? [],
      weldingStandards: standardsResult.data ?? [],
      weldingParameters: parametersResult.data ?? [],
      downloadedAt: new Date().toISOString(),
      ...(queryErrors.length > 0 && { warnings: queryErrors }),
    });
  } catch (err) {
    sendError(res, err);
  }
}
