-- BahriApp v1.1 — ingestion schema.
--
-- Two v1.1 properties are enforced here rather than left to application code:
--
--   * DEDUPLICATION. A retried upload must not create a duplicate session.
--     The unique constraint on (participant_id, session_id, modality) makes a
--     replay a no-op instead of corpus pollution.
--
--   * IDENTIFIER SEPARATION. Behavioural records carry only an opaque
--     participant id. Contact details live in a separate table that the
--     export path never joins against, so a direct identifier cannot leave
--     the system in a dataset export (the v1.0 'Email' column defect).

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ---------------------------------------------------------------- identity
-- Deliberately separate from every behavioural table.
CREATE TABLE IF NOT EXISTS participant_identity (
    participant_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email            TEXT UNIQUE,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    withdrawn_at     TIMESTAMPTZ,
    withdrawal_note  TEXT
);
COMMENT ON TABLE participant_identity IS
  'Direct identifiers. NEVER joined by the export path. On withdrawal, set '
  'withdrawn_at and run the deletion routine in docs/withdrawal.md.';

-- Minimal demographics, keyed by the opaque id only.
CREATE TABLE IF NOT EXISTS participant (
    participant_id   UUID PRIMARY KEY
                     REFERENCES participant_identity(participant_id)
                     ON DELETE CASCADE,
    birth_year       SMALLINT,
    sex              TEXT,
    skill_level      TEXT,
    enrolled_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ------------------------------------------------------------- acquisition
CREATE TABLE IF NOT EXISTS session (
    id               BIGSERIAL PRIMARY KEY,
    participant_id   UUID NOT NULL REFERENCES participant(participant_id)
                     ON DELETE CASCADE,
    session_id       TEXT NOT NULL,   -- device-minted, stored as TEXT: see below
    modality         TEXT NOT NULL,
    app_version      TEXT NOT NULL,
    started_at       TIMESTAMPTZ NOT NULL,
    ended_at         TIMESTAMPTZ,
    received_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    instrument       JSONB,           -- SessionInstrumentMeta
    idempotency_key  TEXT NOT NULL,

    -- Replay protection. A retried upload hits this and is ignored.
    CONSTRAINT session_unique UNIQUE (participant_id, session_id, modality)
);

-- session_id is TEXT, not BIGINT, on purpose. It is a 13-digit millisecond
-- epoch stamp; storing and exporting it as a number is what let the v1.0 tap
-- export lose 7 orders of magnitude of resolution to float formatting.
COMMENT ON COLUMN session.session_id IS
  'Millisecond epoch as TEXT. Never export as a numeric type.';

CREATE INDEX IF NOT EXISTS session_participant_idx
    ON session (participant_id, modality);
CREATE INDEX IF NOT EXISTS session_started_idx ON session (started_at);
CREATE UNIQUE INDEX IF NOT EXISTS session_idempotency_idx
    ON session (idempotency_key);

CREATE TABLE IF NOT EXISTS record (
    id               BIGSERIAL PRIMARY KEY,
    session_pk       BIGINT NOT NULL REFERENCES session(id) ON DELETE CASCADE,
    seq              INTEGER NOT NULL,
    payload          JSONB NOT NULL,
    CONSTRAINT record_unique UNIQUE (session_pk, seq)
);
CREATE INDEX IF NOT EXISTS record_session_idx ON record (session_pk);

-- --------------------------------------------------------------- auditing
-- Every export is logged, append-only. Addresses the "malicious or careless
-- administrator" and "unauthorised export" threats.
CREATE TABLE IF NOT EXISTS export_audit (
    id               BIGSERIAL PRIMARY KEY,
    actor            TEXT NOT NULL,
    modality         TEXT,
    row_count        INTEGER,
    exported_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    client_ip        INET
);
REVOKE UPDATE, DELETE ON export_audit FROM PUBLIC;

-- ------------------------------------------------------------ withdrawal
-- Honours a participant's deletion request across every behavioural table.
CREATE OR REPLACE FUNCTION withdraw_participant(p_id UUID, note TEXT)
RETURNS void AS $$
BEGIN
    UPDATE participant_identity
       SET withdrawn_at = now(), withdrawal_note = note, email = NULL
     WHERE participant_id = p_id;
    DELETE FROM session WHERE participant_id = p_id;  -- cascades to record
END;
$$ LANGUAGE plpgsql;
