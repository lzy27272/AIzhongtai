-- A verified WeCom employee must provide a unique mobile before a new
-- platform account can enter HR review. Existing pre-V45 applications stay
-- approvable; all new registration submissions populate this column.

ALTER TABLE wecom_person_onboarding
    ADD COLUMN requested_mobile VARCHAR(32);

ALTER TABLE wecom_person_onboarding
    ADD CONSTRAINT ck_wecom_onboarding_requested_mobile
        CHECK (requested_mobile IS NULL OR requested_mobile ~ '^1[3-9][0-9]{9}$');

CREATE UNIQUE INDEX ux_user_account_tenant_mobile
    ON user_account (tenant_id, mobile)
    WHERE mobile IS NOT NULL AND btrim(mobile) <> '';

CREATE UNIQUE INDEX ux_wecom_onboarding_open_mobile
    ON wecom_person_onboarding (tenant_id, requested_mobile)
    WHERE requested_mobile IS NOT NULL
      AND status IN ('WAITING_PROFILE','PENDING_APPROVAL','CONFLICT');
