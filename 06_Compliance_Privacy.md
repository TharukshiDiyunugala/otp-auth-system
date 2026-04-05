# Step 8: GDPR and Compliance Implementation

This guide defines the compliance-oriented maintenance routines for the OTP authentication system. It focuses on retention, portability, and erasure workflows for the data already stored in the database.

## Data Classes Covered

The system stores the following user-related records:

- `Users`
- `OTP_Tokens`
- `Login_Attempts`
- `Audit_Log`

## Recommended Retention Baseline

Use local policy and legal review to set the final values, but the following defaults are a practical starting point:

- OTP tokens: 7 days after use or expiration
- Login attempts: 30 days
- Audit logs: 90 days

## Export Workflow

For subject-access requests, export the current profile and recent activity in a read-only report.

```sql
SELECT UserID, Username, Email, PhoneNumber, IsActive, IsLocked, LockUntil, CreatedAt, UpdatedAt
FROM Users
WHERE UserID = <user_id>;

SELECT AttemptID, IPAddress, Attempt_Status, ErrorMessage, AttemptedAt
FROM Login_Attempts
WHERE UserID = <user_id>
ORDER BY AttemptedAt DESC;

SELECT LogID, Action, Description, Status, LoggedAt
FROM Audit_Log
WHERE UserID = <user_id>
ORDER BY LoggedAt DESC;
```

## Erasure Workflow

When data deletion is approved, remove the dependent records in a transaction so referential integrity stays intact.

```sql
START TRANSACTION;

DELETE FROM OTP_Tokens WHERE UserID = <user_id>;
DELETE FROM Login_Attempts WHERE UserID = <user_id>;
DELETE FROM Audit_Log WHERE UserID = <user_id>;
DELETE FROM Users WHERE UserID = <user_id>;

COMMIT;
```

## Maintenance Queries

Use these routines during scheduled maintenance windows.

```sql
DELETE FROM OTP_Tokens
WHERE IsUsed = 1
  AND ExpiresAt < DATE_SUB(NOW(), INTERVAL 7 DAY);

DELETE FROM Login_Attempts
WHERE AttemptedAt < DATE_SUB(NOW(), INTERVAL 30 DAY);

DELETE FROM Audit_Log
WHERE LoggedAt < DATE_SUB(NOW(), INTERVAL 90 DAY);
```

## Operational Controls

1. Restrict deletion and export routines to privileged operators.
1. Keep encrypted backups before any retention job runs.
1. Log every export and delete request in the application audit trail.
1. Review retention windows with legal and security stakeholders before production use.

## Suggested Database Extension

If you want the compliance workflows enforced inside MySQL, add stored procedures that wrap the queries above and require explicit confirmation before execution.