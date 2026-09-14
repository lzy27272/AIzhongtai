-- Separate a reusable onboarding invitation from the employee-specific
-- application created by each scan. The shared token remains valid until its
-- fixed expiry; OAuth, identity, profile and approval state stay isolated per
-- employee application.

CREATE TABLE wecom_open_onboarding_invitation (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenant(id),
    corp_id VARCHAR(128) NOT NULL,
    token_hash CHAR(64) NOT NULL,
    issued_at TIMESTAMPTZ NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    created_by UUID NOT NULL,
    row_version BIGINT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, token_hash),
    FOREIGN KEY (tenant_id, created_by) REFERENCES user_account (tenant_id, id),
    CHECK (token_hash ~ '^[0-9a-f]{64}$'),
    CHECK (expires_at > issued_at),
    CHECK (expires_at <= issued_at + interval '120 minutes 5 seconds'),
    CHECK (row_version >= 0)
);

ALTER TABLE wecom_person_onboarding
    ADD COLUMN open_invitation_id UUID,
    ADD CONSTRAINT fk_wecom_onboarding_open_invitation
        FOREIGN KEY (tenant_id, open_invitation_id)
        REFERENCES wecom_open_onboarding_invitation (tenant_id, id);

CREATE INDEX ix_wecom_open_onboarding_invitation_expiry
    ON wecom_open_onboarding_invitation (tenant_id, corp_id, expires_at DESC, id);

CREATE INDEX ix_wecom_onboarding_open_invitation
    ON wecom_person_onboarding (tenant_id, open_invitation_id, created_at, id)
    WHERE open_invitation_id IS NOT NULL;

CREATE TRIGGER trg_wecom_open_onboarding_invitation_updated_at
    BEFORE UPDATE ON wecom_open_onboarding_invitation
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE wecom_open_onboarding_invitation ENABLE ROW LEVEL SECURITY;
ALTER TABLE wecom_open_onboarding_invitation FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON wecom_open_onboarding_invitation
    USING (tenant_id = nullif(current_setting('app.tenant_id', true), '')::uuid)
    WITH CHECK (tenant_id = nullif(current_setting('app.tenant_id', true), '')::uuid);

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'hotel_ai_os_app') THEN
        GRANT SELECT, INSERT, UPDATE, DELETE ON wecom_open_onboarding_invitation
        TO hotel_ai_os_app;
    END IF;
END $$;

COMMENT ON TABLE wecom_open_onboarding_invitation IS
    'Time-bounded reusable employee onboarding invitation; each scan creates an isolated application.';
COMMENT ON COLUMN wecom_person_onboarding.open_invitation_id IS
    'Reusable invitation that created this employee-specific onboarding application.';
