-- Store-manager pilot template V2, sourced from the 2026-09-13 test workbook.
-- Keeps V46 immutable and publishes a forward-only replacement with seven routine items.

ALTER TABLE hotel_profile
    ADD COLUMN breakfast_service_enabled BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN guest_room_floor_count SMALLINT NOT NULL DEFAULT 1
        CHECK (guest_room_floor_count BETWEEN 1 AND 100);

ALTER TABLE work_package_item
    ADD COLUMN applicability_policy JSONB NOT NULL DEFAULT '{}'::jsonb,
    ADD COLUMN execution_policy JSONB NOT NULL DEFAULT '{}'::jsonb,
    ADD CONSTRAINT ck_work_package_item_applicability_policy_object
        CHECK (jsonb_typeof(applicability_policy) = 'object'),
    ADD CONSTRAINT ck_work_package_item_execution_policy_object
        CHECK (jsonb_typeof(execution_policy) = 'object');

ALTER TABLE work_expectation_reminder
    DROP CONSTRAINT work_expectation_reminder_reminder_stage_check,
    ADD CONSTRAINT work_expectation_reminder_reminder_stage_check
        CHECK (reminder_stage ~ '^[A-Z0-9_]{2,24}$');

CREATE TABLE work_expectation_delegation (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenant(id),
    work_expectation_id UUID NOT NULL,
    delegate_assignment_id UUID NOT NULL,
    delegated_by_account_id UUID NOT NULL,
    owner_resting BOOLEAN NOT NULL DEFAULT false,
    reason TEXT,
    status VARCHAR(16) NOT NULL DEFAULT 'ACTIVE'
        CHECK (status IN ('ACTIVE', 'REVOKED')),
    revoked_by_account_id UUID,
    revoked_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    CHECK (status <> 'REVOKED' OR (revoked_by_account_id IS NOT NULL AND revoked_at IS NOT NULL)),
    FOREIGN KEY (tenant_id, work_expectation_id)
        REFERENCES work_expectation (tenant_id, id) ON DELETE CASCADE,
    FOREIGN KEY (tenant_id, delegate_assignment_id)
        REFERENCES employee_position_assignment (tenant_id, id),
    FOREIGN KEY (tenant_id, delegated_by_account_id)
        REFERENCES user_account (tenant_id, id),
    FOREIGN KEY (tenant_id, revoked_by_account_id)
        REFERENCES user_account (tenant_id, id)
);

CREATE UNIQUE INDEX ux_work_expectation_delegation_active
    ON work_expectation_delegation (tenant_id, work_expectation_id)
    WHERE status = 'ACTIVE';

CREATE INDEX ix_work_expectation_delegation_delegate
    ON work_expectation_delegation (tenant_id, delegate_assignment_id, status);

ALTER TABLE work_expectation_delegation ENABLE ROW LEVEL SECURITY;
ALTER TABLE work_expectation_delegation FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON work_expectation_delegation
    USING (tenant_id = nullif(current_setting('app.tenant_id', true), '')::uuid)
    WITH CHECK (tenant_id = nullif(current_setting('app.tenant_id', true), '')::uuid);

CREATE TRIGGER trg_work_expectation_delegation_updated_at
    BEFORE UPDATE ON work_expectation_delegation
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'hotel_ai_os_app') THEN
        GRANT SELECT, INSERT, UPDATE, DELETE ON work_expectation_delegation TO hotel_ai_os_app;
    END IF;
END $$;

SELECT set_config('app.tenant_id', '10000000-0000-0000-0000-000000000001', false);

-- The seeded pilot hotel has breakfast. Other hotels retain the safe default and are
-- configured explicitly in Organization Management before automation is enabled.
UPDATE hotel_profile
SET breakfast_service_enabled = true, updated_at = now()
WHERE tenant_id = '10000000-0000-0000-0000-000000000001'
  AND org_unit_id = '12000000-0000-0000-0000-000000000003';

INSERT INTO form_definition
    (id, tenant_id, code, name, form_type, position_id)
VALUES
    ('47010000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',
     'PILOT-GM-BREAKFAST-INSPECTION','早餐厅巡查记录','INSPECTION','14000000-0000-0000-0000-000000000004'),
    ('47010000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001',
     'PILOT-GM-APPEARANCE-MORNING-V2','仪容仪表与晨会记录','INSPECTION','14000000-0000-0000-0000-000000000004'),
    ('47010000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000001',
     'PILOT-GM-PUBLIC-AREA-AM','上午公共区域巡查记录','INSPECTION','14000000-0000-0000-0000-000000000004'),
    ('47010000-0000-0000-0000-000000000004','10000000-0000-0000-0000-000000000001',
     'PILOT-GM-FRONT-DESK-COACHING','前台带教与经营事项记录','DAILY_WORK','14000000-0000-0000-0000-000000000004'),
    ('47010000-0000-0000-0000-000000000005','10000000-0000-0000-0000-000000000001',
     'PILOT-GM-ROOM-INSPECTION','客房查房记录','INSPECTION','14000000-0000-0000-0000-000000000004'),
    ('47010000-0000-0000-0000-000000000006','10000000-0000-0000-0000-000000000001',
     'PILOT-GM-PEOPLE-CUSTOMER-FORMS','人员与客户沟通表上传','INSPECTION','14000000-0000-0000-0000-000000000004'),
    ('47010000-0000-0000-0000-000000000007','10000000-0000-0000-0000-000000000001',
     'PILOT-GM-PUBLIC-AREA-PM','晚间公共区域巡查记录','INSPECTION','14000000-0000-0000-0000-000000000004')
ON CONFLICT (tenant_id, id) DO NOTHING;

INSERT INTO form_version
    (id, tenant_id, form_id, version_no, lifecycle_status, json_schema, ui_schema, published_at)
VALUES
    ('47020000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',
     '47010000-0000-0000-0000-000000000001',1,'PUBLISHED',
     '{"type":"object","required":["inspectionResult"],"properties":{"inspectionResult":{"type":"string","title":"早餐厅巡查结果"},"issueFound":{"type":"boolean","title":"是否发现问题"},"issueSummary":{"type":"string","title":"问题及处理记录"}}}'::jsonb,
     '{"evidenceCheckpoints":["display_area","table_setting","dishes","dining_area"]}'::jsonb,now()),
    ('47020000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001',
     '47010000-0000-0000-0000-000000000002',1,'PUBLISHED',
     '{"type":"object","required":["expectedAttendance","actualAttendance","appearancePassed","meetingNotes"],"properties":{"expectedAttendance":{"type":"integer","title":"应到人数","minimum":0},"actualAttendance":{"type":"integer","title":"实到人数","minimum":0},"appearancePassed":{"type":"boolean","title":"仪容仪表是否合格"},"meetingNotes":{"type":"string","title":"晨会纪要与任务分工"},"correctiveAction":{"type":"string","title":"异常及整改安排"}}}'::jsonb,
     '{"evidenceCheckpoints":["full_body","upper_body","meeting_minutes"]}'::jsonb,now()),
    ('47020000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000001',
     '47010000-0000-0000-0000-000000000003',1,'PUBLISHED',
     '{"type":"object","required":["inspectionResult","issueFound"],"properties":{"inspectionResult":{"type":"string","title":"公共区域巡查结果"},"issueFound":{"type":"boolean","title":"是否发现问题"},"issueSummary":{"type":"string","title":"问题说明"},"correctiveOwner":{"type":"string","title":"整改责任人"},"correctiveDeadline":{"type":"string","title":"整改时限"}}}'::jsonb,
     '{"evidenceCheckpoints":["lobby","front_desk_inside","front_desk_outside","floor_public_area","laundry","gym","equipment_overview","equipment_status","warehouse","welcome_tea","water_bar","popcorn_machine"]}'::jsonb,now()),
    ('47020000-0000-0000-0000-000000000004','10000000-0000-0000-0000-000000000001',
     '47010000-0000-0000-0000-000000000004',1,'PUBLISHED',
     '{"type":"object","required":["coachingSummary","complaintHandling","followUpOrders"],"properties":{"coachingSummary":{"type":"string","title":"前台带教与检查"},"complaintHandling":{"type":"string","title":"客诉处理"},"followUpOrders":{"type":"string","title":"三跟进订单分配与检查"},"specialNotes":{"type":"string","title":"特殊记录或备注"}}}'::jsonb,
     '{}'::jsonb,now()),
    ('47020000-0000-0000-0000-000000000005','10000000-0000-0000-0000-000000000001',
     '47010000-0000-0000-0000-000000000005',1,'PUBLISHED',
     '{"type":"object","required":["roomInspectionRoomNumbers","dirtyRoomNumbers","issueFound"],"properties":{"roomInspectionRoomNumbers":{"type":"array","title":"查房房号","description":"填写5个不同房号，每个房号至少上传1张对应照片，照片数量不限","minItems":5,"maxItems":5,"uniqueItems":true,"items":{"type":"string","minLength":1,"maxLength":32}},"dirtyRoomNumbers":{"type":"array","title":"走脏房房号","description":"填写2个不同房号，每个房号至少上传1张对应照片，照片数量不限","minItems":2,"maxItems":2,"uniqueItems":true,"items":{"type":"string","minLength":1,"maxLength":32}},"issueFound":{"type":"boolean","title":"是否发现问题"},"issueSummary":{"type":"string","title":"问题文字档案"},"correctiveOwner":{"type":"string","title":"整改责任人"},"correctiveDeadline":{"type":"string","title":"整改时限"}}}'::jsonb,
     '{"evidenceCheckpoints":["room_inspection","dirty_room"]}'::jsonb,now()),
    ('47020000-0000-0000-0000-000000000006','10000000-0000-0000-0000-000000000001',
     '47010000-0000-0000-0000-000000000006',1,'PUBLISHED',
     '{"type":"object","required":["employeeCommunicationOccurred","trainingOccurred","cooperationAssessmentOccurred","stayoverCommunicationOccurred","complaintOccurred"],"properties":{"employeeCommunicationOccurred":{"type":"boolean","title":"今日有员工沟通记录"},"trainingOccurred":{"type":"boolean","title":"今日有员工培训签到"},"cooperationAssessmentOccurred":{"type":"boolean","title":"今日有员工配合考核"},"stayoverCommunicationOccurred":{"type":"boolean","title":"今日有续住客户沟通"},"complaintOccurred":{"type":"boolean","title":"今日有投诉意见"},"notes":{"type":"string","title":"补充说明"}}}'::jsonb,
     '{"evidenceCheckpoints":["employee_communication","training_signin","cooperation_assessment","stayover_communication","complaint_form"]}'::jsonb,now()),
    ('47020000-0000-0000-0000-000000000007','10000000-0000-0000-0000-000000000001',
     '47010000-0000-0000-0000-000000000007',1,'PUBLISHED',
     '{"type":"object","required":["inspectionResult","issueFound"],"properties":{"inspectionResult":{"type":"string","title":"公共区域巡查结果"},"issueFound":{"type":"boolean","title":"是否发现问题"},"issueSummary":{"type":"string","title":"问题说明"},"correctiveOwner":{"type":"string","title":"整改责任人"},"correctiveDeadline":{"type":"string","title":"整改时限"}}}'::jsonb,
     '{"evidenceCheckpoints":["lobby","front_desk_inside","front_desk_outside","floor_public_area","laundry","gym","equipment_overview","equipment_status","warehouse","welcome_tea","water_bar","popcorn_machine"]}'::jsonb,now())
ON CONFLICT (tenant_id, id) DO NOTHING;

INSERT INTO work_package_version
    (id, tenant_id, work_package_definition_id, version_no, lifecycle_status, title,
     description, content_hash, created_by)
VALUES
    ('47030000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',
     '42000000-0000-0000-0000-000000000004',
     (SELECT coalesce(max(version_no),0)+1
      FROM work_package_version
      WHERE tenant_id='10000000-0000-0000-0000-000000000001'
        AND work_package_definition_id='42000000-0000-0000-0000-000000000004'),
     'DRAFT',
     '店长每日巡查与工作记录试点 V2',
     '按2026-09-13试点表执行早餐、晨会、公区、带教、查房、沟通表与晚间公区七段闭环。',
     encode(digest('STORE-MANAGER-PILOT-TEMPLATE-V2','sha256'),'hex'),
     '19000000-0000-0000-0000-000000000001')
ON CONFLICT (tenant_id, id) DO NOTHING;

INSERT INTO work_package_scope (id, tenant_id, work_package_version_id, scope_type)
VALUES ('47040000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',
        '47030000-0000-0000-0000-000000000001','TENANT')
ON CONFLICT (tenant_id, id) DO NOTHING;

INSERT INTO work_package_item
    (id, tenant_id, work_package_version_id, item_code, name, description, item_type,
     form_version_id, sort_order, required, period_type, timezone_mode,
     work_window_start, work_window_end, due_local_time, grace_minutes, weekdays,
     holiday_policy, waiver_allowed, target_granularity, review_mode,
     submission_policy, reminder_policy, report_policy, applicability_policy, execution_policy)
SELECT seed.id,'10000000-0000-0000-0000-000000000001','47030000-0000-0000-0000-000000000001',
       seed.item_code,seed.name,seed.description,'INSPECTION',seed.form_version_id,seed.sort_order,true,
       'DAY','HOTEL',seed.window_start,seed.window_end,seed.due_time,seed.grace_minutes,
       ARRAY[1,2,3,4,5,6,7]::smallint[],'INCLUDE',false,'ASSIGNMENT_ORG','MANUAL',
       seed.submission_policy,seed.reminder_policy,seed.report_policy,
       seed.applicability_policy,
       '{"sharedPerOrg":true,"allowedPositionCodes":["GENERAL_MANAGER","ASSISTANT_GENERAL_MANAGER"],"delegationAllowed":true,"delegateScope":"SAME_ORG_ACTIVE_ASSIGNMENT","ownerRestOption":true,"firstValidSubmissionWins":true}'::jsonb
FROM (VALUES
    ('47050000-0000-0000-0000-000000000001'::uuid,'GM_BREAKFAST_INSPECTION','早餐厅巡查',
     '检查明档陈列、摆餐、菜品和客户就餐区域。','47020000-0000-0000-0000-000000000001'::uuid,1,
     TIME '07:00',TIME '09:00',TIME '09:00',15,
     '{"completionStatementRequired":true,"attachmentRequired":true,"maxAttachments":20,"maxFileSizeBytes":20971520,"allowedExtensions":["jpg","jpeg","png","pdf","docx","xlsx"],"evidenceRequirements":[{"checkpointCode":"display_area","label":"明档陈列区","captureSource":"CAMERA","mediaTypes":["image/jpeg","image/png"],"minimum":1,"recommendedMaximum":1},{"checkpointCode":"table_setting","label":"摆餐区","captureSource":"CAMERA","mediaTypes":["image/jpeg","image/png"],"minimum":1,"recommendedMaximum":3},{"checkpointCode":"dishes","label":"菜品","captureSource":"CAMERA","mediaTypes":["image/jpeg","image/png"],"minimum":3,"recommendedMaximum":6},{"checkpointCode":"dining_area","label":"客户就餐区","captureSource":"CAMERA","mediaTypes":["image/jpeg","image/png"],"minimum":2,"recommendedMaximum":4}]}'::jsonb,
     '{"moments":[{"code":"R0730","kind":"REMINDER","localTime":"07:30","recipient":"EXECUTORS"},{"code":"O0915","kind":"OVERDUE","localTime":"09:15","recipient":"EXECUTORS"},{"code":"E0950","kind":"ESCALATION","localTime":"09:50","recipient":"DIRECT_MANAGER"}]}'::jsonb,
     '{"dailyReport":true,"factLabel":"早餐厅巡查","includeEvidence":true}'::jsonb,
     '{"requiresBreakfastService":true}'::jsonb),
    ('47050000-0000-0000-0000-000000000002'::uuid,'GM_APPEARANCE_MORNING_MEETING_V2','仪容仪表与晨会',
     '拍摄全体员工仪容仪表并上传晨会纪要。','47020000-0000-0000-0000-000000000002'::uuid,2,
     TIME '08:30',TIME '10:30',TIME '10:30',15,
     '{"completionStatementRequired":true,"attachmentRequired":true,"maxAttachments":10,"maxFileSizeBytes":20971520,"allowedExtensions":["jpg","jpeg","png","pdf","docx","xlsx"],"evidenceRequirements":[{"checkpointCode":"full_body","label":"全体员工全身照","captureSource":"CAMERA","mediaTypes":["image/jpeg","image/png"],"minimum":1,"recommendedMaximum":1},{"checkpointCode":"upper_body","label":"上半身妆容照","captureSource":"CAMERA","mediaTypes":["image/jpeg","image/png"],"minimum":1,"recommendedMaximum":2},{"checkpointCode":"meeting_minutes","label":"晨会纪要","captureSource":"CAMERA","mediaTypes":["image/jpeg","image/png"],"minimum":1,"recommendedMaximum":2}]}'::jsonb,
     '{"moments":[{"code":"R0930","kind":"REMINDER","localTime":"09:30","recipient":"EXECUTORS"},{"code":"O1045","kind":"OVERDUE","localTime":"10:45","recipient":"EXECUTORS"},{"code":"E1100","kind":"ESCALATION","localTime":"11:00","recipient":"DIRECT_MANAGER"}]}'::jsonb,
     '{"dailyReport":true,"factLabel":"仪容仪表与晨会","includeEvidence":true}'::jsonb,'{}'::jsonb),
    ('47050000-0000-0000-0000-000000000003'::uuid,'GM_PUBLIC_AREA_INSPECTION_AM','上午公共区域巡查',
     '逐点检查大堂、前台、楼层公区及各功能区域。','47020000-0000-0000-0000-000000000003'::uuid,3,
     TIME '09:30',TIME '11:30',TIME '11:30',15,
     '{"completionStatementRequired":true,"attachmentRequired":true,"maxAttachments":120,"maxFileSizeBytes":20971520,"allowedExtensions":["jpg","jpeg","png","pdf","docx","xlsx"],"evidenceRequirements":[{"checkpointCode":"lobby","label":"大堂","captureSource":"CAMERA","mediaTypes":["image/jpeg","image/png"],"minimum":2,"recommendedMaximum":5},{"checkpointCode":"front_desk_inside","label":"前台桌面内侧","captureSource":"CAMERA","mediaTypes":["image/jpeg","image/png"],"minimum":1},{"checkpointCode":"front_desk_outside","label":"前台桌面外侧","captureSource":"CAMERA","mediaTypes":["image/jpeg","image/png"],"minimum":1},{"checkpointCode":"floor_public_area","label":"楼层公区（每层）","captureSource":"CAMERA","mediaTypes":["image/jpeg","image/png"],"minimumPerHotelFloor":2,"recommendedMaximumPerHotelFloor":4},{"checkpointCode":"laundry","label":"洗衣房","captureSource":"CAMERA","mediaTypes":["image/jpeg","image/png"],"minimum":1},{"checkpointCode":"gym","label":"健身房","captureSource":"CAMERA","mediaTypes":["image/jpeg","image/png"],"minimum":1},{"checkpointCode":"equipment_overview","label":"设备间全景","captureSource":"CAMERA","mediaTypes":["image/jpeg","image/png"],"minimum":1},{"checkpointCode":"equipment_status","label":"设备状态","captureSource":"CAMERA","mediaTypes":["image/jpeg","image/png"],"minimum":1},{"checkpointCode":"warehouse","label":"库房","captureSource":"CAMERA","mediaTypes":["image/jpeg","image/png"],"minimum":1},{"checkpointCode":"welcome_tea","label":"欢迎茶水","captureSource":"CAMERA","mediaTypes":["image/jpeg","image/png"],"minimum":1},{"checkpointCode":"water_bar","label":"水吧区","captureSource":"CAMERA","mediaTypes":["image/jpeg","image/png"],"minimum":2,"recommendedMaximum":3},{"checkpointCode":"popcorn_machine","label":"爆米花机","captureSource":"CAMERA","mediaTypes":["image/jpeg","image/png"],"minimum":1}]}'::jsonb,
     '{"moments":[{"code":"R1000","kind":"REMINDER","localTime":"10:00","recipient":"EXECUTORS"},{"code":"O1145","kind":"OVERDUE","localTime":"11:45","recipient":"EXECUTORS"},{"code":"E1200","kind":"ESCALATION","localTime":"12:00","recipient":"DIRECT_MANAGER"}]}'::jsonb,
     '{"dailyReport":true,"factLabel":"上午公共区域巡查","includeEvidence":true}'::jsonb,'{}'::jsonb),
    ('47050000-0000-0000-0000-000000000004'::uuid,'GM_FRONT_DESK_COACHING','前台带教与经营事项跟进',
     '完成前台带教、客诉处理、三跟进订单分配和检查。','47020000-0000-0000-0000-000000000004'::uuid,4,
     TIME '11:30',TIME '14:30',TIME '14:30',0,
     '{"completionStatementRequired":true,"attachmentRequired":false,"maxAttachments":10,"maxFileSizeBytes":20971520,"allowedExtensions":["jpg","jpeg","png","pdf","docx","xlsx"],"evidenceRequirements":[]}'::jsonb,
     '{"moments":[{"code":"R1130","kind":"REMINDER","localTime":"11:30","recipient":"EXECUTORS"},{"code":"O1430","kind":"OVERDUE","localTime":"14:30","recipient":"EXECUTORS"}]}'::jsonb,
     '{"dailyReport":true,"factLabel":"前台带教与经营事项跟进","includeEvidence":true}'::jsonb,'{}'::jsonb),
    ('47050000-0000-0000-0000-000000000005'::uuid,'GM_ROOM_INSPECTION','客房查房',
     '查房5间、走脏房2间；逐房填写房号并分别上传不限张数的对应照片。','47020000-0000-0000-0000-000000000005'::uuid,5,
     TIME '14:30',TIME '17:30',TIME '17:30',0,
     '{"completionStatementRequired":true,"attachmentRequired":true,"maxAttachments":200,"attachmentCountUnlimited":true,"maxFileSizeBytes":20971520,"allowedExtensions":["jpg","jpeg","png","pdf","docx","xlsx"],"evidenceRequirements":[{"checkpointCode":"room_inspection","label":"查房","captureSource":"CAMERA","mediaTypes":["image/jpeg","image/png"],"requiredInstances":5,"instanceField":"roomInspectionRoomNumbers","instanceLabel":"房号","minimumPerInstance":1},{"checkpointCode":"dirty_room","label":"走脏房","captureSource":"CAMERA","mediaTypes":["image/jpeg","image/png"],"requiredInstances":2,"instanceField":"dirtyRoomNumbers","instanceLabel":"房号","minimumPerInstance":1}]}'::jsonb,
     '{"moments":[{"code":"R1430","kind":"REMINDER","localTime":"14:30","recipient":"EXECUTORS"},{"code":"E1630","kind":"PROGRESS","localTime":"16:30","recipient":"DIRECT_MANAGER"},{"code":"O1730","kind":"OVERDUE","localTime":"17:30","recipient":"EXECUTORS"}]}'::jsonb,
     '{"dailyReport":true,"factLabel":"客房查房","includeEvidence":true}'::jsonb,'{}'::jsonb),
    ('47050000-0000-0000-0000-000000000006'::uuid,'GM_PEOPLE_CUSTOMER_FORMS','人员与客户沟通表上传',
     '按当日实际发生情况上传人员及客户沟通记录表。','47020000-0000-0000-0000-000000000006'::uuid,6,
     TIME '17:30',TIME '18:00',TIME '18:00',0,
     '{"completionStatementRequired":true,"attachmentRequired":false,"maxAttachments":20,"maxFileSizeBytes":20971520,"allowedExtensions":["jpg","jpeg","png","pdf","docx","xlsx"],"evidenceRequirements":[{"checkpointCode":"employee_communication","label":"员工沟通记录表","captureSource":"CAMERA","mediaTypes":["image/jpeg","image/png"],"minimum":1,"requiredWhen":{"field":"employeeCommunicationOccurred","equals":true}},{"checkpointCode":"training_signin","label":"员工培训签到记录表","captureSource":"CAMERA","mediaTypes":["image/jpeg","image/png"],"minimum":1,"requiredWhen":{"field":"trainingOccurred","equals":true}},{"checkpointCode":"cooperation_assessment","label":"员工配合考核记录表","captureSource":"CAMERA","mediaTypes":["image/jpeg","image/png"],"minimum":1,"requiredWhen":{"field":"cooperationAssessmentOccurred","equals":true}},{"checkpointCode":"stayover_communication","label":"续住客户沟通表","captureSource":"CAMERA","mediaTypes":["image/jpeg","image/png"],"minimum":1,"requiredWhen":{"field":"stayoverCommunicationOccurred","equals":true}},{"checkpointCode":"complaint_form","label":"投诉意见表","captureSource":"CAMERA","mediaTypes":["image/jpeg","image/png"],"minimum":1,"requiredWhen":{"field":"complaintOccurred","equals":true}}]}'::jsonb,
     '{}'::jsonb,
     '{"dailyReport":true,"factLabel":"人员与客户沟通表","includeEvidence":true}'::jsonb,'{}'::jsonb),
    ('47050000-0000-0000-0000-000000000007'::uuid,'GM_PUBLIC_AREA_INSPECTION_PM','晚间公共区域巡查',
     '晚间再次逐点检查全部公共区域并单独留证。','47020000-0000-0000-0000-000000000007'::uuid,7,
     TIME '18:00',TIME '19:00',TIME '19:00',10,
     '{"completionStatementRequired":true,"attachmentRequired":true,"maxAttachments":120,"maxFileSizeBytes":20971520,"allowedExtensions":["jpg","jpeg","png","pdf","docx","xlsx"],"evidenceRequirements":[{"checkpointCode":"lobby","label":"大堂","captureSource":"CAMERA","mediaTypes":["image/jpeg","image/png"],"minimum":2,"recommendedMaximum":5},{"checkpointCode":"front_desk_inside","label":"前台桌面内侧","captureSource":"CAMERA","mediaTypes":["image/jpeg","image/png"],"minimum":1},{"checkpointCode":"front_desk_outside","label":"前台桌面外侧","captureSource":"CAMERA","mediaTypes":["image/jpeg","image/png"],"minimum":1},{"checkpointCode":"floor_public_area","label":"楼层公区（每层）","captureSource":"CAMERA","mediaTypes":["image/jpeg","image/png"],"minimumPerHotelFloor":2,"recommendedMaximumPerHotelFloor":4},{"checkpointCode":"laundry","label":"洗衣房","captureSource":"CAMERA","mediaTypes":["image/jpeg","image/png"],"minimum":1},{"checkpointCode":"gym","label":"健身房","captureSource":"CAMERA","mediaTypes":["image/jpeg","image/png"],"minimum":1},{"checkpointCode":"equipment_overview","label":"设备间全景","captureSource":"CAMERA","mediaTypes":["image/jpeg","image/png"],"minimum":1},{"checkpointCode":"equipment_status","label":"设备状态","captureSource":"CAMERA","mediaTypes":["image/jpeg","image/png"],"minimum":1},{"checkpointCode":"warehouse","label":"库房","captureSource":"CAMERA","mediaTypes":["image/jpeg","image/png"],"minimum":1},{"checkpointCode":"welcome_tea","label":"欢迎茶水","captureSource":"CAMERA","mediaTypes":["image/jpeg","image/png"],"minimum":1},{"checkpointCode":"water_bar","label":"水吧区","captureSource":"CAMERA","mediaTypes":["image/jpeg","image/png"],"minimum":2,"recommendedMaximum":3},{"checkpointCode":"popcorn_machine","label":"爆米花机","captureSource":"CAMERA","mediaTypes":["image/jpeg","image/png"],"minimum":1}]}'::jsonb,
     '{"moments":[{"code":"R1720","kind":"REMINDER","localTime":"17:20","recipient":"EXECUTORS"},{"code":"O1910","kind":"OVERDUE","localTime":"19:10","recipient":"EXECUTORS"},{"code":"E1930","kind":"ESCALATION","localTime":"19:30","recipient":"DIRECT_MANAGER"}]}'::jsonb,
     '{"dailyReport":true,"factLabel":"晚间公共区域巡查","includeEvidence":true}'::jsonb,'{}'::jsonb)
) AS seed(id,item_code,name,description,form_version_id,sort_order,window_start,window_end,
          due_time,grace_minutes,submission_policy,reminder_policy,report_policy,applicability_policy)
WHERE EXISTS (
    SELECT 1 FROM work_package_version
    WHERE tenant_id = '10000000-0000-0000-0000-000000000001'
      AND id = '47030000-0000-0000-0000-000000000001' AND lifecycle_status = 'DRAFT'
)
ON CONFLICT (tenant_id, id) DO NOTHING;

INSERT INTO work_package_item_standard
    (id, tenant_id, work_package_item_id, standard_version_id, usage_type, weight)
SELECT ('47060000-0000-0000-0000-' || lpad(item_no::text,12,'0'))::uuid,
       '10000000-0000-0000-0000-000000000001'::uuid,
       ('47050000-0000-0000-0000-' || lpad(item_no::text,12,'0'))::uuid,
       '41300000-0000-0000-0000-000000000001','EXECUTION',1
FROM generate_series(1,7) item_no
ON CONFLICT (tenant_id, id) DO NOTHING;

INSERT INTO work_package_item_responsibility
    (id, tenant_id, work_package_item_id, participant_type, resolver_type,
     scope_strategy, escalation_level)
SELECT ('47070000-0000-0000-0000-' || lpad(item_no::text,12,'0'))::uuid,
       '10000000-0000-0000-0000-000000000001'::uuid,
       ('47050000-0000-0000-0000-' || lpad(item_no::text,12,'0'))::uuid,
       'EXECUTOR','CURRENT_ASSIGNMENT','ASSIGNMENT_ORG',0
FROM generate_series(1,7) item_no
UNION ALL
SELECT ('47080000-0000-0000-0000-' || lpad(item_no::text,12,'0'))::uuid,
       '10000000-0000-0000-0000-000000000001'::uuid,
       ('47050000-0000-0000-0000-' || lpad(item_no::text,12,'0'))::uuid,
       'REVIEWER','DIRECT_MANAGER_ASSIGNMENT','ANCESTOR_ORG',0
FROM generate_series(1,7) item_no
ON CONFLICT (tenant_id, id) DO NOTHING;

UPDATE work_package_version
SET lifecycle_status='PUBLISHED', effective_from=now()-interval '1 minute',
    published_by='19000000-0000-0000-0000-000000000001',published_at=now(),updated_at=now()
WHERE tenant_id='10000000-0000-0000-0000-000000000001'
  AND id='47030000-0000-0000-0000-000000000001' AND lifecycle_status='DRAFT';

UPDATE work_package_allocation
SET status='REVOKED',valid_to=greatest(valid_from,current_date),updated_at=now()
WHERE tenant_id='10000000-0000-0000-0000-000000000001'
  AND work_package_version_id='46030000-0000-0000-0000-000000000001' AND status='ACTIVE';

UPDATE work_package_version
SET lifecycle_status='RETIRED',effective_to=now(),updated_at=now()
WHERE tenant_id='10000000-0000-0000-0000-000000000001'
  AND id='46030000-0000-0000-0000-000000000001' AND lifecycle_status='PUBLISHED';

UPDATE work_expectation expectation
SET status='CANCELLED',cancellation_reason='店长试点模板 V2 已启用',
    cancelled_by_account_id='19000000-0000-0000-0000-000000000001',
    cancelled_at=now(),row_version=row_version+1,updated_at=now()
FROM work_package_item item
WHERE expectation.tenant_id='10000000-0000-0000-0000-000000000001'
  AND item.tenant_id=expectation.tenant_id AND item.id=expectation.work_package_item_id
  AND item.work_package_version_id='46030000-0000-0000-0000-000000000001'
  AND expectation.business_date>=current_date
  AND expectation.status IN ('PLANNED','AVAILABLE','IN_PROGRESS','MISSED');

INSERT INTO work_package_allocation
    (id, tenant_id, work_package_version_id, position_assignment_id, target_org_unit_id,
     allocation_source, valid_from, status, allocated_by)
SELECT gen_random_uuid(),assignment.tenant_id,'47030000-0000-0000-0000-000000000001',
       assignment.id,assignment.org_unit_id,'SYSTEM',(timezone(tenant.timezone,now()))::date,
       'ACTIVE','19000000-0000-0000-0000-000000000001'
FROM employee_position_assignment assignment
JOIN position_definition position
  ON position.tenant_id=assignment.tenant_id AND position.id=assignment.position_id
JOIN employee employee_row
  ON employee_row.tenant_id=assignment.tenant_id AND employee_row.id=assignment.employee_id
JOIN user_account account
  ON account.tenant_id=employee_row.tenant_id AND account.id=employee_row.account_id
JOIN tenant ON tenant.id=assignment.tenant_id
WHERE assignment.tenant_id='10000000-0000-0000-0000-000000000001'
  AND position.code='GENERAL_MANAGER' AND assignment.status='ACTIVE'
  AND assignment.valid_from<=(timezone(tenant.timezone,now()))::date
  AND (assignment.valid_to IS NULL OR assignment.valid_to>=(timezone(tenant.timezone,now()))::date)
  AND employee_row.employment_status='ACTIVE' AND account.status='ACTIVE'
  AND NOT EXISTS (
      SELECT 1 FROM work_package_allocation existing
      WHERE existing.tenant_id=assignment.tenant_id
        AND existing.work_package_version_id='47030000-0000-0000-0000-000000000001'
        AND existing.position_assignment_id=assignment.id
        AND existing.target_org_unit_id=assignment.org_unit_id AND existing.status='ACTIVE'
  );

-- Daily report V3: seven automatic routine facts plus manual other work.
INSERT INTO daily_report_template_version
    (id, tenant_id, template_id, version_no, lifecycle_status, work_package_version_id,
     configuration, created_by)
VALUES
    ('47100000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',
     '43000000-0000-0000-0000-000000000004',3,'DRAFT',
     '47030000-0000-0000-0000-000000000001',
     '{"title":"店长每日巡查与工作记录","description":"七项日常事实自动汇总，其他工作由店长补充。","sections":[{"id":"43200000-0000-0000-0000-000000000004","sectionVersionId":"47110000-0000-0000-0000-000000000001","sectionCode":"store_manager_pilot_v2","title":"店长每日巡查与工作记录","sectionOrigin":"HQ","sectionRole":"BASE","required":true,"sortOrder":1,"items":[]}]}'::jsonb,
     '19000000-0000-0000-0000-000000000001')
ON CONFLICT (tenant_id,id) DO NOTHING;

INSERT INTO daily_report_section_version
    (id,tenant_id,section_definition_id,version_no,lifecycle_status,
     condition_expression,configuration,created_by)
VALUES
    ('47110000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',
     '43200000-0000-0000-0000-000000000004',3,'DRAFT','{}'::jsonb,
     '{"sectionCode":"store_manager_pilot_v2","title":"店长每日巡查与工作记录","description":"试点表日常证据、其他工作与规则分析。","sectionOrigin":"HQ"}'::jsonb,
     '19000000-0000-0000-0000-000000000001')
ON CONFLICT (tenant_id,id) DO NOTHING;

INSERT INTO daily_report_template_section
    (id,tenant_id,template_version_id,section_version_id,section_role,required,sort_order)
VALUES
    ('47120000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',
     '47100000-0000-0000-0000-000000000001','47110000-0000-0000-0000-000000000001','BASE',true,1)
ON CONFLICT (tenant_id,id) DO NOTHING;

INSERT INTO daily_report_template_item
    (id,tenant_id,section_version_id,item_code,label,input_type,required,
     work_package_item_id,evidence_policy,source_policy,validation_rules,option_values,sort_order)
SELECT ('47130000-0000-0000-0000-'||lpad(item_no::text,12,'0'))::uuid,
       '10000000-0000-0000-0000-000000000001'::uuid,'47110000-0000-0000-0000-000000000001'::uuid,
       item_code,label,'WORK_RECORD_REFERENCE',false,
       ('47050000-0000-0000-0000-'||lpad(item_no::text,12,'0'))::uuid,
       '{"required":true,"inheritFromWorkRecord":true}'::jsonb,
       '{"sourceType":"WORK_RECORD","required":true,"mode":"AUTO_APPROVED"}'::jsonb,
       '{}'::jsonb,'[]'::jsonb,item_no
FROM (VALUES
    (1,'breakfastInspectionFact','早餐厅巡查'),
    (2,'appearanceMorningFact','仪容仪表与晨会'),
    (3,'publicAreaAmFact','上午公共区域巡查'),
    (4,'frontDeskCoachingFact','前台带教与经营事项'),
    (5,'roomInspectionFact','客房查房'),
    (6,'peopleCustomerFormsFact','人员与客户沟通表'),
    (7,'publicAreaPmFact','晚间公共区域巡查')
) seed(item_no,item_code,label)
UNION ALL
SELECT '47130000-0000-0000-0000-000000000008'::uuid,'10000000-0000-0000-0000-000000000001'::uuid,
       '47110000-0000-0000-0000-000000000001'::uuid,'otherWork','其他工作与经营安排',
       'LONG_TEXT',false,null,'{"required":false}'::jsonb,
       '{"sourceType":"MANUAL","required":false}'::jsonb,
       '{"maxLength":4000}'::jsonb,'[]'::jsonb,8
ON CONFLICT (tenant_id,id) DO NOTHING;

UPDATE daily_report_section_version
SET lifecycle_status='PUBLISHED',content_hash=encode(digest(configuration::text,'sha256'),'hex'),
    effective_from=date_trunc('day',now()),published_by='19000000-0000-0000-0000-000000000001',
    published_at=now(),updated_at=now(),row_version=row_version+1
WHERE tenant_id='10000000-0000-0000-0000-000000000001'
  AND id='47110000-0000-0000-0000-000000000001' AND lifecycle_status='DRAFT';

UPDATE daily_report_template_version
SET lifecycle_status='PUBLISHED',content_hash=encode(digest(configuration::text,'sha256'),'hex'),
    effective_from=date_trunc('day',now()),published_by='19000000-0000-0000-0000-000000000001',
    published_at=now(),updated_at=now(),row_version=row_version+1
WHERE tenant_id='10000000-0000-0000-0000-000000000001'
  AND id='47100000-0000-0000-0000-000000000001' AND lifecycle_status='DRAFT';

UPDATE daily_report_template_assignment
SET status='REVOKED',valid_to=greatest(valid_from,current_date),row_version=row_version+1,updated_at=now()
WHERE tenant_id='10000000-0000-0000-0000-000000000001'
  AND id='46140000-0000-0000-0000-000000000001' AND status='ACTIVE';

UPDATE daily_report_template_version
SET lifecycle_status='RETIRED',effective_to=now(),updated_at=now()
WHERE tenant_id='10000000-0000-0000-0000-000000000001'
  AND id='46100000-0000-0000-0000-000000000001' AND lifecycle_status='PUBLISHED';

INSERT INTO daily_report_template_assignment
    (id,tenant_id,template_version_id,assignment_kind,scope_type,position_id,
     priority,valid_from,status,assigned_by)
VALUES
    ('47140000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',
     '47100000-0000-0000-0000-000000000001','BASE','POSITION',
     '14000000-0000-0000-0000-000000000004',900,current_date,'ACTIVE',
     '19000000-0000-0000-0000-000000000001')
ON CONFLICT (tenant_id,id) DO NOTHING;

-- The first valid shared submission wins; rejected attempts may be replaced.
CREATE UNIQUE INDEX IF NOT EXISTS uq_work_record_expectation_active_submission
    ON work_record (tenant_id,work_expectation_id)
    WHERE work_expectation_id IS NOT NULL AND status IN ('SUBMITTED','APPROVED');

INSERT INTO daily_report_delivery_policy
    (id,tenant_id,template_assignment_id,enabled,open_local_time,due_local_time,
     grace_minutes,pre_due_reminder_minutes,overdue_reminder_minutes,backfill_days,
     created_by,updated_by)
VALUES
    ('47150000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',
     '47140000-0000-0000-0000-000000000001',true,TIME '18:55',TIME '22:00',0,
     ARRAY[180,60]::integer[],ARRAY[60,65]::integer[],1,
     '19000000-0000-0000-0000-000000000001','19000000-0000-0000-0000-000000000001')
ON CONFLICT (tenant_id,id) DO NOTHING;

-- Store assistants need the same personal-work entry for shared pilot items.
INSERT INTO role_permission (tenant_id,role_id,permission_id)
SELECT role.tenant_id,role.id,permission.id
FROM app_role role
JOIN permission ON permission.code='ui.module.my-work'
WHERE role.tenant_id='10000000-0000-0000-0000-000000000001'
  AND role.code='ASSISTANT_GENERAL_MANAGER'
ON CONFLICT DO NOTHING;
