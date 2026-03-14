-- WeldTrace: Initial Schema Migration
-- All tables use UUID primary keys
-- Immutability enforced via RLS and application logic

-- ============================================================
-- EXTENSIONS
-- ============================================================
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- ENUMS
-- ============================================================
CREATE TYPE user_role AS ENUM ('manager', 'supervisor', 'welder', 'auditor');
CREATE TYPE weld_type AS ENUM ('electrofusion', 'butt_fusion');
CREATE TYPE weld_status AS ENUM ('in_progress', 'completed', 'cancelled', 'failed');
CREATE TYPE sync_status AS ENUM ('pending', 'synced', 'conflict');
CREATE TYPE project_status AS ENUM ('active', 'completed', 'suspended');
CREATE TYPE machine_type AS ENUM ('electrofusion', 'butt_fusion', 'universal');
CREATE TYPE photo_type AS ENUM ('pipe_before', 'pipe_after', 'fitting', 'weld_complete', 'defect', 'general');
CREATE TYPE certificate_status AS ENUM ('draft', 'issued', 'revoked');
CREATE TYPE maintenance_type AS ENUM ('calibration', 'repair', 'inspection', 'service');
CREATE TYPE standard_code AS ENUM ('DVS_2207', 'ISO_21307', 'ASTM_F2620');

-- ============================================================
-- COMPANIES
-- ============================================================
CREATE TABLE companies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    country TEXT NOT NULL,
    industry TEXT,
    tax_id TEXT,
    contact_email TEXT,
    contact_phone TEXT,
    address TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- USERS (linked to auth.users)
-- ============================================================
CREATE TABLE users (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
    role user_role NOT NULL,
    first_name TEXT NOT NULL,
    last_name TEXT NOT NULL,
    email TEXT NOT NULL,
    welder_certification_number TEXT,
    certification_expiry DATE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_users_company_id ON users(company_id);
CREATE INDEX idx_users_role ON users(role);

-- ============================================================
-- PROJECTS
-- ============================================================
CREATE TABLE projects (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
    name TEXT NOT NULL,
    description TEXT,
    location TEXT,
    gps_lat NUMERIC(10, 7),
    gps_lng NUMERIC(10, 7),
    status project_status NOT NULL DEFAULT 'active',
    start_date DATE,
    end_date DATE,
    client_name TEXT,
    contract_number TEXT,
    created_by UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_projects_company_id ON projects(company_id);
CREATE INDEX idx_projects_status ON projects(status);

-- ============================================================
-- PROJECT USERS (many-to-many)
-- ============================================================
CREATE TABLE project_users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role_in_project user_role NOT NULL,
    assigned_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    assigned_by UUID REFERENCES users(id) ON DELETE SET NULL,
    UNIQUE(project_id, user_id)
);

CREATE INDEX idx_project_users_project_id ON project_users(project_id);
CREATE INDEX idx_project_users_user_id ON project_users(user_id);

-- ============================================================
-- MACHINES
-- ============================================================
CREATE TABLE machines (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
    serial_number TEXT NOT NULL,
    model TEXT NOT NULL,
    manufacturer TEXT NOT NULL,
    type machine_type NOT NULL,
    manufacture_year INT,
    last_calibration_date DATE,
    next_calibration_date DATE,
    is_approved BOOLEAN NOT NULL DEFAULT FALSE,
    approved_by UUID REFERENCES users(id) ON DELETE SET NULL,
    approved_at TIMESTAMPTZ,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(company_id, serial_number)
);

CREATE INDEX idx_machines_company_id ON machines(company_id);
CREATE INDEX idx_machines_is_approved ON machines(is_approved);

-- ============================================================
-- PROJECT MACHINES (many-to-many)
-- ============================================================
CREATE TABLE project_machines (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    machine_id UUID NOT NULL REFERENCES machines(id) ON DELETE CASCADE,
    assigned_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    assigned_by UUID REFERENCES users(id) ON DELETE SET NULL,
    UNIQUE(project_id, machine_id)
);

CREATE INDEX idx_project_machines_project_id ON project_machines(project_id);
CREATE INDEX idx_project_machines_machine_id ON project_machines(machine_id);

-- ============================================================
-- WELDING STANDARDS
-- ============================================================
CREATE TABLE welding_standards (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    standard_code standard_code NOT NULL,
    weld_type weld_type NOT NULL,
    pipe_material TEXT NOT NULL,
    version TEXT NOT NULL,
    description TEXT,
    valid_from DATE NOT NULL,
    valid_until DATE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_welding_standards_code ON welding_standards(standard_code);
CREATE INDEX idx_welding_standards_weld_type ON welding_standards(weld_type);

-- ============================================================
-- WELDING PARAMETERS (per standard, phase, and pipe spec)
-- ============================================================
CREATE TABLE welding_parameters (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    standard_id UUID NOT NULL REFERENCES welding_standards(id) ON DELETE CASCADE,
    phase_name TEXT NOT NULL,
    phase_order INT NOT NULL,
    parameter_name TEXT NOT NULL,
    unit TEXT NOT NULL,
    nominal_value NUMERIC,
    min_value NUMERIC,
    max_value NUMERIC,
    pipe_diameter_min NUMERIC,
    pipe_diameter_max NUMERIC,
    pipe_sdr TEXT,
    tolerance_pct NUMERIC,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_welding_parameters_standard_id ON welding_parameters(standard_id);
CREATE INDEX idx_welding_parameters_phase ON welding_parameters(phase_name);

-- ============================================================
-- WELDS (immutable after status = 'completed')
-- ============================================================
CREATE TABLE welds (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE RESTRICT,
    machine_id UUID NOT NULL REFERENCES machines(id) ON DELETE RESTRICT,
    operator_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    standard_id UUID REFERENCES welding_standards(id) ON DELETE SET NULL,
    weld_type weld_type NOT NULL,
    status weld_status NOT NULL DEFAULT 'in_progress',
    pipe_material TEXT NOT NULL,
    pipe_diameter NUMERIC NOT NULL,
    pipe_sdr TEXT,
    pipe_wall_thickness NUMERIC,
    ambient_temperature NUMERIC,
    gps_lat NUMERIC(10, 7),
    gps_lng NUMERIC(10, 7),
    standard_used standard_code,
    is_cancelled BOOLEAN NOT NULL DEFAULT FALSE,
    cancel_reason TEXT,
    cancel_timestamp TIMESTAMPTZ,
    notes TEXT,
    started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_welds_project_id ON welds(project_id);
CREATE INDEX idx_welds_operator_id ON welds(operator_id);
CREATE INDEX idx_welds_status ON welds(status);
CREATE INDEX idx_welds_started_at ON welds(started_at);

-- ============================================================
-- WELD STEPS (one row per phase of a weld)
-- ============================================================
CREATE TABLE weld_steps (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    weld_id UUID NOT NULL REFERENCES welds(id) ON DELETE CASCADE,
    phase_name TEXT NOT NULL,
    phase_order INT NOT NULL,
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    nominal_value NUMERIC,
    actual_value NUMERIC,
    unit TEXT,
    validation_passed BOOLEAN,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_weld_steps_weld_id ON weld_steps(weld_id);

-- ============================================================
-- WELD PHOTOS
-- ============================================================
CREATE TABLE weld_photos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    weld_id UUID NOT NULL REFERENCES welds(id) ON DELETE CASCADE,
    storage_path TEXT NOT NULL,
    photo_type photo_type NOT NULL DEFAULT 'general',
    caption TEXT,
    taken_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    uploaded_by UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_weld_photos_weld_id ON weld_photos(weld_id);

-- ============================================================
-- WELD SIGNATURES (digital, for future certification)
-- ============================================================
CREATE TABLE weld_signatures (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    weld_id UUID NOT NULL REFERENCES welds(id) ON DELETE CASCADE,
    signed_by UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    signature_hash TEXT NOT NULL,
    signature_role user_role NOT NULL,
    signed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ip_address TEXT,
    device_info TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_weld_signatures_weld_id ON weld_signatures(weld_id);

-- ============================================================
-- SENSOR LOGS (1 Hz readings, batch uploaded)
-- Architecture note: mobile Sync Service uploads these in
-- batches of 100–200 records per request to avoid network
-- overload. Each record maps to a specific weld and phase.
-- Immutable once weld is completed (enforced via RLS).
-- ============================================================
CREATE TABLE sensor_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    weld_id UUID NOT NULL REFERENCES welds(id) ON DELETE CASCADE,
    weld_step_id UUID REFERENCES weld_steps(id) ON DELETE SET NULL,
    recorded_at TIMESTAMPTZ NOT NULL,
    pressure_bar NUMERIC(8, 4),
    temperature_celsius NUMERIC(8, 4),
    phase_name TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_sensor_logs_weld_id ON sensor_logs(weld_id);
CREATE INDEX idx_sensor_logs_recorded_at ON sensor_logs(recorded_at);
CREATE INDEX idx_sensor_logs_weld_step_id ON sensor_logs(weld_step_id);

-- ============================================================
-- WELD ERRORS (auto-cancellation events)
-- ============================================================
CREATE TABLE weld_errors (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    weld_id UUID NOT NULL REFERENCES welds(id) ON DELETE CASCADE,
    error_type TEXT NOT NULL,
    error_message TEXT NOT NULL,
    phase_name TEXT,
    parameter_name TEXT,
    actual_value NUMERIC,
    allowed_min NUMERIC,
    allowed_max NUMERIC,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_weld_errors_weld_id ON weld_errors(weld_id);

-- ============================================================
-- MACHINE MAINTENANCE
-- ============================================================
CREATE TABLE machine_maintenance (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    machine_id UUID NOT NULL REFERENCES machines(id) ON DELETE CASCADE,
    maintenance_type maintenance_type NOT NULL,
    performed_by UUID REFERENCES users(id) ON DELETE SET NULL,
    performed_at TIMESTAMPTZ NOT NULL,
    next_due_date DATE,
    notes TEXT,
    attachments_path TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_machine_maintenance_machine_id ON machine_maintenance(machine_id);

-- ============================================================
-- SENSOR CALIBRATIONS
-- Tracks calibration history for each plug-and-play sensor.
-- Sensors are calibrated against an RBC-certified reference gauge.
-- Offset and slope are applied to raw sensor readings.
-- ============================================================
CREATE TABLE sensor_calibrations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    machine_id UUID NOT NULL REFERENCES machines(id) ON DELETE CASCADE,
    sensor_serial TEXT NOT NULL,
    calibration_date DATE NOT NULL,
    calibrated_by UUID REFERENCES users(id) ON DELETE SET NULL,
    reference_device TEXT NOT NULL,
    reference_certificate TEXT NOT NULL,
    offset_value NUMERIC(10, 6) NOT NULL DEFAULT 0,
    slope_value NUMERIC(10, 6) NOT NULL DEFAULT 1,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_sensor_calibrations_machine_id ON sensor_calibrations(machine_id);
CREATE INDEX idx_sensor_calibrations_sensor_serial ON sensor_calibrations(sensor_serial);
CREATE INDEX idx_sensor_calibrations_date ON sensor_calibrations(calibration_date);

-- ============================================================
-- WELD CERTIFICATES (future digital certification system)
-- Not fully implemented yet — schema reserved for certification module.
-- ============================================================
CREATE TABLE weld_certificates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    weld_id UUID NOT NULL REFERENCES welds(id) ON DELETE RESTRICT,
    certificate_hash TEXT NOT NULL UNIQUE,
    issued_by UUID REFERENCES users(id) ON DELETE SET NULL,
    issued_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    certificate_status certificate_status NOT NULL DEFAULT 'draft',
    metadata JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_weld_certificates_weld_id ON weld_certificates(weld_id);
CREATE INDEX idx_weld_certificates_status ON weld_certificates(certificate_status);

-- ============================================================
-- UPDATED_AT TRIGGER FUNCTION
-- ============================================================
CREATE OR REPLACE FUNCTION trigger_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply updated_at trigger to all relevant tables
CREATE TRIGGER set_updated_at_companies
    BEFORE UPDATE ON companies
    FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

CREATE TRIGGER set_updated_at_users
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

CREATE TRIGGER set_updated_at_projects
    BEFORE UPDATE ON projects
    FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

CREATE TRIGGER set_updated_at_machines
    BEFORE UPDATE ON machines
    FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

CREATE TRIGGER set_updated_at_welds
    BEFORE UPDATE ON welds
    FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

CREATE TRIGGER set_updated_at_weld_steps
    BEFORE UPDATE ON weld_steps
    FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

CREATE TRIGGER set_updated_at_weld_certificates
    BEFORE UPDATE ON weld_certificates
    FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();
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
