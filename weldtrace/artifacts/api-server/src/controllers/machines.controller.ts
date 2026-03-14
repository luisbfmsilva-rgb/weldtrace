import { Response } from "express";
import { sendError, NotFoundError, ApiError } from "../lib/errors.js";
import {
  CreateMachineBody,
  UpdateMachineBody,
  CreateMaintenanceBody,
  CreateCalibrationBody,
} from "../lib/validation.js";
import type { AuthenticatedRequest } from "../middlewares/auth.js";

export async function listMachines(req: AuthenticatedRequest, res: Response): Promise<void> {
  try {
    const { isApproved, type } = req.query as Record<string, string>;

    let q = req.supabaseClient!
      .from("machines")
      .select(`
        id, serial_number, model, manufacturer, type, is_approved, is_active,
        manufacture_year, last_calibration_date, next_calibration_date, created_at, updated_at,
        approved_by_user:users!machines_approved_by_fkey(id, first_name, last_name)
      `)
      .order("created_at", { ascending: false });

    if (isApproved !== undefined) q = q.eq("is_approved", isApproved === "true");
    if (type) q = q.eq("type", type);

    const { data, error } = await q;
    if (error) throw new ApiError(500, error.message, "DB_ERROR");

    res.json(data ?? []);
  } catch (err) {
    sendError(res, err);
  }
}

export async function getMachine(req: AuthenticatedRequest, res: Response): Promise<void> {
  try {
    const { id } = req.params;
    const { data, error } = await req.supabaseClient!
      .from("machines")
      .select(`
        *,
        approved_by_user:users!machines_approved_by_fkey(id, first_name, last_name),
        machine_maintenance(
          id, maintenance_type, performed_at, next_due_date, notes, attachments_path, created_at,
          performed_by_user:users!machine_maintenance_performed_by_fkey(id, first_name, last_name)
        ),
        sensor_calibrations(
          id, sensor_serial, calibration_date, reference_device, reference_certificate,
          offset_value, slope_value, notes,
          calibrated_by_user:users!sensor_calibrations_calibrated_by_fkey(id, first_name, last_name)
        )
      `)
      .eq("id", id)
      .single();

    if (error || !data) throw new NotFoundError("Machine");
    res.json(data);
  } catch (err) {
    sendError(res, err);
  }
}

export async function createMachine(req: AuthenticatedRequest, res: Response): Promise<void> {
  try {
    const body = CreateMachineBody.parse(req.body);

    const { data, error } = await req.supabaseClient!
      .from("machines")
      .insert({
        serial_number: body.serialNumber,
        model: body.model,
        manufacturer: body.manufacturer,
        type: body.type,
        manufacture_year: body.manufactureYear ?? null,
        notes: body.notes ?? null,
        company_id: req.user!.companyId,
      })
      .select()
      .single();

    if (error) {
      if ((error as unknown as { code: string }).code === "23505") {
        throw new ApiError(409, "A machine with this serial number already exists", "CONFLICT");
      }
      throw new ApiError(500, error.message, "DB_ERROR");
    }

    res.status(201).json(data);
  } catch (err) {
    sendError(res, err);
  }
}

export async function updateMachine(req: AuthenticatedRequest, res: Response): Promise<void> {
  try {
    const { id } = req.params;
    const body = UpdateMachineBody.parse(req.body);

    const patch: Record<string, unknown> = {};
    if (body.model !== undefined) patch["model"] = body.model;
    if (body.manufacturer !== undefined) patch["manufacturer"] = body.manufacturer;
    if (body.notes !== undefined) patch["notes"] = body.notes;
    if (body.isActive !== undefined) patch["is_active"] = body.isActive;
    if (body.lastCalibrationDate !== undefined) patch["last_calibration_date"] = body.lastCalibrationDate;
    if (body.nextCalibrationDate !== undefined) patch["next_calibration_date"] = body.nextCalibrationDate;

    if (Object.keys(patch).length === 0) {
      throw new ApiError(400, "No fields to update", "VALIDATION_ERROR");
    }

    const { data, error } = await req.supabaseClient!
      .from("machines")
      .update(patch)
      .eq("id", id)
      .select()
      .single();

    if (error || !data) throw new NotFoundError("Machine");
    res.json(data);
  } catch (err) {
    sendError(res, err);
  }
}

export async function approveMachine(req: AuthenticatedRequest, res: Response): Promise<void> {
  try {
    const { id } = req.params;

    const { data: existing } = await req.supabaseClient!
      .from("machines")
      .select("id, is_approved")
      .eq("id", id)
      .single();

    if (!existing) throw new NotFoundError("Machine");
    if (existing.is_approved) {
      throw new ApiError(409, "Machine is already approved", "ALREADY_APPROVED");
    }

    const { data, error } = await req.supabaseClient!
      .from("machines")
      .update({
        is_approved: true,
        approved_by: req.user!.id,
        approved_at: new Date().toISOString(),
      })
      .eq("id", id)
      .select()
      .single();

    if (error || !data) throw new ApiError(500, "Approval failed", "DB_ERROR");
    res.json(data);
  } catch (err) {
    sendError(res, err);
  }
}

export async function createMaintenance(req: AuthenticatedRequest, res: Response): Promise<void> {
  try {
    const { id } = req.params;
    const body = CreateMaintenanceBody.parse(req.body);

    const { data: machine } = await req.supabaseClient!
      .from("machines")
      .select("id")
      .eq("id", id)
      .single();

    if (!machine) throw new NotFoundError("Machine");

    const { data, error } = await req.supabaseClient!
      .from("machine_maintenance")
      .insert({
        machine_id: id,
        maintenance_type: body.maintenanceType,
        performed_by: req.user!.id,
        performed_at: body.performedAt,
        next_due_date: body.nextDueDate ?? null,
        notes: body.notes ?? null,
        attachments_path: body.attachmentsPath ?? null,
      })
      .select(`
        *,
        performed_by_user:users!machine_maintenance_performed_by_fkey(id, first_name, last_name)
      `)
      .single();

    if (error) throw new ApiError(500, error.message, "DB_ERROR");
    res.status(201).json(data);
  } catch (err) {
    sendError(res, err);
  }
}

export async function createCalibration(req: AuthenticatedRequest, res: Response): Promise<void> {
  try {
    const { id } = req.params;
    const body = CreateCalibrationBody.parse(req.body);

    const { data: machine } = await req.supabaseClient!
      .from("machines")
      .select("id")
      .eq("id", id)
      .single();

    if (!machine) throw new NotFoundError("Machine");

    const { data, error } = await req.supabaseClient!
      .from("sensor_calibrations")
      .insert({
        machine_id: id,
        sensor_serial: body.sensorSerial,
        calibration_date: body.calibrationDate,
        calibrated_by: req.user!.id,
        reference_device: body.referenceDevice,
        reference_certificate: body.referenceCertificate,
        offset_value: body.offsetValue,
        slope_value: body.slopeValue,
        notes: body.notes ?? null,
      })
      .select(`
        *,
        calibrated_by_user:users!sensor_calibrations_calibrated_by_fkey(id, first_name, last_name)
      `)
      .single();

    if (error) throw new ApiError(500, error.message, "DB_ERROR");
    res.status(201).json(data);
  } catch (err) {
    sendError(res, err);
  }
}

export async function listCalibrations(req: AuthenticatedRequest, res: Response): Promise<void> {
  try {
    const { id } = req.params;

    const { data, error } = await req.supabaseClient!
      .from("sensor_calibrations")
      .select(`
        id, sensor_serial, calibration_date, reference_device, reference_certificate,
        offset_value, slope_value, notes, created_at,
        calibrated_by_user:users!sensor_calibrations_calibrated_by_fkey(id, first_name, last_name)
      `)
      .eq("machine_id", id)
      .order("calibration_date", { ascending: false });

    if (error) throw new ApiError(500, error.message, "DB_ERROR");
    res.json(data ?? []);
  } catch (err) {
    sendError(res, err);
  }
}
