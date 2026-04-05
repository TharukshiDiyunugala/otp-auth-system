# Step 7: Security Testing and Penetration Testing

This guide covers the security checks that should be run after Steps 1 to 6 are deployed. It focuses on the controls already implemented in the database and API layers: account lockout, OTP expiration, OTP reuse prevention, suspicious activity detection, and audit logging.

## Scope

Run these checks in a staging or local environment only. Do not use production credentials or production data.

## Test Matrix

1. Account lockout after repeated failures
1. OTP rejection after expiration
1. OTP reuse prevention
1. Suspicious activity detection across multiple IPs
1. Audit log completeness for successful and failed events

## Recommended Manual Checks

### 1. Account lockout

1. Create or identify a test user.
2. Submit 5 failed login attempts within 60 minutes.
3. Confirm `Users.IsLocked = 1` and `Users.LockUntil` is populated.
4. Confirm a corresponding `Audit_Log` entry exists with `ACCOUNT_AUTO_LOCKED`.

Validation query:

```sql
SELECT UserID, Username, IsLocked, LockUntil
FROM Users
WHERE UserID = <test_user_id>;

SELECT Action, Description, Status, LoggedAt
FROM Audit_Log
WHERE UserID = <test_user_id>
ORDER BY LogID DESC
LIMIT 5;
```

### 2. OTP expiration and reuse

1. Generate a login OTP for the test user.
2. Wait for the configured expiration window or adjust the record in a test database.
3. Verify the OTP is rejected after expiration.
4. Verify an already-used OTP cannot be marked unused again.

Validation query:

```sql
SELECT OTP_ID, UserID, Purpose, IsUsed, Attempts, CreatedAt, ExpiresAt, UsedAt
FROM OTP_Tokens
WHERE UserID = <test_user_id>
ORDER BY CreatedAt DESC
LIMIT 1;
```

### 3. Suspicious activity detection

1. Record successful or failed attempts from 3 different IP addresses within 15 minutes.
2. Confirm the audit log contains a `SUSPICIOUS_ACTIVITY_DETECTED` entry.

Validation query:

```sql
SELECT Action, Description, Status, LoggedAt
FROM Audit_Log
WHERE UserID = <test_user_id>
  AND Action = 'SUSPICIOUS_ACTIVITY_DETECTED'
ORDER BY LogID DESC;
```

## API Smoke Checks

Use these calls to verify the API layer still routes correctly into the database procedures.

```bash
curl -X POST http://localhost:8000/api/register ^
  -H "Content-Type: application/json" ^
  -d "{\"username\":\"sec_test\",\"email\":\"sec@example.com\",\"phone_number\":\"+1555000100\",\"password\":\"TestPass123!\"}"

curl -X POST http://localhost:8000/api/login/password-verify ^
  -H "Content-Type: application/json" ^
  -d "{\"login_id\":\"sec_test\",\"password\":\"TestPass123!\"}"

curl -X POST http://localhost:8000/api/otp/generate ^
  -H "Content-Type: application/json" ^
  -d "{\"user_id\":1,\"purpose\":\"LOGIN\"}"
```

## Pass Criteria

1. Failed attempts lock the account at the configured threshold.
1. Expired OTPs are rejected and marked used.
1. OTP reuse attempts fail.
1. Multiple IP activity is logged as suspicious.
1. Every outcome appears in `Audit_Log`.

## Suggested Follow-Up

If a check fails, inspect the matching stored procedure or trigger in:

- `02_Stored_Procedures.sql`
- `03_Database_Triggers.sql`
- `api/app.py`