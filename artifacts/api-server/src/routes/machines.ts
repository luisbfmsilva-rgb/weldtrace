import { Router, type IRouter } from "express";
import { requireAuth, requireRole, type AuthenticatedRequest } from "../middlewares/auth.js";

const router: IRouter = Router();

router.use(requireAuth);

router.get("/machines", async (req: AuthenticatedRequest, res): Promise<void> => {
  const { data, error } = await req.supabaseClient!
    .from("machines")
    .select("*, approved_by_user:users!machines_approved_by_fkey(id, first_name, last_name)")
    .order("created_at", { ascending: false });

  if (error) {
    res.status(500).json({ error: error.message });
    return;
  }

  res.json(data);
});

router.get("/machines/:id", async (req: AuthenticatedRequest, res): Promise<void> => {
  const { id } = req.params;

  const { data, error } = await req.supabaseClient!
    .from("machines")
    .select(`
      *,
      approved_by_user:users!machines_approved_by_fkey(id, first_name, last_name),
      machine_maintenance(id, maintenance_type, performed_at, next_due_date, notes),
      sensor_calibrations(id, sensor_serial, calibration_date, reference_device, offset_value, slope_value)
    `)
    .eq("id", id)
    .single();

  if (error || !data) {
    res.status(404).json({ error: "Machine not found" });
    return;
  }

  res.json(data);
});

router.post("/machines", requireRole("manager", "supervisor"), async (req: AuthenticatedRequest, res): Promise<void> => {
  const { serialNumber, model, manufacturer, type, manufactureYear, notes } = req.body;

  if (!serialNumber || !model || !manufacturer || !type) {
    res.status(400).json({ error: "serialNumber, model, manufacturer, and type are required" });
    return;
  }

  const { data, error } = await req.supabaseClient!
    .from("machines")
    .insert({
      serial_number: serialNumber,
      model,
      manufacturer,
      type,
      manufacture_year: manufactureYear,
      notes,
      company_id: req.user!.companyId,
    })
    .select()
    .single();

  if (error) {
    res.status(500).json({ error: error.message });
    return;
  }

  res.status(201).json(data);
});

router.patch("/machines/:id/approve", requireRole("manager", "supervisor"), async (req: AuthenticatedRequest, res): Promise<void> => {
  const { id } = req.params;

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

  if (error || !data) {
    res.status(404).json({ error: "Machine not found or approval failed" });
    return;
  }

  res.json(data);
});

router.patch("/machines/:id", requireRole("manager", "supervisor"), async (req: AuthenticatedRequest, res): Promise<void> => {
  const { id } = req.params;
  const { model, manufacturer, notes, isActive, lastCalibrationDate, nextCalibrationDate } = req.body;

  const { data, error } = await req.supabaseClient!
    .from("machines")
    .update({
      ...(model !== undefined && { model }),
      ...(manufacturer !== undefined && { manufacturer }),
      ...(notes !== undefined && { notes }),
      ...(isActive !== undefined && { is_active: isActive }),
      ...(lastCalibrationDate !== undefined && { last_calibration_date: lastCalibrationDate }),
      ...(nextCalibrationDate !== undefined && { next_calibration_date: nextCalibrationDate }),
    })
    .eq("id", id)
    .select()
    .single();

  if (error || !data) {
    res.status(404).json({ error: "Machine not found or update failed" });
    return;
  }

  res.json(data);
});

router.post("/machines/:id/maintenance", requireRole("manager", "supervisor"), async (req: AuthenticatedRequest, res): Promise<void> => {
  const { id } = req.params;
  const { maintenanceType, performedAt, nextDueDate, notes, attachmentsPath } = req.body;

  if (!maintenanceType || !performedAt) {
    res.status(400).json({ error: "maintenanceType and performedAt are required" });
    return;
  }

  const { data, error } = await req.supabaseClient!
    .from("machine_maintenance")
    .insert({
      machine_id: id,
      maintenance_type: maintenanceType,
      performed_by: req.user!.id,
      performed_at: performedAt,
      next_due_date: nextDueDate,
      notes,
      attachments_path: attachmentsPath,
    })
    .select()
    .single();

  if (error) {
    res.status(500).json({ error: error.message });
    return;
  }

  res.status(201).json(data);
});

router.post("/machines/:id/calibrations", requireRole("manager", "supervisor"), async (req: AuthenticatedRequest, res): Promise<void> => {
  const { id } = req.params;
  const { sensorSerial, calibrationDate, referenceDevice, referenceCertificate, offsetValue, slopeValue, notes } = req.body;

  if (!sensorSerial || !calibrationDate || !referenceDevice || !referenceCertificate) {
    res.status(400).json({ error: "sensorSerial, calibrationDate, referenceDevice, and referenceCertificate are required" });
    return;
  }

  const { data, error } = await req.supabaseClient!
    .from("sensor_calibrations")
    .insert({
      machine_id: id,
      sensor_serial: sensorSerial,
      calibration_date: calibrationDate,
      calibrated_by: req.user!.id,
      reference_device: referenceDevice,
      reference_certificate: referenceCertificate,
      offset_value: offsetValue ?? 0,
      slope_value: slopeValue ?? 1,
      notes,
    })
    .select()
    .single();

  if (error) {
    res.status(500).json({ error: error.message });
    return;
  }

  res.status(201).json(data);
});

router.get("/machines/:id/calibrations", async (req: AuthenticatedRequest, res): Promise<void> => {
  const { id } = req.params;

  const { data, error } = await req.supabaseClient!
    .from("sensor_calibrations")
    .select("*, calibrated_by_user:users!sensor_calibrations_calibrated_by_fkey(id, first_name, last_name)")
    .eq("machine_id", id)
    .order("calibration_date", { ascending: false });

  if (error) {
    res.status(500).json({ error: error.message });
    return;
  }

  res.json(data);
});

export default router;
