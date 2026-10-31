-- =====================================================================
-- IT Inventory & Helpdesk Database
-- 02_seed.sql  -  realistic test data for a fictional company
-- (fictional company "Kvarner Trade d.o.o.", all people are invented)
-- Run after 01_schema.sql
-- =====================================================================

-- The file is saved as UTF-8 (Croatian letters in names)
SET client_encoding TO 'UTF8';
SET search_path TO helpdesk;

-- Same "random" data every time the script runs
SELECT setseed(0.42);

-- ---------------------------------------------------------------------
-- Reference data
-- ---------------------------------------------------------------------

INSERT INTO location (building, floor, room) VALUES
    ('Head Office', 0, 'Reception'),
    ('Head Office', 1, '101'),
    ('Head Office', 1, '102'),
    ('Head Office', 2, '201'),
    ('Head Office', 2, '202'),
    ('Head Office', 2, 'Server room'),
    ('Warehouse',   0, 'Office'),
    ('Warehouse',   0, 'Loading dock');

INSERT INTO department (name) VALUES
    ('Management'),
    ('Finance'),
    ('Sales'),
    ('Logistics'),
    ('IT');

INSERT INTO employee (first_name, last_name, email, department_id, location_id, is_it_staff) VALUES
    ('Marko',     'Horvat',    'marko.horvat@kvarnertrade.example',    1, 4, FALSE),
    ('Ivana',     'Kovačić',   'ivana.kovacic@kvarnertrade.example',   1, 4, FALSE),
    ('Petra',     'Babić',     'petra.babic@kvarnertrade.example',     2, 2, FALSE),
    ('Tomislav',  'Marić',     'tomislav.maric@kvarnertrade.example',  2, 2, FALSE),
    ('Ana',       'Jurić',     'ana.juric@kvarnertrade.example',       2, 2, FALSE),
    ('Luka',      'Novak',     'luka.novak@kvarnertrade.example',      3, 3, FALSE),
    ('Maja',      'Knežević',  'maja.knezevic@kvarnertrade.example',   3, 3, FALSE),
    ('Filip',     'Vuković',   'filip.vukovic@kvarnertrade.example',   3, 3, FALSE),
    ('Lucija',    'Marković',  'lucija.markovic@kvarnertrade.example', 3, 3, FALSE),
    ('Josip',     'Petrović',  'josip.petrovic@kvarnertrade.example',  3, 1, FALSE),
    ('Martina',   'Matić',     'martina.matic@kvarnertrade.example',   4, 7, FALSE),
    ('Ivan',      'Tomić',     'ivan.tomic@kvarnertrade.example',      4, 7, FALSE),
    ('Nikola',    'Pavlović',  'nikola.pavlovic@kvarnertrade.example', 4, 8, FALSE),
    ('Sara',      'Božić',     'sara.bozic@kvarnertrade.example',      4, 7, FALSE),
    ('Dario',     'Blažević',  'dario.blazevic@kvarnertrade.example',  4, 8, FALSE),
    ('Katarina',  'Grgić',     'katarina.grgic@kvarnertrade.example',  2, 2, FALSE),
    ('Matej',     'Pavić',     'matej.pavic@kvarnertrade.example',     3, 3, FALSE),
    ('Elena',     'Radić',     'elena.radic@kvarnertrade.example',     1, 1, FALSE),
    ('Antonio',   'Perić',     'antonio.peric@kvarnertrade.example',   5, 5, TRUE),
    ('Nina',      'Šarić',     'nina.saric@kvarnertrade.example',      5, 5, TRUE),
    ('Karlo',     'Lovrić',    'karlo.lovric@kvarnertrade.example',    5, 5, TRUE);

-- One former employee (inactive) - useful for data quality queries
INSERT INTO employee (first_name, last_name, email, department_id, location_id, is_active) VALUES
    ('Robert', 'Vidović', 'robert.vidovic@kvarnertrade.example', 3, NULL, FALSE);

INSERT INTO vendor (name, contact_email, phone) VALUES
    ('Adria IT Distribucija', 'prodaja@adriait.example',     '+385 51 000 101'),
    ('Kvarner Computers',     'info@kvarnercomputers.example', '+385 51 000 202'),
    ('NetOprema',             'sales@netoprema.example',     '+385 1 000 303');

INSERT INTO asset_category (name) VALUES
    ('Laptop'),        -- 1
    ('Desktop'),       -- 2
    ('Monitor'),       -- 3
    ('Printer'),       -- 4
    ('Network'),       -- 5
    ('Server'),        -- 6
    ('Phone');         -- 7

-- ---------------------------------------------------------------------
-- Assets
-- ---------------------------------------------------------------------

-- Laptops and desktops: one per active non-IT employee (laptops for
-- management/sales, desktops for others), plus spare and retired units
INSERT INTO asset (inventory_tag, category_id, vendor_id, model, serial_number,
                   purchase_date, purchase_price, warranty_until, status, location_id, assigned_to)
SELECT
    'INV-' || to_char(e.purchase_date, 'YYYY') || '-' || lpad(e.employee_id::text, 4, '0'),
    CASE WHEN e.department_id IN (1, 3, 5) THEN 1 ELSE 2 END,
    CASE WHEN e.department_id IN (1, 3, 5) THEN 1 ELSE 2 END,
    CASE WHEN e.department_id IN (1, 3, 5) THEN 'Lenovo ThinkPad T14' ELSE 'Dell OptiPlex 7010' END,
    'SN' || upper(substr(md5(e.email), 1, 10)),
    e.purchase_date,
    CASE WHEN e.department_id IN (1, 3, 5) THEN 1149.00 ELSE 789.00 END,
    e.purchase_date + INTERVAL '3 years',
    'in_use',
    e.location_id,
    e.employee_id
FROM (
    -- random purchase date between March 2022 and mid-2025, one per employee
    SELECT emp.*, DATE '2022-03-01' + floor(random() * 1200)::int AS purchase_date
    FROM employee emp
    WHERE emp.is_active
) e;

INSERT INTO asset (inventory_tag, category_id, vendor_id, model, serial_number,
                   purchase_date, purchase_price, warranty_until, status, location_id, assigned_to)
VALUES
    -- spares and devices in repair
    ('INV-2025-0101', 1, 1, 'Lenovo ThinkPad T14',   'SNSPARE0001', '2025-02-10', 1149.00, '2028-02-10', 'in_stock',  5, NULL),
    ('INV-2025-0102', 1, 1, 'Lenovo ThinkPad T14',   'SNSPARE0002', '2025-02-10', 1149.00, '2028-02-10', 'in_repair', 5, NULL),
    ('INV-2023-0103', 2, 2, 'Dell OptiPlex 7010',    'SNSPARE0003', '2023-06-15',  789.00, '2026-06-15', 'in_stock',  5, NULL),
    -- retired equipment
    ('INV-2019-0104', 2, 2, 'HP ProDesk 600 G4',     'SNOLD000001', '2019-04-01',  690.00, '2022-04-01', 'retired',   NULL, NULL),
    ('INV-2019-0105', 1, 1, 'HP ProBook 450 G6',     'SNOLD000002', '2019-04-01',  820.00, '2022-04-01', 'retired',   NULL, NULL),
    -- monitors
    ('INV-2023-0201', 3, 2, 'Dell P2423D 24"',       'SNMON000001', '2023-01-20',  249.00, '2026-01-20', 'in_use',    2, NULL),
    ('INV-2023-0202', 3, 2, 'Dell P2423D 24"',       'SNMON000002', '2023-01-20',  249.00, '2026-01-20', 'in_use',    2, NULL),
    ('INV-2023-0203', 3, 2, 'Dell P2423D 24"',       'SNMON000003', '2023-01-20',  249.00, '2026-01-20', 'in_use',    3, NULL),
    ('INV-2024-0204', 3, 2, 'LG 27UP650 27"',        'SNMON000004', '2024-09-05',  329.00, '2027-09-05', 'in_use',    4, NULL),
    -- printers
    ('INV-2022-0301', 4, 3, 'HP LaserJet Pro M404',  'SNPRN000001', '2022-05-12',  310.00, '2024-05-12', 'in_use',    2, NULL),
    ('INV-2023-0302', 4, 3, 'Brother MFC-L8900CDW',  'SNPRN000002', '2023-11-03',  690.00, '2025-11-03', 'in_use',    3, NULL),
    ('INV-2021-0303', 4, 3, 'HP LaserJet Pro M404',  'SNPRN000003', '2021-08-30',  310.00, '2023-08-30', 'in_use',    7, NULL),
    -- network and servers
    ('INV-2022-0401', 5, 3, 'Cisco CBS350-24P',      'SNNET000001', '2022-02-14',  520.00, '2027-02-14', 'in_use',    6, NULL),
    ('INV-2022-0402', 5, 3, 'Cisco CBS350-24P',      'SNNET000002', '2022-02-14',  520.00, '2027-02-14', 'in_use',    7, NULL),
    ('INV-2024-0403', 5, 3, 'Ubiquiti U6 Pro AP',    'SNNET000003', '2024-03-01',  159.00, '2026-03-01', 'in_use',    4, NULL),
    ('INV-2024-0404', 5, 3, 'Ubiquiti U6 Pro AP',    'SNNET000004', '2024-03-01',  159.00, '2026-03-01', 'in_use',    8, NULL),
    ('INV-2023-0501', 6, 1, 'Dell PowerEdge T350',   'SNSRV000001', '2023-04-18', 3450.00, '2028-04-18', 'in_use',    6, NULL),
    ('INV-2022-0502', 6, 1, 'Synology DS920+ NAS',   'SNSRV000002', '2022-07-07',  640.00, '2025-07-07', 'in_use',    6, NULL),
    -- phones
    ('INV-2024-0601', 7, 1, 'Samsung Galaxy A55',    'SNPHN000001', '2024-06-01',  449.00, '2026-06-01', 'in_use',    3, 6),
    ('INV-2024-0602', 7, 1, 'Samsung Galaxy A55',    'SNPHN000002', '2024-06-01',  449.00, '2026-06-01', 'in_use',    3, 7),
    ('INV-2024-0603', 7, 1, 'Samsung Galaxy A55',    'SNPHN000003', '2024-06-01',  449.00, '2026-06-01', 'in_use',    7, 11);

-- ---------------------------------------------------------------------
-- Tickets: ~150 over the last 12 months
-- ---------------------------------------------------------------------

-- Typical problems per asset category
CREATE TEMP TABLE problem (category_id INT, title TEXT, weight INT);
INSERT INTO problem VALUES
    (1,    'Laptop will not boot',                 2),
    (1,    'Battery drains very fast',             2),
    (1,    'Laptop overheating and fan noise',     2),
    (1,    'Cannot connect to Wi-Fi',              3),
    (2,    'Computer very slow at startup',        3),
    (2,    'Blue screen after Windows update',     2),
    (2,    'No sound from speakers',               1),
    (3,    'Monitor flickering',                   2),
    (3,    'No signal on second monitor',          2),
    (4,    'Printer paper jam',                    4),
    (4,    'Printer offline on the network',       3),
    (4,    'Toner replacement',                    3),
    (5,    'Network outage in the warehouse',      1),
    (5,    'Wi-Fi signal weak in meeting room',    2),
    (6,    'Shared drive not accessible',          2),
    (6,    'Backup job failed',                    2),
    (7,    'Company e-mail not syncing on phone',  2),
    (NULL, 'Password reset',                       5),
    (NULL, 'New user account setup',               2),
    (NULL, 'Outlook keeps asking for password',    3),
    (NULL, 'Request for software installation',    3),
    (NULL, 'VPN connection drops',                 2);

-- Expand by weight so frequent problems are picked more often
CREATE TEMP TABLE problem_pool AS
SELECT row_number() OVER () AS n, p.category_id, p.title
FROM problem p, generate_series(1, p.weight);

-- Step 1: all random values for each ticket, drawn once per row
CREATE TEMP TABLE ticket_draft AS
SELECT
    i,
    random() AS r_problem,
    random() AS r_day,
    random() AS r_hour,
    random() AS r_minute,
    random() AS r_priority,
    random() AS r_status,
    random() AS r_resolve,
    random() AS r_asset,
    random() AS r_reporter,
    random() AS r_it,
    random() AS r_unassigned
FROM generate_series(1, 150) AS i;

-- Step 2: turn random values into ticket attributes
CREATE TEMP TABLE ticket_plan AS
WITH base AS (
    SELECT
        d.*,
        pp.category_id,
        pp.title,
        -- weekdays 07:00-16:00, spread over the last 12 months
        TIMESTAMPTZ '2025-10-30'
            + floor(d.r_day * 364) * INTERVAL '1 day'
            + (7 + floor(d.r_hour * 9)) * INTERVAL '1 hour'
            + floor(d.r_minute * 60) * INTERVAL '1 minute' AS raw_created_at
    FROM ticket_draft d
    JOIN problem_pool pp
      ON pp.n = 1 + floor(d.r_problem * (SELECT count(*) FROM problem_pool))::int
),
dated AS (
    SELECT
        b.*,
        -- move weekend tickets to the following Monday
        raw_created_at + CASE extract(isodow FROM raw_created_at)
                             WHEN 6 THEN INTERVAL '2 days'
                             WHEN 7 THEN INTERVAL '1 day'
                             ELSE INTERVAL '0'
                         END AS created_at,
        CASE
            WHEN title IN ('Network outage in the warehouse', 'Shared drive not accessible') THEN 'critical'
            WHEN r_priority < 0.15 THEN 'high'
            WHEN r_priority < 0.80 THEN 'medium'
            ELSE 'low'
        END AS priority
    FROM base b
)
SELECT
    d.*,
    -- recent tickets are more likely to still be open
    CASE
        WHEN created_at > TIMESTAMPTZ '2026-10-16' THEN CASE WHEN r_status < 0.5 THEN 'open' ELSE 'in_progress' END
        WHEN created_at > TIMESTAMPTZ '2026-10-01' AND r_status < 0.3 THEN 'in_progress'
        WHEN created_at > TIMESTAMPTZ '2026-09-01' THEN 'resolved'
        ELSE 'closed'
    END AS status,
    -- higher priority = faster resolution (in hours)
    CASE priority
        WHEN 'critical' THEN 1  + r_resolve * 5
        WHEN 'high'     THEN 2  + r_resolve * 22
        WHEN 'medium'   THEN 4  + r_resolve * 68
        ELSE                 24 + r_resolve * 144
    END AS resolve_hours
FROM dated d;

-- Step 3: insert tickets, linking assets, reporters and IT staff
INSERT INTO ticket (asset_id, reported_by, assigned_to, title, priority, status, created_at, resolved_at)
SELECT
    a.asset_id,
    COALESCE(a.assigned_to, rep.employee_id),
    CASE WHEN p.status = 'open' AND p.r_unassigned < 0.5 THEN NULL ELSE it.employee_id END,
    p.title,
    p.priority,
    p.status,
    p.created_at,
    CASE WHEN p.status IN ('resolved', 'closed')
         THEN p.created_at + p.resolve_hours * INTERVAL '1 hour'
    END
FROM ticket_plan p
-- an asset of the matching category (none for account/software issues)
LEFT JOIN LATERAL (
    SELECT asset_id, assigned_to
    FROM asset
    WHERE category_id = p.category_id
      AND status <> 'retired'
    ORDER BY asset_id
    OFFSET floor(p.r_asset * (SELECT count(*) FROM asset
                              WHERE category_id = p.category_id AND status <> 'retired'))::int
    LIMIT 1
) a ON TRUE
-- fallback reporter: a random active non-IT employee
CROSS JOIN LATERAL (
    SELECT employee_id
    FROM employee
    WHERE is_active AND NOT is_it_staff
    ORDER BY employee_id
    OFFSET floor(p.r_reporter * (SELECT count(*) FROM employee WHERE is_active AND NOT is_it_staff))::int
    LIMIT 1
) rep
-- IT staff member handling the ticket
CROSS JOIN LATERAL (
    SELECT employee_id
    FROM employee
    WHERE is_it_staff
    ORDER BY employee_id
    OFFSET floor(p.r_it * (SELECT count(*) FROM employee WHERE is_it_staff))::int
    LIMIT 1
) it
ORDER BY p.created_at;

-- ---------------------------------------------------------------------
-- A few comments on recent tickets
-- ---------------------------------------------------------------------

INSERT INTO ticket_comment (ticket_id, author_id, body, created_at)
SELECT t.ticket_id,
       t.assigned_to,
       CASE WHEN t.status IN ('resolved', 'closed')
            THEN 'Issue resolved, user confirmed everything works.'
            ELSE 'Looking into it, will update soon.'
       END,
       COALESCE(t.resolved_at, t.created_at + INTERVAL '30 minutes')
FROM ticket t
WHERE t.assigned_to IS NOT NULL
  AND t.created_at > TIMESTAMPTZ '2026-09-01';

-- ---------------------------------------------------------------------
-- Quick summary
-- ---------------------------------------------------------------------

SELECT 'employees' AS what, count(*) FROM employee
UNION ALL SELECT 'assets',   count(*) FROM asset
UNION ALL SELECT 'tickets',  count(*) FROM ticket
UNION ALL SELECT 'comments', count(*) FROM ticket_comment;