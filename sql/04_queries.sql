-- =====================================================================
-- IT Inventory & Helpdesk Database
-- 04_queries.sql  -  business questions answered with SQL
-- Run after 01-03. Each query can also be run on its own.
-- =====================================================================

SET client_encoding TO 'UTF8';
SET search_path TO helpdesk;

-- ---------------------------------------------------------------------
-- Q1. How many tickets do we get per month, and is it going up or down?
--     (window function LAG compares each month with the previous one)
-- ---------------------------------------------------------------------
SELECT
    to_char(month, 'YYYY-MM')                    AS month,
    tickets,
    tickets - LAG(tickets) OVER (ORDER BY month) AS change_vs_prev_month
FROM (
    SELECT date_trunc('month', created_at) AS month, count(*) AS tickets
    FROM ticket
    GROUP BY 1
) m
ORDER BY month;

-- ---------------------------------------------------------------------
-- Q2. Are we meeting our SLA (target resolution time per priority)?
--     critical 4 h, high 24 h, medium 72 h, low 168 h
-- ---------------------------------------------------------------------
WITH sla (priority, target_hours, sort_order) AS (
    VALUES ('critical', 4, 1), ('high', 24, 2), ('medium', 72, 3), ('low', 168, 4)
)
SELECT
    t.priority,
    s.target_hours,
    count(*) AS resolved_tickets,
    round(avg(extract(epoch FROM t.resolved_at - t.created_at) / 3600), 1) AS avg_hours,
    round((percentile_cont(0.5) WITHIN GROUP (
              ORDER BY extract(epoch FROM t.resolved_at - t.created_at) / 3600))::numeric, 1) AS median_hours,
    round(100.0 * count(*) FILTER (
              WHERE t.resolved_at - t.created_at <= s.target_hours * INTERVAL '1 hour')
          / count(*), 1) AS pct_within_sla
FROM ticket t
JOIN sla s ON s.priority = t.priority
WHERE t.resolved_at IS NOT NULL
GROUP BY t.priority, s.target_hours, s.sort_order
ORDER BY s.sort_order;

-- ---------------------------------------------------------------------
-- Q3. How is the work distributed across the IT team?
-- ---------------------------------------------------------------------
SELECT
    e.first_name || ' ' || e.last_name AS it_staff,
    count(*) FILTER (WHERE t.status IN ('resolved', 'closed'))   AS resolved,
    count(*) FILTER (WHERE t.status IN ('open', 'in_progress'))  AS in_queue,
    round(avg(extract(epoch FROM t.resolved_at - t.created_at) / 3600), 1) AS avg_hours,
    round(100.0 * count(*) / sum(count(*)) OVER (), 1)           AS pct_of_all_tickets,
    RANK() OVER (ORDER BY count(*) FILTER (WHERE t.status IN ('resolved', 'closed')) DESC) AS rank
FROM ticket t
JOIN employee e ON e.employee_id = t.assigned_to
GROUP BY e.employee_id, e.first_name, e.last_name
ORDER BY rank;

-- ---------------------------------------------------------------------
-- Q4. What are the most common problems?
-- ---------------------------------------------------------------------
SELECT
    t.title                            AS problem,
    COALESCE(c.name, 'Account / software') AS area,
    count(*)                           AS tickets,
    round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS pct
FROM ticket t
LEFT JOIN asset a          ON a.asset_id = t.asset_id
LEFT JOIN asset_category c ON c.category_id = a.category_id
GROUP BY t.title, c.name
ORDER BY tickets DESC
LIMIT 10;

-- ---------------------------------------------------------------------
-- Q5. Which devices cause the most trouble? (candidates for replacement)
-- ---------------------------------------------------------------------
SELECT
    inventory_tag,
    category,
    model,
    location,
    purchase_date,
    warranty_status,
    ticket_count
FROM v_asset_overview
WHERE ticket_count >= 5
ORDER BY ticket_count DESC, purchase_date;

-- ---------------------------------------------------------------------
-- Q6. Recurring faults: the same device reported again within 30 days
--     after the previous ticket was resolved
-- ---------------------------------------------------------------------
WITH asset_tickets AS (
    SELECT
        t.asset_id,
        t.ticket_id,
        t.title,
        t.created_at,
        LAG(t.resolved_at) OVER (PARTITION BY t.asset_id ORDER BY t.created_at) AS prev_resolved_at,
        LAG(t.title)       OVER (PARTITION BY t.asset_id ORDER BY t.created_at) AS prev_title
    FROM ticket t
    WHERE t.asset_id IS NOT NULL
)
SELECT
    a.inventory_tag,
    a.model,
    at.prev_title AS previous_problem,
    at.title      AS new_problem,
    (at.created_at::date - at.prev_resolved_at::date) AS days_later
FROM asset_tickets at
JOIN asset a ON a.asset_id = at.asset_id
WHERE at.created_at - at.prev_resolved_at BETWEEN INTERVAL '0' AND INTERVAL '30 days'
ORDER BY days_later
LIMIT 15;

-- ---------------------------------------------------------------------
-- Q7. Which department reports the most issues per employee?
-- ---------------------------------------------------------------------
SELECT
    d.name AS department,
    count(DISTINCT e.employee_id) AS employees,
    count(t.ticket_id)            AS tickets,
    round(count(t.ticket_id)::numeric / NULLIF(count(DISTINCT e.employee_id), 0), 1) AS tickets_per_employee
FROM department d
JOIN employee e     ON e.department_id = d.department_id AND e.is_active
LEFT JOIN ticket t  ON t.reported_by = e.employee_id
GROUP BY d.name
ORDER BY tickets_per_employee DESC;

-- ---------------------------------------------------------------------
-- Q8. When are we busiest? (weekday x part of day)
-- ---------------------------------------------------------------------
SELECT
    to_char(created_at, 'ID Dy') AS weekday,
    count(*) FILTER (WHERE extract(hour FROM created_at) < 10)              AS "07-10",
    count(*) FILTER (WHERE extract(hour FROM created_at) BETWEEN 10 AND 12) AS "10-13",
    count(*) FILTER (WHERE extract(hour FROM created_at) >= 13)             AS "13-16",
    count(*) AS total
FROM ticket
GROUP BY 1
ORDER BY 1;

-- ---------------------------------------------------------------------
-- Q9. Warranty planning: equipment in use whose warranty has expired
--     or expires in the next 6 months, and what replacing it would cost
-- ---------------------------------------------------------------------
SELECT
    category,
    count(*) FILTER (WHERE warranty_until <  current_date) AS expired,
    count(*) FILTER (WHERE warranty_until >= current_date
                       AND warranty_until <  current_date + INTERVAL '6 months') AS expiring_6_months,
    sum(purchase_price) FILTER (WHERE warranty_until < current_date + INTERVAL '6 months') AS replacement_budget_eur
FROM v_asset_overview
WHERE status = 'in_use'
GROUP BY category
HAVING count(*) FILTER (WHERE warranty_until < current_date + INTERVAL '6 months') > 0
ORDER BY replacement_budget_eur DESC;

-- ---------------------------------------------------------------------
-- Q10. Inventory value by purchase year, with a running total
-- ---------------------------------------------------------------------
SELECT
    purchase_year,
    assets,
    value_eur,
    sum(value_eur) OVER (ORDER BY purchase_year) AS running_total_eur
FROM (
    SELECT
        extract(year FROM purchase_date)::int AS purchase_year,
        count(*)                              AS assets,
        sum(purchase_price)                   AS value_eur
    FROM asset
    WHERE status <> 'retired'
    GROUP BY 1
) y
ORDER BY purchase_year;

-- ---------------------------------------------------------------------
-- Q11. Data quality checks - each row is something to fix
-- ---------------------------------------------------------------------
SELECT 'Asset assigned to an inactive employee' AS issue,
       a.inventory_tag AS detail
FROM asset a
JOIN employee e ON e.employee_id = a.assigned_to
WHERE NOT e.is_active

UNION ALL
SELECT 'Active employee without a computer',
       e.first_name || ' ' || e.last_name
FROM employee e
WHERE e.is_active
  AND NOT EXISTS (SELECT 1 FROM asset a
                  WHERE a.assigned_to = e.employee_id AND a.category_id IN (1, 2))

UNION ALL
SELECT 'Open ticket without an assignee',
       '#' || t.ticket_id || ' ' || t.title
FROM ticket t
WHERE t.status IN ('open', 'in_progress') AND t.assigned_to IS NULL

UNION ALL
SELECT 'In-use asset without a location',
       a.inventory_tag
FROM asset a
WHERE a.status = 'in_use' AND a.location_id IS NULL;