-- WeldTrace: Row Level Security Policies
-- All data access is scoped to company, project membership, and role.

-- ============================================================
-- HELPER FUNCTION: Get current user's company_id
-- ============================================================
CREATE OR REPLACE FUNCTION auth_user_company_id()
RETURNS UUID AS $$
    SELECT company_id FROM users WHERE id = auth.uid()
$$ LANGUAGE SQL SECURITY DEFINER STABLE;

-- ============================================================
-- HELPER FUNCTION: Get current user's role
-- ============================================================
CREATE OR REPLACE FUNCTION auth_user_role()
RETURNS user_role AS $$
    SELECT role FROM users WHERE id = auth.uid()
$$ LANGUAGE SQL SECURITY DEFINER STABLE;

-- ============================================================
-- HELPER FUNCTION: Check if user is assigned to a project
-- ============================================================
CREATE OR REPLACE FUNCTION user_in_project(p_project_id UUID)
RETURNS BOOLEAN AS $$
    SELECT EXISTS (
        SELECT 1 FROM project_users
        WHERE project_id = p_project_id
        AND user_id = auth.uid()
    )
$$ LANGUAGE SQL SECURITY DEFINER STABLE;

-- ============================================================
-- HELPER FUNCTION: Check if weld belongs to user's company
-- ============================================================
CREATE OR REPLACE FUNCTION weld_in_user_company(p_weld_id UUID)
RETURNS BOOLEAN AS $$
    SELECT EXISTS (
        SELECT 1
        FROM welds w
        JOIN projects p ON p.id = w.project_id
        WHERE w.id = p_weld_id
        AND p.company_id = auth_user_company_id()
    )
$$ LANGUAGE SQL SECURITY DEFINER STABLE;

-- ============================================================
-- ENABLE RLS ON ALL TABLES
-- ============================================================
ALTER TABLE companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE projects ENABLE ROW LEVEL SECURITY;
ALTER TABLE project_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE machines ENABLE ROW LEVEL SECURITY;
ALTER TABLE project_machines ENABLE ROW LEVEL SECURITY;
ALTER TABLE welding_standards ENABLE ROW LEVEL SECURITY;
ALTER TABLE welding_parameters ENABLE ROW LEVEL SECURITY;
ALTER TABLE welds ENABLE ROW LEVEL SECURITY;
ALTER TABLE weld_steps ENABLE ROW LEVEL SECURITY;
ALTER TABLE weld_photos ENABLE ROW LEVEL SECURITY;
ALTER TABLE weld_signatures ENABLE ROW LEVEL SECURITY;
ALTER TABLE sensor_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE weld_errors ENABLE ROW LEVEL SECURITY;
ALTER TABLE machine_maintenance ENABLE ROW LEVEL SECURITY;
ALTER TABLE sensor_calibrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE weld_certificates ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- COMPANIES
-- Users can only see their own company.
-- Only managers can update company info.
-- ============================================================
CREATE POLICY companies_select ON companies FOR SELECT
    USING (id = auth_user_company_id());

CREATE POLICY companies_update ON companies FOR UPDATE
    USING (id = auth_user_company_id() AND auth_user_role() IN ('manager'));

-- ============================================================
-- USERS
-- Users see all members of their company.
-- Managers/supervisors can insert new users.
-- Users can update their own profile.
-- ============================================================
CREATE POLICY users_select ON users FOR SELECT
    USING (company_id = auth_user_company_id());

CREATE POLICY users_insert ON users FOR INSERT
    WITH CHECK (
        company_id = auth_user_company_id()
        AND auth_user_role() IN ('manager', 'supervisor')
    );

CREATE POLICY users_update ON users FOR UPDATE
    USING (
        company_id = auth_user_company_id()
        AND (id = auth.uid() OR auth_user_role() IN ('manager', 'supervisor'))
    );

-- ============================================================
-- PROJECTS
-- All roles can view projects in their company.
-- Managers and supervisors can create/update projects.
-- ============================================================
CREATE POLICY projects_select ON projects FOR SELECT
    USING (company_id = auth_user_company_id());

CREATE POLICY projects_insert ON projects FOR INSERT
    WITH CHECK (
        company_id = auth_user_company_id()
        AND auth_user_role() IN ('manager', 'supervisor')
    );

CREATE POLICY projects_update ON projects FOR UPDATE
    USING (
        company_id = auth_user_company_id()
        AND auth_user_role() IN ('manager', 'supervisor')
    );

-- ============================================================
-- PROJECT USERS
-- All roles can see project assignments in their company.
-- Managers/supervisors can assign users.
-- ============================================================
CREATE POLICY project_users_select ON project_users FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM projects p
            WHERE p.id = project_id AND p.company_id = auth_user_company_id()
        )
    );

CREATE POLICY project_users_insert ON project_users FOR INSERT
    WITH CHECK (
        auth_user_role() IN ('manager', 'supervisor')
        AND EXISTS (
            SELECT 1 FROM projects p
            WHERE p.id = project_id AND p.company_id = auth_user_company_id()
        )
    );

CREATE POLICY project_users_delete ON project_users FOR DELETE
    USING (
        auth_user_role() IN ('manager', 'supervisor')
        AND EXISTS (
            SELECT 1 FROM projects p
            WHERE p.id = project_id AND p.company_id = auth_user_company_id()
        )
    );

-- ============================================================
-- MACHINES
-- All roles can view machines in their company.
-- Managers/supervisors can register and approve machines.
-- ============================================================
CREATE POLICY machines_select ON machines FOR SELECT
    USING (company_id = auth_user_company_id());

CREATE POLICY machines_insert ON machines FOR INSERT
    WITH CHECK (
        company_id = auth_user_company_id()
        AND auth_user_role() IN ('manager', 'supervisor')
    );

CREATE POLICY machines_update ON machines FOR UPDATE
    USING (
        company_id = auth_user_company_id()
        AND auth_user_role() IN ('manager', 'supervisor')
    );

-- ============================================================
-- PROJECT MACHINES
-- All roles can view machine assignments in their company.
-- Managers/supervisors can assign machines.
-- ============================================================
CREATE POLICY project_machines_select ON project_machines FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM projects p
            WHERE p.id = project_id AND p.company_id = auth_user_company_id()
        )
    );

CREATE POLICY project_machines_insert ON project_machines FOR INSERT
    WITH CHECK (
        auth_user_role() IN ('manager', 'supervisor')
        AND EXISTS (
            SELECT 1 FROM projects p
            WHERE p.id = project_id AND p.company_id = auth_user_company_id()
        )
    );

-- ============================================================
-- WELDING STANDARDS & PARAMETERS
-- Read-only for all authenticated users (global reference data).
-- ============================================================
CREATE POLICY welding_standards_select ON welding_standards FOR SELECT
    USING (auth.uid() IS NOT NULL);

CREATE POLICY welding_parameters_select ON welding_parameters FOR SELECT
    USING (auth.uid() IS NOT NULL);

-- ============================================================
-- WELDS
-- Welders: can create welds, read welds from assigned projects.
-- Managers/Supervisors: full access to all welds in their company.
-- Auditors: read-only access to completed welds in their company.
-- IMMUTABILITY: completed welds cannot be updated or deleted.
-- ============================================================
CREATE POLICY welds_select ON welds FOR SELECT
    USING (
        -- Managers/supervisors see all company welds
        (auth_user_role() IN ('manager', 'supervisor')
            AND EXISTS (SELECT 1 FROM projects p WHERE p.id = project_id AND p.company_id = auth_user_company_id()))
        OR
        -- Welders see welds from their assigned projects
        (auth_user_role() = 'welder' AND user_in_project(project_id))
        OR
        -- Auditors see completed welds in their company
        (auth_user_role() = 'auditor'
            AND status = 'completed'
            AND EXISTS (SELECT 1 FROM projects p WHERE p.id = project_id AND p.company_id = auth_user_company_id()))
    );

CREATE POLICY welds_insert ON welds FOR INSERT
    WITH CHECK (
        auth_user_role() IN ('manager', 'supervisor', 'welder')
        AND user_in_project(project_id)
        AND EXISTS (SELECT 1 FROM projects p WHERE p.id = project_id AND p.company_id = auth_user_company_id())
    );

-- Immutability: completed/cancelled welds cannot be updated
CREATE POLICY welds_update ON welds FOR UPDATE
    USING (
        status = 'in_progress'
        AND (
            (auth_user_role() = 'welder' AND operator_id = auth.uid())
            OR auth_user_role() IN ('manager', 'supervisor')
        )
        AND EXISTS (SELECT 1 FROM projects p WHERE p.id = project_id AND p.company_id = auth_user_company_id())
    );

-- Only managers can delete in-progress welds (e.g. test/mistake cleanup)
CREATE POLICY welds_delete ON welds FOR DELETE
    USING (
        status = 'in_progress'
        AND auth_user_role() = 'manager'
        AND EXISTS (SELECT 1 FROM projects p WHERE p.id = project_id AND p.company_id = auth_user_company_id())
    );

-- ============================================================
-- WELD STEPS
-- Access follows the parent weld's access rules.
-- ============================================================
CREATE POLICY weld_steps_select ON weld_steps FOR SELECT
    USING (weld_in_user_company(weld_id) AND (
        auth_user_role() IN ('manager', 'supervisor', 'auditor')
        OR (auth_user_role() = 'welder' AND EXISTS (
            SELECT 1 FROM welds w WHERE w.id = weld_id AND user_in_project(w.project_id)
        ))
    ));

CREATE POLICY weld_steps_insert ON weld_steps FOR INSERT
    WITH CHECK (
        weld_in_user_company(weld_id)
        AND EXISTS (
            SELECT 1 FROM welds w WHERE w.id = weld_id AND w.status = 'in_progress'
        )
        AND auth_user_role() IN ('manager', 'supervisor', 'welder')
    );

CREATE POLICY weld_steps_update ON weld_steps FOR UPDATE
    USING (
        weld_in_user_company(weld_id)
        AND EXISTS (
            SELECT 1 FROM welds w WHERE w.id = weld_id AND w.status = 'in_progress'
        )
        AND auth_user_role() IN ('manager', 'supervisor', 'welder')
    );

-- ============================================================
-- WELD PHOTOS
-- Welders can upload. All project members can view.
-- ============================================================
CREATE POLICY weld_photos_select ON weld_photos FOR SELECT
    USING (weld_in_user_company(weld_id));

CREATE POLICY weld_photos_insert ON weld_photos FOR INSERT
    WITH CHECK (
        weld_in_user_company(weld_id)
        AND auth_user_role() IN ('manager', 'supervisor', 'welder')
    );

-- ============================================================
-- WELD SIGNATURES
-- Only managers and supervisors can sign. All can view.
-- ============================================================
CREATE POLICY weld_signatures_select ON weld_signatures FOR SELECT
    USING (weld_in_user_company(weld_id));

CREATE POLICY weld_signatures_insert ON weld_signatures FOR INSERT
    WITH CHECK (
        weld_in_user_company(weld_id)
        AND auth_user_role() IN ('manager', 'supervisor')
    );

-- ============================================================
-- SENSOR LOGS
-- All project members can read.
-- Only welders/supervisors can insert (during active weld).
-- IMMUTABLE: no updates or deletes once inserted.
-- ============================================================
CREATE POLICY sensor_logs_select ON sensor_logs FOR SELECT
    USING (weld_in_user_company(weld_id));

CREATE POLICY sensor_logs_insert ON sensor_logs FOR INSERT
    WITH CHECK (
        weld_in_user_company(weld_id)
        AND auth_user_role() IN ('manager', 'supervisor', 'welder')
        AND EXISTS (
            SELECT 1 FROM welds w WHERE w.id = weld_id AND w.status = 'in_progress'
        )
    );

-- No UPDATE or DELETE policy for sensor_logs — they are immutable by design.

-- ============================================================
-- WELD ERRORS
-- Readable by all company members. Inserted by system only.
-- ============================================================
CREATE POLICY weld_errors_select ON weld_errors FOR SELECT
    USING (weld_in_user_company(weld_id));

CREATE POLICY weld_errors_insert ON weld_errors FOR INSERT
    WITH CHECK (
        weld_in_user_company(weld_id)
        AND auth_user_role() IN ('manager', 'supervisor', 'welder')
    );

-- ============================================================
-- MACHINE MAINTENANCE
-- All company members can read. Managers/supervisors can insert.
-- ============================================================
CREATE POLICY machine_maintenance_select ON machine_maintenance FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM machines m
            WHERE m.id = machine_id AND m.company_id = auth_user_company_id()
        )
    );

CREATE POLICY machine_maintenance_insert ON machine_maintenance FOR INSERT
    WITH CHECK (
        auth_user_role() IN ('manager', 'supervisor')
        AND EXISTS (
            SELECT 1 FROM machines m
            WHERE m.id = machine_id AND m.company_id = auth_user_company_id()
        )
    );

-- ============================================================
-- SENSOR CALIBRATIONS
-- All company members can read calibration history.
-- Managers/supervisors can record new calibrations.
-- ============================================================
CREATE POLICY sensor_calibrations_select ON sensor_calibrations FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM machines m
            WHERE m.id = machine_id AND m.company_id = auth_user_company_id()
        )
    );

CREATE POLICY sensor_calibrations_insert ON sensor_calibrations FOR INSERT
    WITH CHECK (
        auth_user_role() IN ('manager', 'supervisor')
        AND EXISTS (
            SELECT 1 FROM machines m
            WHERE m.id = machine_id AND m.company_id = auth_user_company_id()
        )
    );

-- ============================================================
-- WELD CERTIFICATES (future)
-- Readable by all. Only managers can issue.
-- ============================================================
CREATE POLICY weld_certificates_select ON weld_certificates FOR SELECT
    USING (weld_in_user_company(weld_id));

CREATE POLICY weld_certificates_insert ON weld_certificates FOR INSERT
    WITH CHECK (
        auth_user_role() = 'manager'
        AND weld_in_user_company(weld_id)
    );

CREATE POLICY weld_certificates_update ON weld_certificates FOR UPDATE
    USING (
        auth_user_role() = 'manager'
        AND weld_in_user_company(weld_id)
    );
