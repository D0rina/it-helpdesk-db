# IT Inventory & Helpdesk Database

A PostgreSQL database for managing an organisation's IT equipment and support tickets —
from conceptual ER model to business reports written in SQL.

🇭🇷 *Baza podataka za evidenciju IT opreme i prijava kvarova (helpdesk) u PostgreSQL-u.*

> 🚧 Work in progress

## Structure

| File | Contents |
|---|---|
| `sql/01_schema.sql` | Tables, constraints, indexes |
| `docs/` | ER diagram and relational model |

## How to run

```bash
psql -U postgres -f sql/01_schema.sql
```