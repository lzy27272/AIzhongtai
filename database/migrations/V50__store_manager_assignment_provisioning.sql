-- Keep store-manager reporting lines and the published daily work package in sync
-- with every newly-created hotel GENERAL_MANAGER assignment.  V47 provisioned
-- only the assignments that existed while that migration ran; employees approved
-- afterwards therefore had no allocation and could never receive expectations or
-- reminders.

CREATE OR REPLACE FUNCTION assign_store_manager_direct_manager()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.manager_assignment_id IS NULL
       AND NEW.status = 'ACTIVE'
       AND EXISTS (
           SELECT 1
           FROM position_definition position
           JOIN org_unit organization
             ON organization.tenant_id = position.tenant_id
            AND organization.id = NEW.org_unit_id
           WHERE position.tenant_id = NEW.tenant_id
             AND position.id = NEW.position_id
             AND position.code = 'GENERAL_MANAGER'
             AND organization.unit_type = 'HOTEL'
             AND organization.status = 'ACTIVE'
       ) THEN
        SELECT manager.id
        INTO NEW.manager_assignment_id
        FROM employee_position_assignment manager
        JOIN position_definition manager_position
          ON manager_position.tenant_id = manager.tenant_id
         AND manager_position.id = manager.position_id
        JOIN employee manager_employee
          ON manager_employee.tenant_id = manager.tenant_id
         AND manager_employee.id = manager.employee_id
        JOIN user_account manager_account
          ON manager_account.tenant_id = manager_employee.tenant_id
         AND manager_account.id = manager_employee.account_id
        WHERE manager.tenant_id = NEW.tenant_id
          AND manager_position.code = 'GROUP_GENERAL_MANAGER'
          AND manager.status = 'ACTIVE'
          AND manager.valid_from <= NEW.valid_from
          AND (manager.valid_to IS NULL OR manager.valid_to >= NEW.valid_from)
          AND manager_employee.employment_status = 'ACTIVE'
          AND manager_employee.deleted_at IS NULL
          AND manager_account.status = 'ACTIVE'
        ORDER BY manager.is_primary DESC, manager.valid_from DESC, manager.id
        LIMIT 1;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_store_manager_direct_manager ON employee_position_assignment;
CREATE TRIGGER trg_store_manager_direct_manager
    BEFORE INSERT ON employee_position_assignment
    FOR EACH ROW
    EXECUTE FUNCTION assign_store_manager_direct_manager();

CREATE OR REPLACE FUNCTION allocate_store_manager_daily_work_package()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.status = 'ACTIVE' THEN
        INSERT INTO work_package_allocation
            (id, tenant_id, work_package_version_id, position_assignment_id,
             target_org_unit_id, allocation_source, valid_from, valid_to,
             status, allocated_by)
        SELECT gen_random_uuid(), NEW.tenant_id, published.id, NEW.id,
               NEW.org_unit_id, 'SYSTEM', NEW.valid_from, NEW.valid_to,
               'ACTIVE', definition.created_by
        FROM work_package_definition definition
        JOIN position_definition position
          ON position.tenant_id = definition.tenant_id
         AND position.id = definition.position_id
        JOIN org_unit organization
          ON organization.tenant_id = definition.tenant_id
         AND organization.id = NEW.org_unit_id
        JOIN LATERAL (
            SELECT version.id
            FROM work_package_version version
            WHERE version.tenant_id = definition.tenant_id
              AND version.work_package_definition_id = definition.id
              AND version.lifecycle_status = 'PUBLISHED'
              AND version.effective_from <= now()
              AND (version.effective_to IS NULL OR version.effective_to >= now())
            ORDER BY version.version_no DESC, version.id
            LIMIT 1
        ) published ON true
        WHERE definition.tenant_id = NEW.tenant_id
          AND definition.code = 'WP-PILOT-GM-DAILY'
          AND definition.status = 'ACTIVE'
          AND definition.position_id = NEW.position_id
          AND position.code = 'GENERAL_MANAGER'
          AND organization.unit_type = 'HOTEL'
          AND organization.status = 'ACTIVE'
          AND EXISTS (
              SELECT 1
              FROM work_package_scope scope
              WHERE scope.tenant_id = NEW.tenant_id
                AND scope.work_package_version_id = published.id
                AND (
                    scope.scope_type = 'TENANT'
                    OR (scope.scope_type = 'POSITION' AND scope.position_id = NEW.position_id)
                    OR (scope.scope_type = 'ORG_UNIT' AND scope.org_unit_id = NEW.org_unit_id)
                    OR (scope.scope_type = 'ORG_TREE' AND EXISTS (
                        SELECT 1
                        FROM org_unit_closure closure
                        WHERE closure.tenant_id = scope.tenant_id
                          AND closure.ancestor_id = scope.org_unit_id
                          AND closure.descendant_id = NEW.org_unit_id
                    ))
                    OR (scope.scope_type = 'BRAND' AND EXISTS (
                        SELECT 1
                        FROM hotel_profile hotel
                        WHERE hotel.tenant_id = scope.tenant_id
                          AND hotel.org_unit_id = NEW.org_unit_id
                          AND hotel.brand_id = scope.brand_id
                    ))
                )
          )
          AND NOT EXISTS (
              SELECT 1
              FROM work_package_allocation existing
              WHERE existing.tenant_id = NEW.tenant_id
                AND existing.work_package_version_id = published.id
                AND existing.position_assignment_id = NEW.id
                AND existing.target_org_unit_id = NEW.org_unit_id
                AND existing.status = 'ACTIVE'
          );
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_store_manager_daily_work_package ON employee_position_assignment;
CREATE TRIGGER trg_store_manager_daily_work_package
    AFTER INSERT ON employee_position_assignment
    FOR EACH ROW
    EXECUTE FUNCTION allocate_store_manager_daily_work_package();

-- Repair reporting lines for active hotel store managers created after V46.
WITH store_manager_reporting AS (
    SELECT store_manager.tenant_id, store_manager.id AS store_manager_id,
           group_manager.id AS group_manager_id
    FROM employee_position_assignment store_manager
    JOIN position_definition store_manager_position
      ON store_manager_position.tenant_id = store_manager.tenant_id
     AND store_manager_position.id = store_manager.position_id
    JOIN org_unit store_manager_org
      ON store_manager_org.tenant_id = store_manager.tenant_id
     AND store_manager_org.id = store_manager.org_unit_id
    JOIN LATERAL (
         SELECT manager.id
         FROM employee_position_assignment manager
         JOIN position_definition manager_position
           ON manager_position.tenant_id = manager.tenant_id
          AND manager_position.id = manager.position_id
         JOIN employee manager_employee
           ON manager_employee.tenant_id = manager.tenant_id
          AND manager_employee.id = manager.employee_id
         JOIN user_account manager_account
           ON manager_account.tenant_id = manager_employee.tenant_id
          AND manager_account.id = manager_employee.account_id
         WHERE manager.tenant_id = store_manager.tenant_id
           AND manager_position.code = 'GROUP_GENERAL_MANAGER'
           AND manager.status = 'ACTIVE'
           AND manager.valid_from <= store_manager.valid_from
           AND (manager.valid_to IS NULL OR manager.valid_to >= store_manager.valid_from)
           AND manager_employee.employment_status = 'ACTIVE'
           AND manager_employee.deleted_at IS NULL
           AND manager_account.status = 'ACTIVE'
         ORDER BY manager.is_primary DESC, manager.valid_from DESC, manager.id
         LIMIT 1
    ) group_manager ON true
    WHERE store_manager_position.code = 'GENERAL_MANAGER'
      AND store_manager_org.unit_type = 'HOTEL'
      AND store_manager.status = 'ACTIVE'
      AND store_manager.manager_assignment_id IS NULL
)
UPDATE employee_position_assignment store_manager
SET manager_assignment_id = reporting.group_manager_id,
    updated_at = now()
FROM store_manager_reporting reporting
WHERE store_manager.tenant_id = reporting.tenant_id
  AND store_manager.id = reporting.store_manager_id;

-- Repair missing allocations for existing active hotel store managers.  The
-- allocation remains idempotent and future expectations are still generated by
-- the normal SLA automation worker.
INSERT INTO work_package_allocation
    (id, tenant_id, work_package_version_id, position_assignment_id,
     target_org_unit_id, allocation_source, valid_from, valid_to,
     status, allocated_by)
SELECT gen_random_uuid(), assignment.tenant_id, published.id, assignment.id,
       assignment.org_unit_id, 'SYSTEM', assignment.valid_from, assignment.valid_to,
       'ACTIVE', definition.created_by
FROM employee_position_assignment assignment
JOIN position_definition position
  ON position.tenant_id = assignment.tenant_id
 AND position.id = assignment.position_id
JOIN org_unit organization
  ON organization.tenant_id = assignment.tenant_id
 AND organization.id = assignment.org_unit_id
JOIN employee employee_row
  ON employee_row.tenant_id = assignment.tenant_id
 AND employee_row.id = assignment.employee_id
JOIN user_account account
  ON account.tenant_id = employee_row.tenant_id
 AND account.id = employee_row.account_id
JOIN work_package_definition definition
  ON definition.tenant_id = assignment.tenant_id
 AND definition.position_id = assignment.position_id
 AND definition.code = 'WP-PILOT-GM-DAILY'
 AND definition.status = 'ACTIVE'
JOIN LATERAL (
    SELECT version.id
    FROM work_package_version version
    WHERE version.tenant_id = definition.tenant_id
      AND version.work_package_definition_id = definition.id
      AND version.lifecycle_status = 'PUBLISHED'
      AND version.effective_from <= now()
      AND (version.effective_to IS NULL OR version.effective_to >= now())
    ORDER BY version.version_no DESC, version.id
    LIMIT 1
) published ON true
WHERE position.code = 'GENERAL_MANAGER'
  AND organization.unit_type = 'HOTEL'
  AND organization.status = 'ACTIVE'
  AND assignment.status = 'ACTIVE'
  AND assignment.valid_from <= (timezone((SELECT timezone FROM tenant WHERE id = assignment.tenant_id), now()))::date
  AND (assignment.valid_to IS NULL OR assignment.valid_to >= (timezone((SELECT timezone FROM tenant WHERE id = assignment.tenant_id), now()))::date)
  AND employee_row.employment_status = 'ACTIVE'
  AND employee_row.deleted_at IS NULL
  AND account.status = 'ACTIVE'
  AND EXISTS (
      SELECT 1
      FROM work_package_scope scope
      WHERE scope.tenant_id = assignment.tenant_id
        AND scope.work_package_version_id = published.id
        AND (
            scope.scope_type = 'TENANT'
            OR (scope.scope_type = 'POSITION' AND scope.position_id = assignment.position_id)
            OR (scope.scope_type = 'ORG_UNIT' AND scope.org_unit_id = assignment.org_unit_id)
            OR (scope.scope_type = 'ORG_TREE' AND EXISTS (
                SELECT 1
                FROM org_unit_closure closure
                WHERE closure.tenant_id = scope.tenant_id
                  AND closure.ancestor_id = scope.org_unit_id
                  AND closure.descendant_id = assignment.org_unit_id
            ))
            OR (scope.scope_type = 'BRAND' AND EXISTS (
                SELECT 1
                FROM hotel_profile hotel
                WHERE hotel.tenant_id = scope.tenant_id
                  AND hotel.org_unit_id = assignment.org_unit_id
                  AND hotel.brand_id = scope.brand_id
            ))
        )
  )
  AND NOT EXISTS (
      SELECT 1
      FROM work_package_allocation existing
      WHERE existing.tenant_id = assignment.tenant_id
        AND existing.work_package_version_id = published.id
        AND existing.position_assignment_id = assignment.id
        AND existing.target_org_unit_id = assignment.org_unit_id
        AND existing.status = 'ACTIVE'
  );
