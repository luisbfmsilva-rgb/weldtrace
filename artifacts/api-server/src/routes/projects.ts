import { Router, type IRouter } from "express";
import { requireAuth, requireRole, type AuthenticatedRequest } from "../middlewares/auth.js";

const router: IRouter = Router();

router.use(requireAuth);

router.get("/projects", async (req: AuthenticatedRequest, res): Promise<void> => {
  const { data, error } = await req.supabaseClient!
    .from("projects")
    .select(`
      *,
      company:companies(id, name),
      created_by_user:users!projects_created_by_fkey(id, first_name, last_name)
    `)
    .order("created_at", { ascending: false });

  if (error) {
    res.status(500).json({ error: error.message });
    return;
  }

  res.json(data);
});

router.get("/projects/:id", async (req: AuthenticatedRequest, res): Promise<void> => {
  const { id } = req.params;

  const { data, error } = await req.supabaseClient!
    .from("projects")
    .select(`
      *,
      company:companies(id, name),
      project_users(
        id, role_in_project, assigned_at,
        user:users(id, first_name, last_name, role, email)
      ),
      project_machines(
        id, assigned_at,
        machine:machines(id, serial_number, model, manufacturer, type, is_approved)
      )
    `)
    .eq("id", id)
    .single();

  if (error || !data) {
    res.status(404).json({ error: "Project not found" });
    return;
  }

  res.json(data);
});

router.post("/projects", requireRole("manager", "supervisor"), async (req: AuthenticatedRequest, res): Promise<void> => {
  const { name, description, location, gpsLat, gpsLng, startDate, endDate, clientName, contractNumber } = req.body;

  if (!name) {
    res.status(400).json({ error: "name is required" });
    return;
  }

  const { data, error } = await req.supabaseClient!
    .from("projects")
    .insert({
      name,
      description,
      location,
      gps_lat: gpsLat,
      gps_lng: gpsLng,
      start_date: startDate,
      end_date: endDate,
      client_name: clientName,
      contract_number: contractNumber,
      company_id: req.user!.companyId,
      created_by: req.user!.id,
    })
    .select()
    .single();

  if (error) {
    res.status(500).json({ error: error.message });
    return;
  }

  res.status(201).json(data);
});

router.patch("/projects/:id", requireRole("manager", "supervisor"), async (req: AuthenticatedRequest, res): Promise<void> => {
  const { id } = req.params;
  const { name, description, location, status, startDate, endDate, clientName, contractNumber } = req.body;

  const { data, error } = await req.supabaseClient!
    .from("projects")
    .update({
      ...(name !== undefined && { name }),
      ...(description !== undefined && { description }),
      ...(location !== undefined && { location }),
      ...(status !== undefined && { status }),
      ...(startDate !== undefined && { start_date: startDate }),
      ...(endDate !== undefined && { end_date: endDate }),
      ...(clientName !== undefined && { client_name: clientName }),
      ...(contractNumber !== undefined && { contract_number: contractNumber }),
    })
    .eq("id", id)
    .select()
    .single();

  if (error || !data) {
    res.status(404).json({ error: "Project not found or update failed" });
    return;
  }

  res.json(data);
});

router.post("/projects/:id/users", requireRole("manager", "supervisor"), async (req: AuthenticatedRequest, res): Promise<void> => {
  const { id } = req.params;
  const { userId, roleInProject } = req.body;

  if (!userId || !roleInProject) {
    res.status(400).json({ error: "userId and roleInProject are required" });
    return;
  }

  const { data, error } = await req.supabaseClient!
    .from("project_users")
    .insert({
      project_id: id,
      user_id: userId,
      role_in_project: roleInProject,
      assigned_by: req.user!.id,
    })
    .select()
    .single();

  if (error) {
    res.status(500).json({ error: error.message });
    return;
  }

  res.status(201).json(data);
});

router.delete("/projects/:id/users/:userId", requireRole("manager", "supervisor"), async (req: AuthenticatedRequest, res): Promise<void> => {
  const { id, userId } = req.params;

  const { error } = await req.supabaseClient!
    .from("project_users")
    .delete()
    .eq("project_id", id)
    .eq("user_id", userId);

  if (error) {
    res.status(500).json({ error: error.message });
    return;
  }

  res.sendStatus(204);
});

router.post("/projects/:id/machines", requireRole("manager", "supervisor"), async (req: AuthenticatedRequest, res): Promise<void> => {
  const { id } = req.params;
  const { machineId } = req.body;

  if (!machineId) {
    res.status(400).json({ error: "machineId is required" });
    return;
  }

  const { data, error } = await req.supabaseClient!
    .from("project_machines")
    .insert({
      project_id: id,
      machine_id: machineId,
      assigned_by: req.user!.id,
    })
    .select()
    .single();

  if (error) {
    res.status(500).json({ error: error.message });
    return;
  }

  res.status(201).json(data);
});

export default router;
