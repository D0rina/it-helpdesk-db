-- =====================================================================
-- IT Inventory & Helpdesk Database
-- 01_schema.sql  -  tables, constraints and indexes
-- Target: PostgreSQL 15+
-- =====================================================================

-- Re-runnable: drop and recreate the whole schema
DROP SCHEMA IF EXISTS helpdesk CASCADE;
CREATE SCHEMA helpdesk;
SET search_path TO helpdesk;

-- ---------------------------------------------------------------------
-- Organisation
-- ---------------------------------------------------------------------

CREATE TABLE location (
    location_id  INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    building     VARCHAR(100) NOT NULL,
    floor        SMALLINT,
    room         VARCHAR(20)  NOT NULL,
    CONSTRAINT uq_location UNIQUE (building, room)
);

CREATE TABLE department (
    department_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name          VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE employee (
    employee_id   INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    first_name    VARCHAR(50)  NOT NULL,
    last_name     VARCHAR(50)  NOT NULL,
    email         VARCHAR(255) NOT NULL UNIQUE,
    department_id INT NOT NULL REFERENCES department (department_id),
    location_id   INT          REFERENCES location (location_id),
    is_it_staff   BOOLEAN NOT NULL DEFAULT FALSE,
    is_active     BOOLEAN NOT NULL DEFAULT TRUE
);

-- ---------------------------------------------------------------------
-- Inventory
-- ---------------------------------------------------------------------

CREATE TABLE vendor (
    vendor_id     INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name          VARCHAR(100) NOT NULL UNIQUE,
    contact_email VARCHAR(255),
    phone         VARCHAR(30)
);

CREATE TABLE asset_category (
    category_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name        VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE asset (
    asset_id       INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    inventory_tag  VARCHAR(20)  NOT NULL UNIQUE,      -- e.g. INV-2024-0001
    category_id    INT          NOT NULL REFERENCES asset_category (category_id),
    vendor_id      INT          REFERENCES vendor (vendor_id),
    model          VARCHAR(100) NOT NULL,
    serial_number  VARCHAR(50)  UNIQUE,
    purchase_date  DATE         NOT NULL,
    purchase_price NUMERIC(10,2) CHECK (purchase_price >= 0),
    warranty_until DATE,
    status         VARCHAR(20)  NOT NULL DEFAULT 'in_stock',
    location_id    INT          REFERENCES location (location_id),
    assigned_to    INT          REFERENCES employee (employee_id),

    CONSTRAINT ck_asset_status
        CHECK (status IN ('in_stock', 'in_use', 'in_repair', 'retired')),
    CONSTRAINT ck_asset_warranty
        CHECK (warranty_until IS NULL OR warranty_until >= purchase_date),
    -- an asset can only be assigned to a person while it is in use
    CONSTRAINT ck_asset_assignment
        CHECK (assigned_to IS NULL OR status = 'in_use')
);

-- ---------------------------------------------------------------------
-- Helpdesk
-- ---------------------------------------------------------------------

CREATE TABLE ticket (
    ticket_id    INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    asset_id     INT          REFERENCES asset (asset_id),   -- NULL = not tied to a device
    reported_by  INT NOT NULL REFERENCES employee (employee_id),
    assigned_to  INT          REFERENCES employee (employee_id),
    title        VARCHAR(150) NOT NULL,
    description  TEXT,
    priority     VARCHAR(10)  NOT NULL DEFAULT 'medium',
    status       VARCHAR(15)  NOT NULL DEFAULT 'open',
    created_at   TIMESTAMPTZ  NOT NULL DEFAULT now(),
    resolved_at  TIMESTAMPTZ,

    CONSTRAINT ck_ticket_priority
        CHECK (priority IN ('low', 'medium', 'high', 'critical')),
    CONSTRAINT ck_ticket_status
        CHECK (status IN ('open', 'in_progress', 'resolved', 'closed')),
    CONSTRAINT ck_ticket_resolved_time
        CHECK (resolved_at IS NULL OR resolved_at >= created_at),
    -- resolved/closed tickets must have a resolution time, open ones must not
    CONSTRAINT ck_ticket_resolved_consistency
        CHECK ((status IN ('resolved', 'closed')) = (resolved_at IS NOT NULL))
);

CREATE TABLE ticket_comment (
    comment_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ticket_id  INT  NOT NULL REFERENCES ticket (ticket_id) ON DELETE CASCADE,
    author_id  INT  NOT NULL REFERENCES employee (employee_id),
    body       TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Audit trail of status changes (filled automatically by a trigger, see 03_logic.sql)
CREATE TABLE ticket_status_history (
    history_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ticket_id  INT NOT NULL REFERENCES ticket (ticket_id) ON DELETE CASCADE,
    old_status VARCHAR(15),
    new_status VARCHAR(15) NOT NULL,
    changed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- Indexes on foreign keys and frequent filters
-- (PostgreSQL does not index foreign keys automatically)
-- ---------------------------------------------------------------------

CREATE INDEX ix_employee_department ON employee (department_id);
CREATE INDEX ix_asset_category      ON asset (category_id);
CREATE INDEX ix_asset_assigned_to   ON asset (assigned_to);
CREATE INDEX ix_asset_location      ON asset (location_id);
CREATE INDEX ix_ticket_asset        ON ticket (asset_id);
CREATE INDEX ix_ticket_assigned_to  ON ticket (assigned_to);
CREATE INDEX ix_ticket_status       ON ticket (status);
CREATE INDEX ix_comment_ticket      ON ticket_comment (ticket_id);
CREATE INDEX ix_history_ticket      ON ticket_status_history (ticket_id);