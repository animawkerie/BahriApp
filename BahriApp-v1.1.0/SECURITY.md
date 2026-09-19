# Security

## Disclosure: the v1.0 security posture

The SoftwareX submission describing v1.0 stated that BahriApp used
**end-to-end encryption**. A source-level audit, prompted by peer review,
established that this was not implemented in any sense. **The claim is
withdrawn in full.**

We are documenting this rather than quietly fixing it because the v1.0 pilot
corpus — 341,606 records from 265 participants — was collected under the
posture below, and anyone working with that data, or reusing this code,
needs an accurate picture.

### What v1.0 actually did

| Aspect | v1.0 as deployed | Exposure |
|---|---|---|
| Transport | All 24 collection and authentication endpoints used plain HTTP to a hard-coded IPv4 address (`http://15.184.243.127:8080/...`) | No TLS. Behavioural payloads observable to anyone on the network path. |
| On-device cache | All eight offline Hive boxes opened with no `encryptionCipher` | Cached sessions stored as plaintext. Readable from a lost or stolen device. |
| Authentication | `authToken` written to secure storage at login, then never attached to any upload request | Collection endpoints effectively accepted anonymous writes. |
| Key custody | No key generation, storage or rotation of any kind | There was no encryption to key. |
| Export path | Dashboard export included an `Email` column | A direct identifier could leave the study in a file intended to be pseudonymous. |
| Credentials | Dashboard read a service-account JSON from an absolute developer path (`E:/PhD Cyber/...`) | Not reproducible by anyone else; risks committing a credential location. |
| Architecture | Firebase dependencies commented out in `pubspec.yaml`; the client posted to a Dart Frog service on EC2, while only the dashboard used Firestore | The documented architecture was not the deployed one. |

### Implications for the v1.0 corpus

- Data collected during the pilot travelled unencrypted over the network and
  sat unencrypted on participant devices until upload.
- Because uploads were unauthenticated, the corpus cannot be cryptographically
  attributed — a record's participant id is asserted by the client, not
  verified by the server.
- No evidence of interception or tampering has been found. That is not the
  same as evidence of absence, and we do not claim it is.

Participants were consented for behavioural data collection, minimal
demographics, and publication of a de-identified corpus. The consent materials
stated that behavioural biometrics can function as persistent identifiers.

## What v1.1 changes

| Control | Implementation |
|---|---|
| Transport | HTTPS required; `AppConfig.assertValid()` refuses to start a release build pointed at a plain-HTTP host. Optional SHA-256 certificate pinning. |
| On-device cache | `HiveAesCipher` with a 256-bit key generated on first run and held in the Android Keystore via `flutter_secure_storage`. Purged on acknowledgement. |
| Authentication | Bearer token on every request (`AuthHeadersV11.json()`), server-side verification, refresh rotation. |
| Replay | `Idempotency-Key` derived from `(participantId, sessionId, modality)`, enforced by a matching unique constraint in `deploy/schema.sql`. |
| Export | Identifier columns removed. Exports are role-gated and logged to an append-only `export_audit` table. |
| Credentials | From `GOOGLE_APPLICATION_CREDENTIALS`; the dashboard shows a configuration error instead of crashing on a missing path. |
| Withdrawal | `withdraw_participant()` deletes behavioural records and clears the identity row. |

## Threat model

| Threat | Exposure | Control (v1.1) |
|---|---|---|
| Lost or stolen participant device | Local cache readable offline | AES-256 cache, Keystore-held key, purge after upload |
| Network observer | Behavioural payloads in transit | TLS 1.3, certificate pinning |
| Compromised participant account | Impersonation, forged sessions | Bearer token with rotation, server-side session checks |
| Careless or malicious administrator | Bulk export of the corpus | Role-based access control, append-only export audit log |
| Backend database compromise | Disclosure of the corpus | Encryption at rest; identifiers in a separate table the export path never joins |
| Re-identification of pseudonymous records | Behavioural biometrics are persistent identifiers | Minimal demographics, no direct identifiers in any export. **De-identification is partial, not absolute** — this is a property of the data, not a gap we can close. |
| Replayed or duplicated sessions | Corpus pollution | Server-side deduplication on `(participant, session, modality)` |
| Unauthorised dataset export | Data leaves the study | Authenticated, logged, role-gated exports |

## Deployment checklist

Before collecting data with this software:

- [ ] `BAHRI_API_BASE` is `https://` and `BAHRI_ALLOW_INSECURE` is `false`
- [ ] Certificate pin set, or platform trust store deliberately accepted
- [ ] `BAHRI_JWT_SECRET` generated with `openssl rand -hex 32`, not the template value
- [ ] Database encryption at rest enabled by your hosting provider
- [ ] `.env` is git-ignored and contains no committed secrets
- [ ] Service-account JSON stored outside the repository
- [ ] Institutional ethics/IRB approval obtained
- [ ] Consent materials state that behavioural biometrics are persistent identifiers
- [ ] A withdrawal procedure is in place and tested

## Reporting a vulnerability

Email **animaw.kerie@kue.edu.et** with a description and reproduction steps.
Please do not open a public issue for a security-relevant finding.
