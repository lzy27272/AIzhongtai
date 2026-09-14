-- The group vice president manages stores and direct reports from the role
-- workbench. TaskTargetPolicy remains authoritative for the actual delivery
-- range; these grants only enable the existing create-and-dispatch workflow.

ALTER TABLE tenant NO FORCE ROW LEVEL SECURITY;

DO $$
DECLARE
    tenant_record RECORD;
BEGIN
    FOR tenant_record IN SELECT id FROM tenant ORDER BY id LOOP
        PERFORM set_config('app.tenant_id', tenant_record.id::text, true);

        INSERT INTO role_permission (tenant_id, role_id, permission_id)
        SELECT tenant_record.id, role.id, permission_item.id
        FROM app_role role
        CROSS JOIN permission permission_item
        WHERE role.tenant_id = tenant_record.id
          AND role.code = 'GROUP_VICE_PRESIDENT'
          AND permission_item.code IN ('task.create', 'task.dispatch')
        ON CONFLICT DO NOTHING;

        INSERT INTO position_function_profile_permission
            (tenant_id, profile_version_id, permission_id)
        SELECT tenant_record.id, version.id, permission_item.id
        FROM position_definition position_item
        JOIN position_function_profile profile
          ON profile.tenant_id = position_item.tenant_id
         AND profile.position_id = position_item.id
         AND profile.scope_type = 'GROUP'
        JOIN position_function_profile_version version
          ON version.tenant_id = profile.tenant_id
         AND version.profile_id = profile.id
         AND version.lifecycle_status IN ('PUBLISHED', 'DRAFT')
        CROSS JOIN permission permission_item
        WHERE position_item.tenant_id = tenant_record.id
          AND position_item.code = 'GROUP_VICE_PRESIDENT'
          AND permission_item.code IN ('task.create', 'task.dispatch')
          AND permission_item.delegable_to_position = true
        ON CONFLICT DO NOTHING;
    END LOOP;
END $$;

ALTER TABLE tenant FORCE ROW LEVEL SECURITY;
