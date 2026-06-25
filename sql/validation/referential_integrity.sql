-- =============================================================================
-- referential_integrity.sql
-- Purpose: Find orphan foreign keys not present in the parent table. Zero rows = pass.
-- Workflow: validation before curated publish
-- =============================================================================

SELECT DISTINCT
  child.{{foreign_key_column}} AS orphan_key
FROM {{child_table}} AS child
LEFT JOIN {{parent_table}} AS parent
  ON child.{{foreign_key_column}} = parent.{{parent_key_column}}
WHERE child.{{foreign_key_column}} IS NOT NULL
  AND parent.{{parent_key_column}} IS NULL
ORDER BY orphan_key;

-- -----------------------------------------------------------------------------
-- Example: orders referencing missing customers
-- -----------------------------------------------------------------------------
-- SELECT DISTINCT
--   o.customer_id AS orphan_key
-- FROM staging.stg_orders AS o
-- LEFT JOIN staging.stg_customers AS c
--   ON o.customer_id = c.customer_id
-- WHERE o.customer_id IS NOT NULL
--   AND c.customer_id IS NULL
-- ORDER BY orphan_key;
