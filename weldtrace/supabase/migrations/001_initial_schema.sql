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
