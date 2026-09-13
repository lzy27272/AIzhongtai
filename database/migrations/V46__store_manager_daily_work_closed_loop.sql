-- Store-manager daily-work closed loop V1.
-- Adds immutable template policy, reminder idempotency and trustworthy evidence metadata,
-- then publishes the first two time-boxed GENERAL_MANAGER routines.

ALTER TABLE work_package_item
    ADD COLUMN reminder_policy JSONB NOT NULL DEFAULT '{}'::jsonb,
    ADD COLUMN report_policy JSONB NOT NULL DEFAULT '{}'::jsonb;

ALTER TABLE work_package_item
    ADD CONSTRAINT ck_work_package_item_reminder_policy_object
        CHECK (jsonb_typeof(reminder_policy) = 'object'),
    ADD CONSTRAINT ck_work_package_item_report_policy_object
        CHECK (jsonb_typeof(report_policy) = 'object');

ALTER TABLE attachment
    ADD COLUMN capture_source VARCHAR(24) NOT NULL DEFAULT 'FILE_PICKER'
        CHECK (capture_source IN ('FILE_PICKER', 'CAMERA', 'SYSTEM')),
    ADD COLUMN checkpoint_code VARCHAR(80),
    ADD COLUMN captured_at_client TIMESTAMPTZ,
    ADD COLUMN received_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    ADD COLUMN source_sha256 CHAR(64),
    ADD COLUMN evidence_metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    ADD CONSTRAINT ck_attachment_evidence_metadata_object
        CHECK (jsonb_typeof(evidence_metadata) = 'object');

CREATE INDEX ix_attachment_evidence_checkpoint
    ON attachment (tenant_id, work_record_id, checkpoint_code, capture_source)
    WHERE scan_status <> 'REJECTED';

CREATE TABLE work_expectation_reminder (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenant(id),
    work_expectation_id UUID NOT NULL,
    reminder_stage VARCHAR(24) NOT NULL
        CHECK (reminder_stage IN ('PRE_OPEN', 'DUE_SOON', 'OVERDUE', 'ESCALATION')),
    scheduled_at TIMESTAMPTZ NOT NULL,
    recipient_account_id UUID NOT NULL,
    recipient_assignment_id UUID,
    notification_id UUID,
    status VARCHAR(24) NOT NULL DEFAULT 'PENDING'
        CHECK (status IN ('PENDING', 'SENT', 'CANCELLED', 'FAILED')),
    sent_at TIMESTAMPTZ,
    failure_reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, work_expectation_id, reminder_stage, recipient_account_id),
    CHECK (status <> 'SENT' OR (sent_at IS NOT NULL AND notification_id IS NOT NULL)),
    CHECK (status <> 'FAILED' OR failure_reason IS NOT NULL),
    FOREIGN KEY (tenant_id, work_expectation_id) REFERENCES work_expectation (tenant_id, id) ON DELETE CASCADE,
    FOREIGN KEY (tenant_id, recipient_account_id) REFERENCES user_account (tenant_id, id),
    FOREIGN KEY (tenant_id, recipient_assignment_id)
        REFERENCES employee_position_assignment (tenant_id, id),
    FOREIGN KEY (tenant_id, notification_id) REFERENCES notification (tenant_id, id)
);

CREATE INDEX ix_work_expectation_reminder_due
    ON work_expectation_reminder (tenant_id, scheduled_at, work_expectation_id)
    WHERE status = 'PENDING';

ALTER TABLE work_expectation_reminder ENABLE ROW LEVEL SECURITY;
ALTER TABLE work_expectation_reminder FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON work_expectation_reminder
    USING (tenant_id = nullif(current_setting('app.tenant_id', true), '')::uuid)
    WITH CHECK (tenant_id = nullif(current_setting('app.tenant_id', true), '')::uuid);

CREATE TRIGGER trg_work_expectation_reminder_updated_at
    BEFORE UPDATE ON work_expectation_reminder
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'hotel_ai_os_app') THEN
        GRANT SELECT, INSERT, UPDATE, DELETE ON work_expectation_reminder TO hotel_ai_os_app;
    END IF;
END $$;

SELECT set_config('app.tenant_id', '10000000-0000-0000-0000-000000000001', false);

-- The existing CEO account is also the group general manager. Materialize that
-- business assignment so store-manager reviews resolve to a real direct manager
-- instead of relying on the account's administrative role alone.
INSERT INTO employee
    (id, tenant_id, account_id, employee_no, name, mobile, hired_on)
SELECT
    '46160000-0000-0000-0000-000000000001',
    account.tenant_id,
    account.id,
    'E-GGM-001',
    account.display_name,
    account.mobile,
    current_date
FROM user_account account
WHERE account.tenant_id = '10000000-0000-0000-0000-000000000001'
  AND account.id = '19000000-0000-0000-0000-000000000001'
  AND NOT EXISTS (
      SELECT 1 FROM employee existing
      WHERE existing.tenant_id = account.tenant_id
        AND existing.account_id = account.id
        AND existing.deleted_at IS NULL
  )
ON CONFLICT (tenant_id, employee_no) DO NOTHING;

INSERT INTO employee_position_assignment
    (id, tenant_id, employee_id, org_unit_id, position_id, is_primary,
     valid_from, status)
SELECT
    '46170000-0000-0000-0000-000000000001',
    employee_row.tenant_id,
    employee_row.id,
    '12000000-0000-0000-0000-000000000001',
    position.id,
    NOT EXISTS (
        SELECT 1 FROM employee_position_assignment primary_assignment
        WHERE primary_assignment.tenant_id = employee_row.tenant_id
          AND primary_assignment.employee_id = employee_row.id
          AND primary_assignment.is_primary = true
          AND primary_assignment.status = 'ACTIVE'
          AND primary_assignment.valid_to IS NULL
    ),
    current_date,
    'ACTIVE'
FROM employee employee_row
JOIN position_definition position
  ON position.tenant_id = employee_row.tenant_id
 AND position.code = 'GROUP_GENERAL_MANAGER'
WHERE employee_row.tenant_id = '10000000-0000-0000-0000-000000000001'
  AND employee_row.account_id = '19000000-0000-0000-0000-000000000001'
  AND employee_row.deleted_at IS NULL
  AND NOT EXISTS (
      SELECT 1
      FROM employee_position_assignment existing
      JOIN position_definition existing_position
        ON existing_position.tenant_id = existing.tenant_id
       AND existing_position.id = existing.position_id
      WHERE existing.tenant_id = employee_row.tenant_id
        AND existing.employee_id = employee_row.id
        AND existing_position.code = 'GROUP_GENERAL_MANAGER'
        AND existing.status = 'ACTIVE'
        AND existing.valid_from <= current_date
        AND (existing.valid_to IS NULL OR existing.valid_to >= current_date)
  )
ON CONFLICT (tenant_id, id) DO NOTHING;

UPDATE employee_position_assignment store_manager
SET manager_assignment_id = group_manager.id,
    updated_at = now()
FROM (
    SELECT assignment.id
    FROM employee_position_assignment assignment
    JOIN employee employee_row
      ON employee_row.tenant_id = assignment.tenant_id
     AND employee_row.id = assignment.employee_id
    JOIN position_definition position
      ON position.tenant_id = assignment.tenant_id
     AND position.id = assignment.position_id
    WHERE assignment.tenant_id = '10000000-0000-0000-0000-000000000001'
      AND employee_row.account_id = '19000000-0000-0000-0000-000000000001'
      AND employee_row.deleted_at IS NULL
      AND position.code = 'GROUP_GENERAL_MANAGER'
      AND assignment.status = 'ACTIVE'
      AND assignment.valid_from <= current_date
      AND (assignment.valid_to IS NULL OR assignment.valid_to >= current_date)
    ORDER BY assignment.is_primary DESC, assignment.valid_from DESC, assignment.id
    LIMIT 1
) group_manager
WHERE store_manager.tenant_id = '10000000-0000-0000-0000-000000000001'
  AND store_manager.id = '19200000-0000-0000-0000-000000000001'
  AND store_manager.manager_assignment_id IS NULL;

-- Store-manager routines are executed from My Work. Repair the published navigation
-- grant only where the profile already grants work submission; custom profiles that
-- intentionally deny execution remain unchanged.
INSERT INTO position_function_profile_permission
    (tenant_id, profile_version_id, permission_id)
SELECT profile.tenant_id, version.id, module_permission.id
FROM position_function_profile profile
JOIN position_definition position
  ON position.tenant_id = profile.tenant_id AND position.id = profile.position_id
JOIN position_function_profile_version version
  ON version.tenant_id = profile.tenant_id AND version.profile_id = profile.id
JOIN permission module_permission
  ON module_permission.code = 'ui.module.my-work'
WHERE profile.tenant_id = '10000000-0000-0000-0000-000000000001'
  AND position.code = 'GENERAL_MANAGER'
  AND version.lifecycle_status IN ('DRAFT', 'PUBLISHED')
  AND EXISTS (
      SELECT 1
      FROM position_function_profile_permission action_grant
      JOIN permission action_permission ON action_permission.id = action_grant.permission_id
      WHERE action_grant.tenant_id = version.tenant_id
        AND action_grant.profile_version_id = version.id
        AND action_permission.code IN ('work.submit', 'work-record.submit')
  )
ON CONFLICT DO NOTHING;

INSERT INTO role_permission (tenant_id, role_id, permission_id)
SELECT role.tenant_id, role.id, module_permission.id
FROM app_role role
JOIN permission module_permission ON module_permission.code = 'ui.module.my-work'
WHERE role.tenant_id = '10000000-0000-0000-0000-000000000001'
  AND role.code = 'GENERAL_MANAGER'
ON CONFLICT DO NOTHING;

-- V2 forms deliberately separate the two routines so each evidence contract is independently enforceable.
INSERT INTO form_definition
    (id, tenant_id, code, name, form_type, position_id)
VALUES
    ('46010000-0000-0000-0000-000000000001',
     '10000000-0000-0000-0000-000000000001',
     'PILOT-GM-APPEARANCE-MORNING-MEETING',
     '店长仪容仪表与晨会记录', 'INSPECTION',
     '14000000-0000-0000-0000-000000000004'),
    ('46010000-0000-0000-0000-000000000002',
     '10000000-0000-0000-0000-000000000001',
     'PILOT-GM-PUBLIC-AREA-INSPECTION',
     '店长公共区域巡检记录', 'INSPECTION',
     '14000000-0000-0000-0000-000000000004')
ON CONFLICT (tenant_id, id) DO NOTHING;

INSERT INTO form_version
    (id, tenant_id, form_id, version_no, lifecycle_status, json_schema, ui_schema, published_at)
VALUES
    ('46020000-0000-0000-0000-000000000001',
     '10000000-0000-0000-0000-000000000001',
     '46010000-0000-0000-0000-000000000001', 1, 'PUBLISHED',
     '{"type":"object","required":["expectedAttendance","actualAttendance","appearancePassed","meetingTopic","meetingNotes"],"properties":{"expectedAttendance":{"type":"integer","title":"应到人数","minimum":0},"actualAttendance":{"type":"integer","title":"实到人数","minimum":0},"appearancePassed":{"type":"boolean","title":"仪容仪表是否合格"},"meetingTopic":{"type":"string","title":"晨会主题"},"meetingNotes":{"type":"string","title":"晨会记录与任务分工"},"correctiveAction":{"type":"string","title":"异常及整改安排"}}}'::jsonb,
     '{"evidenceCheckpoints":["appearance"]}'::jsonb, now()),
    ('46020000-0000-0000-0000-000000000002',
     '10000000-0000-0000-0000-000000000001',
     '46010000-0000-0000-0000-000000000002', 1, 'PUBLISHED',
     '{"type":"object","required":["lobbyStatus","equipmentRoomStatus","warehouseStatus","issueFound"],"properties":{"lobbyStatus":{"type":"string","title":"大堂检查结果"},"equipmentRoomStatus":{"type":"string","title":"设备间检查结果"},"warehouseStatus":{"type":"string","title":"库房检查结果"},"issueFound":{"type":"boolean","title":"是否发现问题"},"issueSummary":{"type":"string","title":"问题说明"},"correctiveOwner":{"type":"string","title":"整改责任人"},"correctiveDeadline":{"type":"string","title":"整改时限"}}}'::jsonb,
     '{"evidenceCheckpoints":["lobby","equipment_room","warehouse"]}'::jsonb, now())
ON CONFLICT (tenant_id, id) DO NOTHING;

-- Existing definition is retained; its published V1 remains immutable and is retired below.
INSERT INTO work_package_version
    (id, tenant_id, work_package_definition_id, version_no, lifecycle_status, title,
     description, content_hash, created_by)
VALUES
    ('46030000-0000-0000-0000-000000000001',
     '10000000-0000-0000-0000-000000000001',
     '42000000-0000-0000-0000-000000000004', 2, 'DRAFT',
     '店长每日工作闭环 V2',
     '仪容仪表与晨会、公共区域巡检的分时督办和证据闭环。',
     encode(digest('STORE-MANAGER-DAILY-CLOSED-LOOP-V1', 'sha256'), 'hex'),
     '19000000-0000-0000-0000-000000000001')
ON CONFLICT (tenant_id, id) DO NOTHING;

INSERT INTO work_package_scope (id, tenant_id, work_package_version_id, scope_type)
SELECT '46040000-0000-0000-0000-000000000001',
       '10000000-0000-0000-0000-000000000001',
       '46030000-0000-0000-0000-000000000001', 'TENANT'
WHERE EXISTS (
    SELECT 1 FROM work_package_version
    WHERE tenant_id = '10000000-0000-0000-0000-000000000001'
      AND id = '46030000-0000-0000-0000-000000000001'
      AND lifecycle_status = 'DRAFT'
)
ON CONFLICT (tenant_id, id) DO NOTHING;

INSERT INTO work_package_item
    (id, tenant_id, work_package_version_id, item_code, name, description, item_type,
     form_version_id, sort_order, required, period_type, timezone_mode,
     work_window_start, work_window_end, due_local_time, grace_minutes, weekdays,
     holiday_policy, waiver_allowed, target_granularity, review_mode,
     submission_policy, reminder_policy, report_policy)
SELECT seed.id, '10000000-0000-0000-0000-000000000001',
       '46030000-0000-0000-0000-000000000001', seed.item_code, seed.name,
       seed.description, 'INSPECTION', seed.form_version_id, seed.sort_order, true,
       'DAY', 'HOTEL', seed.window_start, seed.window_end, seed.due_time, 5,
       ARRAY[1,2,3,4,5,6,7]::smallint[], 'INCLUDE', false,
       'ASSIGNMENT_ORG', 'MANUAL', seed.submission_policy, seed.reminder_policy,
       seed.report_policy
FROM (VALUES
    ('46050000-0000-0000-0000-000000000001'::uuid,
     'GM_APPEARANCE_MORNING_MEETING', '仪容仪表检查与晨会',
     '拍摄员工仪容仪表，完成晨会并记录主题、分工和异常整改。',
     '46020000-0000-0000-0000-000000000001'::uuid, 1,
     TIME '08:30', TIME '09:00', TIME '09:00',
     '{"completionStatementRequired":true,"exceptionStatementRequired":false,"nextActionRequired":false,"attachmentRequired":true,"maxAttachments":10,"maxFileSizeBytes":20971520,"allowedExtensions":["jpg","jpeg","png","pdf","docx","xlsx"],"evidenceRequirements":[{"checkpointCode":"appearance","label":"仪容仪表现场照片","captureSource":"CAMERA","mediaTypes":["image/jpeg","image/png"],"minimum":1}]}'::jsonb,
     '{"preOpenMinutes":10,"dueSoonMinutes":10,"overdueMinutes":5,"escalationMinutes":15}'::jsonb,
     '{"dailyReport":true,"factLabel":"今日晨会及仪容仪表检查","includeEvidence":true}'::jsonb),
    ('46050000-0000-0000-0000-000000000002'::uuid,
     'GM_PUBLIC_AREA_INSPECTION', '公共区域巡检',
     '巡视大堂、设备间和库房，逐点拍照并记录问题、责任人与整改时限。',
     '46020000-0000-0000-0000-000000000002'::uuid, 2,
     TIME '10:00', TIME '11:00', TIME '11:00',
     '{"completionStatementRequired":true,"exceptionStatementRequired":false,"nextActionRequired":false,"attachmentRequired":true,"maxAttachments":10,"maxFileSizeBytes":20971520,"allowedExtensions":["jpg","jpeg","png","pdf","docx","xlsx"],"evidenceRequirements":[{"checkpointCode":"lobby","label":"大堂现场照片","captureSource":"CAMERA","mediaTypes":["image/jpeg","image/png"],"minimum":1},{"checkpointCode":"equipment_room","label":"设备间现场照片","captureSource":"CAMERA","mediaTypes":["image/jpeg","image/png"],"minimum":1},{"checkpointCode":"warehouse","label":"库房现场照片","captureSource":"CAMERA","mediaTypes":["image/jpeg","image/png"],"minimum":1}]}'::jsonb,
     '{"preOpenMinutes":10,"dueSoonMinutes":10,"overdueMinutes":5,"escalationMinutes":15}'::jsonb,
     '{"dailyReport":true,"factLabel":"今日公共区域巡检","includeEvidence":true}'::jsonb)
) AS seed(id, item_code, name, description, form_version_id, sort_order,
          window_start, window_end, due_time, submission_policy, reminder_policy, report_policy)
WHERE EXISTS (
    SELECT 1 FROM work_package_version
    WHERE tenant_id = '10000000-0000-0000-0000-000000000001'
      AND id = '46030000-0000-0000-0000-000000000001'
      AND lifecycle_status = 'DRAFT'
)
ON CONFLICT (tenant_id, id) DO NOTHING;

INSERT INTO work_package_item_standard
    (id, tenant_id, work_package_item_id, standard_version_id, usage_type, weight)
VALUES
    ('46060000-0000-0000-0000-000000000001',
     '10000000-0000-0000-0000-000000000001',
     '46050000-0000-0000-0000-000000000001',
     '41300000-0000-0000-0000-000000000001', 'EXECUTION', 1),
    ('46060000-0000-0000-0000-000000000002',
     '10000000-0000-0000-0000-000000000001',
     '46050000-0000-0000-0000-000000000002',
     '41300000-0000-0000-0000-000000000001', 'EXECUTION', 1)
ON CONFLICT (tenant_id, id) DO NOTHING;

INSERT INTO work_package_item_responsibility
    (id, tenant_id, work_package_item_id, participant_type, resolver_type,
     scope_strategy, escalation_level)
VALUES
    ('46070000-0000-0000-0000-000000000001',
     '10000000-0000-0000-0000-000000000001',
     '46050000-0000-0000-0000-000000000001',
     'EXECUTOR', 'CURRENT_ASSIGNMENT', 'ASSIGNMENT_ORG', 0),
    ('46070000-0000-0000-0000-000000000002',
     '10000000-0000-0000-0000-000000000001',
     '46050000-0000-0000-0000-000000000002',
     'EXECUTOR', 'CURRENT_ASSIGNMENT', 'ASSIGNMENT_ORG', 0),
    ('46080000-0000-0000-0000-000000000001',
     '10000000-0000-0000-0000-000000000001',
     '46050000-0000-0000-0000-000000000001',
     'REVIEWER', 'DIRECT_MANAGER_ASSIGNMENT', 'ANCESTOR_ORG', 0),
    ('46080000-0000-0000-0000-000000000002',
     '10000000-0000-0000-0000-000000000001',
     '46050000-0000-0000-0000-000000000002',
     'REVIEWER', 'DIRECT_MANAGER_ASSIGNMENT', 'ANCESTOR_ORG', 0)
ON CONFLICT (tenant_id, id) DO NOTHING;

UPDATE work_package_version
SET lifecycle_status = 'PUBLISHED', effective_from = now() - interval '1 minute',
    published_by = '19000000-0000-0000-0000-000000000001', published_at = now(),
    updated_at = now()
WHERE tenant_id = '10000000-0000-0000-0000-000000000001'
  AND id = '46030000-0000-0000-0000-000000000001'
  AND lifecycle_status = 'DRAFT';

-- Stop the single legacy end-of-day GM item before allocating V2.
UPDATE work_package_allocation
SET status = 'REVOKED', valid_to = greatest(valid_from, current_date), updated_at = now()
WHERE tenant_id = '10000000-0000-0000-0000-000000000001'
  AND work_package_version_id = '42100000-0000-0000-0000-000000000004'
  AND status = 'ACTIVE';

UPDATE work_package_version
SET lifecycle_status = 'RETIRED', effective_to = now(), updated_at = now()
WHERE tenant_id = '10000000-0000-0000-0000-000000000001'
  AND id = '42100000-0000-0000-0000-000000000004'
  AND lifecycle_status = 'PUBLISHED';

UPDATE work_expectation
SET status = 'CANCELLED', cancellation_reason = '店长每日工作闭环 V2 已启用',
    cancelled_by_account_id = '19000000-0000-0000-0000-000000000001',
    cancelled_at = now(), row_version = row_version + 1, updated_at = now()
WHERE tenant_id = '10000000-0000-0000-0000-000000000001'
  AND work_package_item_id = '42300000-0000-0000-0000-000000000004'
  AND business_date >= current_date
  AND status IN ('PLANNED', 'AVAILABLE', 'IN_PROGRESS', 'MISSED');

INSERT INTO work_package_allocation
    (id, tenant_id, work_package_version_id, position_assignment_id, target_org_unit_id,
     allocation_source, valid_from, status, allocated_by)
SELECT gen_random_uuid(), assignment.tenant_id,
       '46030000-0000-0000-0000-000000000001', assignment.id, assignment.org_unit_id,
       'SYSTEM', (timezone(tenant.timezone, now()))::date, 'ACTIVE',
       '19000000-0000-0000-0000-000000000001'
FROM employee_position_assignment assignment
JOIN position_definition position
  ON position.tenant_id = assignment.tenant_id AND position.id = assignment.position_id
JOIN employee employee_row
  ON employee_row.tenant_id = assignment.tenant_id AND employee_row.id = assignment.employee_id
JOIN user_account account
  ON account.tenant_id = employee_row.tenant_id AND account.id = employee_row.account_id
JOIN tenant ON tenant.id = assignment.tenant_id
WHERE assignment.tenant_id = '10000000-0000-0000-0000-000000000001'
  AND position.code = 'GENERAL_MANAGER'
  AND assignment.status = 'ACTIVE'
  AND assignment.valid_from <= (timezone(tenant.timezone, now()))::date
  AND (assignment.valid_to IS NULL OR assignment.valid_to >= (timezone(tenant.timezone, now()))::date)
  AND employee_row.employment_status = 'ACTIVE'
  AND account.status = 'ACTIVE'
  AND NOT EXISTS (
      SELECT 1 FROM work_package_allocation existing
      WHERE existing.tenant_id = assignment.tenant_id
        AND existing.work_package_version_id = '46030000-0000-0000-0000-000000000001'
        AND existing.position_assignment_id = assignment.id
        AND existing.target_org_unit_id = assignment.org_unit_id
        AND existing.status = 'ACTIVE'
  );

-- Instances are intentionally not seeded in a migration. The tenant-scoped scheduler
-- materializes them after startup so deployment time cannot create already-overdue work.

-- Store-manager daily report V2: two system-projected facts plus one manual "other work" item.
INSERT INTO daily_report_template_version
    (id, tenant_id, template_id, version_no, lifecycle_status, work_package_version_id,
     configuration, created_by)
VALUES
    ('46100000-0000-0000-0000-000000000001',
     '10000000-0000-0000-0000-000000000001',
     '43000000-0000-0000-0000-000000000004', 2, 'DRAFT',
     '46030000-0000-0000-0000-000000000001',
     '{"title":"店长每日工作闭环日报","description":"日常工作事实自动汇总，其他工作由店长补充。","sections":[{"id":"43200000-0000-0000-0000-000000000004","sectionVersionId":"46110000-0000-0000-0000-000000000001","sectionCode":"store_manager_daily_closed_loop","title":"店长每日工作闭环","description":"日常工作证据、其他工作与规则分析。","sectionOrigin":"HQ","applicabilityCondition":{},"sectionRole":"BASE","required":true,"sortOrder":1,"items":[{"id":"46130000-0000-0000-0000-000000000001","itemCode":"morningMeetingFact","label":"仪容仪表与晨会","valueType":"WORK_RECORD_REFERENCE","required":true,"workPackageItemId":"46050000-0000-0000-0000-000000000001","dataSourceType":"WORK_RECORD","dataSourceConfig":{"required":true,"mode":"AUTO_APPROVED"},"evidencePolicy":{"required":true,"inheritFromWorkRecord":true},"validationRules":{},"optionValues":[],"sortOrder":1},{"id":"46130000-0000-0000-0000-000000000002","itemCode":"publicAreaInspectionFact","label":"公共区域巡检","valueType":"WORK_RECORD_REFERENCE","required":true,"workPackageItemId":"46050000-0000-0000-0000-000000000002","dataSourceType":"WORK_RECORD","dataSourceConfig":{"required":true,"mode":"AUTO_APPROVED"},"evidencePolicy":{"required":true,"inheritFromWorkRecord":true},"validationRules":{},"optionValues":[],"sortOrder":2},{"id":"46130000-0000-0000-0000-000000000003","itemCode":"otherWork","label":"其他工作与经营安排","valueType":"LONG_TEXT","required":false,"dataSourceType":"MANUAL","dataSourceConfig":{"required":false},"evidencePolicy":{"required":false},"validationRules":{"maxLength":4000},"optionValues":[],"sortOrder":3}]}]}'::jsonb,
     '19000000-0000-0000-0000-000000000001')
ON CONFLICT (tenant_id, id) DO NOTHING;

INSERT INTO daily_report_section_version
    (id, tenant_id, section_definition_id, version_no, lifecycle_status,
     condition_expression, configuration, created_by)
VALUES
    ('46110000-0000-0000-0000-000000000001',
     '10000000-0000-0000-0000-000000000001',
     '43200000-0000-0000-0000-000000000004', 2, 'DRAFT', '{}'::jsonb,
     '{"sectionCode":"store_manager_daily_closed_loop","title":"店长每日工作闭环","description":"日常工作证据、其他工作与规则分析。","sectionOrigin":"HQ"}'::jsonb,
     '19000000-0000-0000-0000-000000000001')
ON CONFLICT (tenant_id, id) DO NOTHING;

INSERT INTO daily_report_template_section
    (id, tenant_id, template_version_id, section_version_id, section_role, required, sort_order)
VALUES
    ('46120000-0000-0000-0000-000000000001',
     '10000000-0000-0000-0000-000000000001',
     '46100000-0000-0000-0000-000000000001',
     '46110000-0000-0000-0000-000000000001', 'BASE', true, 1)
ON CONFLICT (tenant_id, id) DO NOTHING;

INSERT INTO daily_report_template_item
    (id, tenant_id, section_version_id, item_code, label, input_type, required,
     work_package_item_id, evidence_policy, source_policy, validation_rules,
     option_values, sort_order)
VALUES
    ('46130000-0000-0000-0000-000000000001',
     '10000000-0000-0000-0000-000000000001',
     '46110000-0000-0000-0000-000000000001',
     'morningMeetingFact', '仪容仪表与晨会', 'WORK_RECORD_REFERENCE', true,
     '46050000-0000-0000-0000-000000000001',
     '{"required":true,"inheritFromWorkRecord":true}'::jsonb,
     '{"sourceType":"WORK_RECORD","required":true,"mode":"AUTO_APPROVED"}'::jsonb,
     '{}'::jsonb, '[]'::jsonb, 1),
    ('46130000-0000-0000-0000-000000000002',
     '10000000-0000-0000-0000-000000000001',
     '46110000-0000-0000-0000-000000000001',
     'publicAreaInspectionFact', '公共区域巡检', 'WORK_RECORD_REFERENCE', true,
     '46050000-0000-0000-0000-000000000002',
     '{"required":true,"inheritFromWorkRecord":true}'::jsonb,
     '{"sourceType":"WORK_RECORD","required":true,"mode":"AUTO_APPROVED"}'::jsonb,
     '{}'::jsonb, '[]'::jsonb, 2),
    ('46130000-0000-0000-0000-000000000003',
     '10000000-0000-0000-0000-000000000001',
     '46110000-0000-0000-0000-000000000001',
     'otherWork', '其他工作与经营安排', 'LONG_TEXT', false, null,
     '{"required":false}'::jsonb,
     '{"sourceType":"MANUAL","required":false}'::jsonb,
     '{"maxLength":4000}'::jsonb, '[]'::jsonb, 3)
ON CONFLICT (tenant_id, id) DO NOTHING;

UPDATE daily_report_section_version
SET lifecycle_status = 'PUBLISHED',
    content_hash = encode(digest(configuration::text, 'sha256'), 'hex'),
    effective_from = date_trunc('day', now()),
    published_by = '19000000-0000-0000-0000-000000000001',
    published_at = now(), updated_at = now(), row_version = row_version + 1
WHERE tenant_id = '10000000-0000-0000-0000-000000000001'
  AND id = '46110000-0000-0000-0000-000000000001'
  AND lifecycle_status = 'DRAFT';

UPDATE daily_report_template_version
SET lifecycle_status = 'PUBLISHED',
    content_hash = encode(digest(configuration::text, 'sha256'), 'hex'),
    effective_from = date_trunc('day', now()),
    published_by = '19000000-0000-0000-0000-000000000001',
    published_at = now(), updated_at = now(), row_version = row_version + 1
WHERE tenant_id = '10000000-0000-0000-0000-000000000001'
  AND id = '46100000-0000-0000-0000-000000000001'
  AND lifecycle_status = 'DRAFT';

UPDATE daily_report_template_assignment
SET status = 'REVOKED', valid_to = greatest(valid_from, current_date),
    row_version = row_version + 1, updated_at = now()
WHERE tenant_id = '10000000-0000-0000-0000-000000000001'
  AND id = '43600000-0000-0000-0000-000000000004'
  AND status = 'ACTIVE';

UPDATE daily_report_template_version
SET lifecycle_status = 'RETIRED', effective_to = now(), updated_at = now()
WHERE tenant_id = '10000000-0000-0000-0000-000000000001'
  AND id = '43100000-0000-0000-0000-000000000004'
  AND lifecycle_status = 'PUBLISHED';

INSERT INTO daily_report_template_assignment
    (id, tenant_id, template_version_id, assignment_kind, scope_type,
     position_id, priority, valid_from, status, assigned_by)
VALUES
    ('46140000-0000-0000-0000-000000000001',
     '10000000-0000-0000-0000-000000000001',
     '46100000-0000-0000-0000-000000000001', 'BASE', 'POSITION',
     '14000000-0000-0000-0000-000000000004', 800, current_date, 'ACTIVE',
     '19000000-0000-0000-0000-000000000001')
ON CONFLICT (tenant_id, id) DO NOTHING;

INSERT INTO daily_report_delivery_policy
    (id, tenant_id, template_assignment_id, enabled, open_local_time,
     due_local_time, grace_minutes, pre_due_reminder_minutes,
     overdue_reminder_minutes, backfill_days, created_by, updated_by)
VALUES
    ('46150000-0000-0000-0000-000000000001',
     '10000000-0000-0000-0000-000000000001',
     '46140000-0000-0000-0000-000000000001', true,
     TIME '20:00', TIME '23:00', 30, ARRAY[30]::integer[], ARRAY[0,30]::integer[], 1,
     '19000000-0000-0000-0000-000000000001',
     '19000000-0000-0000-0000-000000000001')
ON CONFLICT (tenant_id, id) DO NOTHING;
