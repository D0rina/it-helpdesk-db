-- =====================================================================
-- IT Inventory & Helpdesk Database
-- 03_logic.sql  -  triggers, views and a stored procedure
-- Run after 01_schema.sql and 02_seed.sql
-- =====================================================================

SET client_encoding TO 'UTF8';
SET search_path TO helpdesk;

-- =====================================================================
-- 1. TRIGGERS
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1a. Keep resolved_at in sync with the ticket status
--     resolved / closed  -> resolved_at is filled in (if empty)
--     open / in_progress -> resolved_at is cleared (ticket reopened)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_ticket_set_resolved_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = helpdesk
AS $$
BEGIN
    IF NEW.status IN ('resolved', 'closed') THEN
        NEW.resolved_at := COALESCE(NEW.resolved_at, now());
    ELSE
        NEW.resolved_at := NULL;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS ticket_set_resolved_at ON ticket;
CREATE TRIGGER ticket_set_resolved_at
    BEFORE INSERT OR UPDATE OF status ON ticket
    FOR EACH ROW
    EXECUTE FUNCTION trg_ticket_set_resolved_at();

-- ---------------------------------------------------------------------
-- 1b. Write every status change to ticket_status_history
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_ticket_log_status()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = helpdesk
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO ticket_status_history (ticket_id, old_status, new_status, changed_at)
        VALUES (NEW.ticket_id, NULL, NEW.status, NEW.created_at);
    ELSIF NEW.status IS DISTINCT FROM OLD.status THEN
        INSERT INTO ticket_status_history (ticket_id, old_status, new_status)
        VALUES (NEW.ticket_id, OLD.status, NEW.status);
    END IF;
    RETURN NULL;   -- AFTER trigger: return value is ignored
END;
$$;

DROP TRIGGER IF EXISTS ticket_log_status ON ticket;
CREATE TRIGGER ticket_log_status
    AFTER INSERT OR UPDATE OF status ON ticket
    FOR EACH ROW
    EXECUTE FUNCTION trg_ticket_log_status();

-- ---------------------------------------------------------------------
-- 1c. Backfill history for tickets that were loaded before the trigger
--     existed (02_seed.sql), so reports have complete data
-- ---------------------------------------------------------------------
TRUNCATE ticket_status_history RESTART IDENTITY;

INSERT INTO ticket_status_history (ticket_id, old_status, new_status, changed_at)
SELECT ticket_id, old_status, new_status, changed_at
FROM (
    -- every ticket starts as 'open'
    SELECT ticket_id, NULL AS old_status, 'open' AS new_status, created_at AS changed_at
    FROM ticket
    UNION ALL
    -- work started 15 minutes after creation
    SELECT ticket_id, 'open', 'in_progress', created_at + INTERVAL '15 minutes'
    FROM ticket
    WHERE status <> 'open'
    UNION ALL
    SELECT ticket_id, 'in_progress', 'resolved', resolved_at
    FROM ticket
    WHERE status IN ('resolved', 'closed')
    UNION ALL
    -- user confirmation closes the ticket two days later
    SELECT ticket_id, 'resolved', 'closed', resolved_at + INTERVAL '2 days'
    FROM ticket
    WHERE status = 'closed'
) h
ORDER BY changed_at;

-- =====================================================================
-- 2. VIEWS
-- =====================================================================

-- ---------------------------------------------------------------------
-- 2a. Tickets with readable names instead of IDs
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_ticket_details AS
SELECT
    t.ticket_id,
    t.title,
    t.priority,
    t.status,
    t.created_at,
    t.resolved_at,
    round(extract(epoch FROM t.resolved_at - t.created_at) / 3600, 1) AS resolution_hours,
    r.first_name || ' ' || r.last_name   AS reported_by,
    d.name                               AS department,
    it.first_name || ' ' || it.last_name AS assigned_to,
    a.inventory_tag,
    c.name                               AS asset_category,
    a.model                              AS asset_model
FROM ticket t
JOIN employee r        ON r.employee_id = t.reported_by
JOIN department d      ON d.department_id = r.department_id
LEFT JOIN employee it  ON it.employee_id = t.assigned_to
LEFT JOIN asset a      ON a.asset_id = t.asset_id
LEFT JOIN asset_category c ON c.category_id = a.category_id;

-- ---------------------------------------------------------------------
-- 2b. Open work queue for the IT team, most urgent first
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_open_tickets AS
SELECT
    ticket_id,
    priority,
    status,
    title,
    reported_by,
    department,
    COALESCE(assigned_to, '-- unassigned --') AS assigned_to,
    inventory_tag,
    created_at,
    round(extract(epoch FROM now() - created_at) / 3600, 1) AS age_hours
FROM v_ticket_details
WHERE status IN ('open', 'in_progress')
ORDER BY
    CASE priority
        WHEN 'critical' THEN 1
        WHEN 'high'     THEN 2
        WHEN 'medium'   THEN 3
        ELSE 4
    END,
    created_at;

-- ---------------------------------------------------------------------
-- 2c. Asset register with warranty status and number of tickets
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_asset_overview AS
SELECT
    a.asset_id,
    a.inventory_tag,
    c.name AS category,
    a.model,
    a.status,
    l.building || ' / ' || l.room AS location,
    e.first_name || ' ' || e.last_name AS assigned_to,
    a.purchase_date,
    a.purchase_price,
    a.warranty_until,
    CASE
        WHEN a.warranty_until IS NULL                          THEN 'unknown'
        WHEN a.warranty_until < current_date                   THEN 'expired'
        WHEN a.warranty_until < current_date + INTERVAL '90 days' THEN 'expires soon'
        ELSE 'valid'
    END AS warranty_status,
    (SELECT count(*) FROM ticket t WHERE t.asset_id = a.asset_id) AS ticket_count
FROM asset a
JOIN asset_category c ON c.category_id = a.category_id
LEFT JOIN location l  ON l.location_id = a.location_id
LEFT JOIN employee e  ON e.employee_id = a.assigned_to;

-- =====================================================================
-- 3. STORED PROCEDURE
-- =====================================================================

-- ---------------------------------------------------------------------
-- Resolve a ticket and record a comment in one transaction.
-- Usage:  CALL resolve_ticket(148, 19, 'Replaced the power adapter.');
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE resolve_ticket(
    p_ticket_id INT,
    p_author_id INT,
    p_note      TEXT
)
LANGUAGE plpgsql
SET search_path = helpdesk
AS $$
DECLARE
    v_status VARCHAR(15);
BEGIN
    SELECT status INTO v_status
    FROM ticket
    WHERE ticket_id = p_ticket_id
    FOR UPDATE;                              -- lock the row while we work

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Ticket % does not exist', p_ticket_id;
    END IF;

    IF v_status IN ('resolved', 'closed') THEN
        RAISE EXCEPTION 'Ticket % is already %', p_ticket_id, v_status;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM employee
                   WHERE employee_id = p_author_id AND is_it_staff AND is_active) THEN
        RAISE EXCEPTION 'Employee % is not active IT staff', p_author_id;
    END IF;

    UPDATE ticket
    SET status      = 'resolved',
        assigned_to = COALESCE(assigned_to, p_author_id)
    WHERE ticket_id = p_ticket_id;           -- triggers set resolved_at and log history

    INSERT INTO ticket_comment (ticket_id, author_id, body)
    VALUES (p_ticket_id, p_author_id, p_note);
END;
$$;