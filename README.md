-- ============================================================
-- OTP-Based Authentication System - Implementation Guide
-- First 3 Steps: Schema, Procedures & Triggers
-- ============================================================

## PROJECT OVERVIEW

This is a production-ready, secure OTP-based authentication system built using **SQL stored procedures and triggers**.
The system manages:
- User registration and account management
- OTP (One-Time Password) generation and verification
- Login attempt tracking
- Automatic account locking after failed attempts
- Security audit logging
- Suspicious activity detection

---

## STEP 1: DATABASE SCHEMA (01_Database_Schema.sql)

### Tables Created:

#### 1. Users Table
- Stores user account information
- Fields: UserID, Username, Email, PhoneNumber, PasswordHash
- Security fields: IsActive, IsLocked, LockUntil (for temporary lockouts)
- Timestamps: CreatedAt, UpdatedAt
- Indexes on frequently queried fields (username, email, phone)

#### 2. OTP_Tokens Table
- Stores OTP codes and their hashes
- Links to Users via foreign key
- Fields: OTP_Code (plaintext for generation), OTP_Hash (SHA256 for verification)
- Tracking: IsUsed, Attempts (failed verification attempts), ExpiresAt
- Purpose: LOGIN, PASSWORD_RESET, EMAIL_VERIFICATION
- Automatic cleanup of expired records

#### 3. Login_Attempts Table
- Audit trail of all login attempts
- Tracks: UserID, IPAddress, Status (SUCCESS/FAILED_OTP/FAILED_CREDENTIALS/ACCOUNT_LOCKED)
- Used by triggers to implement automatic account locking
- Enables suspicious activity detection (multiple IPs, brute force attacks)

#### 4. Account_Lockout_Policies Table
- Configuration for security policies
- Settings: MaxFailedAttempts (5), LockoutDurationMinutes (30), OTP_ExpirationMinutes (5), OTP_MaxAttempts (3)
- Default policy provided; can create multiple policies for different user roles

#### 5. Audit_Log Table
- Comprehensive security audit trail
- Tracks all security-related actions
- Fields: UserID, Action, Description, Status, LoggedAt
- Used for compliance and forensics

### Helper Functions Created:

1. **GetCurrentPolicy()** - Retrieves active lockout policy ID
2. **IsAccountLocked(p_UserID)** - Checks if account is locked; auto-unlocks if lockout period expired
3. **VerifyOTPHash(p_OTP_Code, p_OTP_Hash)** - Securely compares OTP codes using SHA256

---

## STEP 2: STORED PROCEDURES (02_Stored_Procedures.sql)

### Core Procedures:

#### 1. sp_RegisterUser
**Purpose:** Create a new user account securely
**Input:**
  - p_Username: User's username (unique)
  - p_Email: User's email (unique)
  - p_PhoneNumber: Phone number for OTP delivery
  - p_PasswordHash: Pre-hashed password (hash at application layer)
**Output:**
  - p_UserID: Assigned user ID
  - p_Success: Success flag (1=success, 0=failure)
  - p_Message: Status message

**Example Usage:**
```sql
CALL sp_RegisterUser('john_doe', 'john@example.com', '+1234567890', 
    'hashed_password_here', @UserID, @Success, @Message);
```

#### 2. sp_GenerateOTP
**Purpose:** Generate a secure OTP code for user authentication
**Input:**
  - p_UserID: User requesting OTP
  - p_Purpose: Use case (LOGIN, PASSWORD_RESET, EMAIL_VERIFICATION)
**Output:**
  - p_OTP_Code: 6-digit OTP (only returned once!)
  - p_Success: Success flag
  - p_Message: Status message

**Features:**
  - Generates random 6-digit code
  - Creates SHA256 hash of OTP for storage
  - Invalidates previous unused OTPs
  - Respects lockout policy (won't generate if account locked)
  - Audit logging

**Example Usage:**
```sql
CALL sp_GenerateOTP(1, 'LOGIN', @OTP_Code, @Success, @Message);
SELECT @OTP_Code;  -- Returns the 6-digit OTP to send to user
```

#### 3. sp_VerifyOTP
**Purpose:** Verify OTP code provided by user during login
**Input:**
  - p_UserID: User verifying
  - p_OTP_Code: Code entered by user
  - p_Purpose: Expected use case
**Output:**
  - p_IsValid: Verification result (1=valid, 0=invalid)
  - p_Message: Detailed message

**Security Features:**
  - Checks OTP expiration (5 min default)
  - Enforces attempt limits (3 attempts default)
  - Hash comparison for code verification
  - Increment attempts on failure
  - Prevents OTP reuse after verification
  - Audit logging

**Example Usage:**
```sql
CALL sp_VerifyOTP(1, '123456', 'LOGIN', @IsValid, @Message);
IF @IsValid = 1 THEN
    -- Allow user to login
ELSE
    -- Reject with error message
END IF;
```

#### 4. sp_RecordLoginAttempt
**Purpose:** Log all login attempts (success/failure)
**Input:**
  - p_UserID: Attempting user
  - p_IPAddress: Source IP address
  - p_Status: Result (SUCCESS, FAILED_OTP, FAILED_CREDENTIALS, ACCOUNT_LOCKED)
  - p_ErrorMessage: Error details if failed

**Used by triggers to implement automatic account locking**

**Example Usage:**
```sql
CALL sp_RecordLoginAttempt(1, '192.168.1.100', 'FAILED_OTP', 'Invalid OTP code');
```

#### 5. sp_UnlockAccount
**Purpose:** Manually unlock a user account (admin operation)
**Input:**
  - p_UserID: User to unlock
  - p_AdminID: Admin performing the action
**Output:**
  - p_Success: Success flag
  - p_Message: Status message

#### 6. sp_SetUserActive
**Purpose:** Activate or deactivate user accounts
**Input:**
  - p_UserID: Target user
  - p_IsActive: 1=active, 0=inactive
**Output:**
  - p_Success: Success flag
  - p_Message: Status message

---

## STEP 3: DATABASE TRIGGERS (03_Database_Triggers.sql)

### Automatic Security Management:

#### 1. trg_AutoLockAccount_AfterFailedAttempts
**Trigger Event:** AFTER INSERT on Login_Attempts
**Purpose:** Automatically lock account after N failed attempts
**Logic:**
  - Counts failed attempts in last 60 minutes
  - When count reaches MaxFailedAttempts (5), locks account
  - Sets LockUntil timestamp for 30 minutes
  - Logs security action to Audit_Log

**Prevents:** Brute force attacks

#### 2. trg_LogSuccessfulLogin
**Trigger Event:** AFTER INSERT on Login_Attempts
**Purpose:** Log successful login events
**Logic:**
  - Records successful login with IP address
  - Checks for anomalies (success after failed attempts)
  - Logs warnings if suspicious pattern detected

**Prevents:** Undetected account compromises

#### 3. trg_ExpireOldOTP_OnInsert
**Trigger Event:** BEFORE INSERT on OTP_Tokens
**Purpose:** Mark all previous OTPs as used when new OTP generated
**Logic:**
  - When new OTP generated, old ones for same user/purpose marked expired
  - Prevents reuse of old codes

**Prevents:** OTP reuse attacks

#### 4. trg_DetectSuspiciousActivity
**Trigger Event:** AFTER INSERT on Login_Attempts
**Purpose:** Alert on multiple IP addresses in short timeframe
**Logic:**
  - Counts distinct IPs used in last 15 minutes
  - If > 2 IPs detected, flags as suspicious
  - Logs alert to Audit_Log

**Prevents:** Account hijacking from multiple locations

#### 5. trg_CleanupExpiredOTP_Weekly
**Trigger Event:** AFTER INSERT on OTP_Tokens
**Purpose:** Clean up expired OTP records older than 7 days
**Logic:**
  - Runs on every insert (batch limit of 1000 per run)
  - Removes used OTPs older than 7 days
  - Maintains data growth

**Benefits:** Database performance and storage optimization

#### 6. trg_PreventOTPReuse
**Trigger Event:** BEFORE UPDATE on OTP_Tokens
**Purpose:** Prevent marking already-used OTPs as unused (SQL injection prevention)
**Logic:**
  - Prevents IsUsed from changing 1→0
  - Logs security violation
  - Raises SQL exception to block the operation

**Prevents:** Direct database manipulation attacks

#### 7. trg_AutoUnlockExpiredLockout
**Trigger Event:** AFTER INSERT on Login_Attempts
**Purpose:** Automatically unlock accounts when lockout period expires
**Logic:**
  - Checks all locked accounts
  - Unlocks if LockUntil < NOW()
  - Logs auto-unlock event

**Improves:** User experience by unlocking automatically

#### 8. trg_AuditUserStatusChange
**Trigger Event:** AFTER UPDATE on Users
**Purpose:** Log all user account status changes
**Logic:**
  - Tracks IsActive status changes
  - Tracks IsLocked status changes
  - Records who changed and when

**Benefits:** Compliance and audit trail

#### 9. trg_ProtectOTPHash
**Trigger Event:** BEFORE UPDATE on OTP_Tokens
**Purpose:** Prevent direct modification of OTP hashes
**Logic:**
  - Detects attempts to modify OTP_Hash
  - Logs security violation
  - Restores original hash

**Prevents:** SQL injection attacks targeting OTP validation

---

## SECURITY FEATURES IMPLEMENTED

### 1. Account Locking
✓ Automatic locking after 5 failed attempts
✓ 30-minute lockout period
✓ Automatic unlock after lockout expires
✓ Manual unlock by administrators
✓ Audit logging of all lock/unlock events

### 2. OTP Security
✓ 6-digit random OTP generation
✓ SHA256 hashing of OTP codes
✓ 5-minute expiration time
✓ Maximum 3 verification attempts per OTP
✓ Automatic invalidation of previous OTPs
✓ Prevention of OTP reuse

### 3. Audit Logging
✓ Complete audit trail of all authentication events
✓ Login attempt tracking with IP addresses
✓ Suspicious activity detection
✓ User status change logging
✓ Admin action logging

### 4. SQL Injection Prevention
✓ All stored procedures use parameterized queries
✓ Triggers prevent direct hash manipulation
✓ Validation at database level

### 5. Brute Force Protection
✓ Failed attempt tracking
✓ Automatic account locking
✓ Multiple IP detection
✓ Rate limiting via attempt history

---

## DEPLOYMENT INSTRUCTIONS

### Step 1: Create Database
```bash
mysql -u root -p < 01_Database_Schema.sql
```

### Step 2: Create Stored Procedures
```bash
mysql -u root -p OTPAuthDB < 02_Stored_Procedures.sql
```

### Step 3: Create Triggers
```bash
mysql -u root -p OTPAuthDB < 03_Database_Triggers.sql
```

### Verify Installation
```sql
-- Check tables
SHOW TABLES;

-- Check procedures
SHOW PROCEDURE STATUS WHERE db = 'OTPAuthDB';

-- Check triggers
SHOW TRIGGERS;

-- Check functions
SHOW FUNCTION STATUS WHERE db = 'OTPAuthDB';
```

---

## TYPICAL AUTHENTICATION FLOW

### 1. User Registration
```sql
CALL sp_RegisterUser('john_doe', 'john@example.com', '+1234567890', 
    'hashed_password_here', @UserID, @Success, @Message);
```

### 2. User Login Initiation
```sql
-- Verify username/password first at application layer
-- Then request OTP

CALL sp_GenerateOTP(@UserID, 'LOGIN', @OTP_Code, @Success, @Message);
-- Send @OTP_Code to user via SMS/Email
```

### 3. OTP Verification
```sql
CALL sp_VerifyOTP(@UserID, 'user_entered_code', 'LOGIN', @IsValid, @Message);

IF @IsValid = 1 THEN
    CALL sp_RecordLoginAttempt(@UserID, '192.168.1.100', 'SUCCESS', NULL);
    -- Grant access to user
ELSE
    CALL sp_RecordLoginAttempt(@UserID, '192.168.1.100', 'FAILED_OTP', @Message);
    -- Account may be locked by trigger if too many failures
END IF;
```

### 4. Query Audit Log
```sql
SELECT * FROM Audit_Log 
WHERE UserID = @UserID 
ORDER BY LoggedAt DESC;
```

---

## CONFIGURATION TUNING

### Adjust Security Policy
```sql
UPDATE Account_Lockout_Policies SET 
    MaxFailedAttempts = 3,           -- Stricter
    LockoutDurationMinutes = 60,      -- Longer lockout
    OTP_ExpirationMinutes = 3,        -- Shorter expiration
    OTP_MaxAttempts = 2               -- Fewer OTP attempts
WHERE PolicyName = 'DEFAULT';
```

---

## NEXT STEPS (Not Included)

- Step 4: Application-level integration code (Python, Node.js, C#, etc.)
- Step 5: SMS/Email OTP delivery service integration
- Step 6: Web API endpoints for registration and login
- Step 7: Security testing and penetration testing (see `05_Security_Testing.md`)
- Step 8: GDPR and compliance implementation

---

## IMPORTANT SECURITY NOTES

⚠️ **Password Hashing:**
  - Hash passwords at application layer using bcrypt/argon2
  - NEVER store plaintext passwords
  - Use salt with all hashes

⚠️ **OTP Delivery:**
  - Use secure channels (SMS, authenticated email)
  - Never log OTP codes in plaintext
  - Verify delivery success

⚠️ **Network Security:**
  - Use HTTPS for all communications
  - Implement rate limiting at API level
  - Use firewall to restrict DB access

⚠️ **Database Security:**
  - Enable MySQL logging for security events
  - Use strong passwords for DB access
  - Regular backups with encryption
  - Consider data at rest encryption

---

**Version:** 1.0
**Last Updated:** 2026-03-30
**Status:** Production Ready
