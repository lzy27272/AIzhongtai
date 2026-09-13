-- Allow an employee to submit an onboarding application with the hotel chosen
-- while leaving the concrete position for the reviewer to assign.  Approved
-- rows still require a complete assignment.
DO $$
DECLARE
    assignment_constraint_name text;
BEGIN
    SELECT constraint_item.conname
      INTO assignment_constraint_name
      FROM pg_constraint constraint_item
     WHERE constraint_item.conrelid = 'wecom_person_onboarding'::regclass
       AND constraint_item.contype = 'c'
       AND pg_get_constraintdef(constraint_item.oid) LIKE '%PENDING_APPROVAL%'
       AND pg_get_constraintdef(constraint_item.oid) LIKE '%requested_org_unit_id%'
       AND pg_get_constraintdef(constraint_item.oid) LIKE '%requested_position_id%'
     ORDER BY constraint_item.conname
     LIMIT 1;

    IF assignment_constraint_name IS NULL THEN
        RAISE EXCEPTION 'wecom onboarding assignment state constraint was not found';
    END IF;

    EXECUTE format(
        'ALTER TABLE wecom_person_onboarding DROP CONSTRAINT %I',
        assignment_constraint_name
    );
END $$;

ALTER TABLE wecom_person_onboarding
    ADD CONSTRAINT ck_wecom_onboarding_review_assignment
    CHECK (
        status NOT IN ('PENDING_APPROVAL', 'CONFLICT', 'APPROVED')
        OR (
            requested_org_unit_id IS NOT NULL
            AND identity_verified_at IS NOT NULL
            AND profile_submitted_at IS NOT NULL
            AND directory_status = 'ACTIVE'
            AND (status <> 'APPROVED' OR requested_position_id IS NOT NULL)
        )
    );

COMMENT ON CONSTRAINT ck_wecom_onboarding_review_assignment
    ON wecom_person_onboarding IS
    'Pending review may defer position selection; approval requires a complete assignment.';
