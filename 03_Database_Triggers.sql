-- ============================================================
-- OTP Authentication System - Database Triggers
-- Step 3: Create Triggers for Automatic Security Management
-- ============================================================

USE OTPAuthDB;

-- ============================================================
-- TRIGGER 1: Auto-Lock Account After Max Failed Attempts
-- Purpose: Automatically lock user account after maximum failed login attempts
-- ============================================================
DELIMITER $$
CREATE TRIGGER trg_AutoLockAccount_AfterFailedAttempts
AFTER INSERT ON Login_Attempts
FOR EACH ROW
BEGIN
    DECLARE v_FailedAttempts INT;
    DECLARE v_MaxFailedAttempts INT;
    DECLARE v_LockoutDuration INT;
    DECLARE v_PolicyID INT;
    
    -- Only process failed attempts
    IF NEW.Attempt_Status IN ('FAILED_OTP', 'FAILED_CREDENTIALS') AND NEW.UserID IS NOT NULL THEN
        -- Get current lockout policy
        SELECT PolicyID INTO v_PolicyID FROM Account_Lockout_Policies WHERE IsActive = 1 LIMIT 1;
        
        -- Get policy settings
        SELECT MaxFailedAttempts, LockoutDurationMinutes 
        INTO v_MaxFailedAttempts, v_LockoutDuration
        FROM Account_Lockout_Policies 
        WHERE PolicyID = v_PolicyID;
        
        -- Count failed attempts in the last hour for this user
        SELECT COUNT(*) INTO v_FailedAttempts
        FROM Login_Attempts
        WHERE UserID = NEW.UserID 
        AND Attempt_Status IN ('FAILED_OTP', 'FAILED_CREDENTIALS')
        AND AttemptedAt > DATE_SUB(NOW(), INTERVAL 60 MINUTE);
        
        -- If max attempts exceeded, lock the account
        IF v_FailedAttempts >= v_MaxFailedAttempts THEN
            UPDATE Users
            SET IsLocked = 1,
                LockUntil = DATE_ADD(NOW(), INTERVAL v_LockoutDuration MINUTE)
            WHERE UserID = NEW.UserID;
            
            -- Log the lockout event
            INSERT INTO Audit_Log (UserID, Action, Description, Status)
            VALUES (NEW.UserID, 'ACCOUNT_AUTO_LOCKED', 
                    CONCAT('Account locked after ', v_FailedAttempts, ' failed attempts'), 
                    'SECURITY_ACTION');
            
            -- Record the lockout attempt
            UPDATE Login_Attempts
            SET Attempt_Status = 'ACCOUNT_LOCKED',
                ErrorMessage = CONCAT('Account locked for ', v_LockoutDuration, ' minutes')
            WHERE AttemptID = NEW.AttemptID;
        END IF;
    END IF;
END$$
DELIMITER ;

-- ============================================================
-- TRIGGER 2: Log Successful Login
-- Purpose: Record successful login and reset failed attempt counter
-- ============================================================
DELIMITER $$
CREATE TRIGGER trg_LogSuccessfulLogin
AFTER INSERT ON Login_Attempts
FOR EACH ROW
BEGIN
    DECLARE v_ExistingFailedAttempts INT;
    
    -- Only process successful attempts
    IF NEW.Attempt_Status = 'SUCCESS' AND NEW.UserID IS NOT NULL THEN
        -- Log the successful login
        INSERT INTO Audit_Log (UserID, Action, Description, Status)
        VALUES (NEW.UserID, 'LOGIN_SUCCESS', CONCAT('User logged in from IP: ', NEW.IPAddress), 'SUCCESS');
        
        -- Check if there were previous failed attempts in last hour
        SELECT COUNT(*) INTO v_ExistingFailedAttempts
        FROM Login_Attempts
        WHERE UserID = NEW.UserID 
        AND Attempt_Status IN ('FAILED_OTP', 'FAILED_CREDENTIALS')
        AND AttemptedAt > DATE_SUB(NOW(), INTERVAL 60 MINUTE)
        AND AttemptID < NEW.AttemptID;
        
        -- Log if there were previous failed attempts
        IF v_ExistingFailedAttempts > 0 THEN
            INSERT INTO Audit_Log (UserID, Action, Description, Status)
            VALUES (NEW.UserID, 'ANOMALY_DETECTED', 
                    CONCAT('Successful login after ', v_ExistingFailedAttempts, ' failed attempts'), 
                    'WARNING');
        END IF;
    END IF;
END$$
DELIMITER ;

-- ============================================================
-- TRIGGER 3: Auto-Expire Old OTP Codes
-- Purpose: Automatically mark expired OTPs as used to prevent reuse
-- ============================================================
DELIMITER $$
CREATE TRIGGER trg_ExpireOldOTP_OnInsert
BEFORE INSERT ON OTP_Tokens
FOR EACH ROW
BEGIN
    DECLARE v_ExpiredCount INT;
    
    -- Mark any expired OTPs as used for the same user and purpose
    UPDATE OTP_Tokens
    SET IsUsed = 1, UsedAt = NOW()
    WHERE UserID = NEW.UserID 
    AND Purpose = NEW.Purpose
    AND IsUsed = 0
    AND ExpiresAt < NOW();
END$$
DELIMITER ;

-- ============================================================
-- TRIGGER 4: Alert on Suspicious Activity (Multiple IPs)
-- Purpose: Detect multiple IP addresses used for same account in short time
-- ============================================================
DELIMITER $$
CREATE TRIGGER trg_DetectSuspiciousActivity
AFTER INSERT ON Login_Attempts
FOR EACH ROW
BEGIN
    DECLARE v_DistinctIPCount INT;
    DECLARE v_IsAlert BIT DEFAULT 0;
    
    IF NEW.UserID IS NOT NULL THEN
        -- Count distinct IP addresses used by this user in the last 15 minutes
        SELECT COUNT(DISTINCT IPAddress) INTO v_DistinctIPCount
        FROM Login_Attempts
        WHERE UserID = NEW.UserID
        AND AttemptedAt > DATE_SUB(NOW(), INTERVAL 15 MINUTE);
        
        -- If more than 2 different IPs in 15 minutes, flag as suspicious
        IF v_DistinctIPCount > 2 THEN
            INSERT INTO Audit_Log (UserID, Action, Description, Status)
            VALUES (NEW.UserID, 'SUSPICIOUS_ACTIVITY_DETECTED', 
                    CONCAT('Multiple IP addresses detected: ', v_DistinctIPCount, ' different IPs in 15 minutes'),
                    'ALERT');
            
            -- This could trigger email notification to user
            -- Email logic would be implemented at application level
        END IF;
    END IF;
END$$
DELIMITER ;

-- ============================================================
-- TRIGGER 5: Auto-Cleanup of Expired OTP Records
-- Purpose: Clean up old expired OTP records periodically
-- ============================================================
DELIMITER $$
CREATE TRIGGER trg_CleanupExpiredOTP_Weekly
AFTER INSERT ON OTP_Tokens
FOR EACH ROW
BEGIN
    -- This trigger runs cleanup on every insert
    -- In production, consider using an event scheduler instead
    DELETE FROM OTP_Tokens
    WHERE IsUsed = 1 
    AND ExpiresAt < DATE_SUB(NOW(), INTERVAL 7 DAY)
    LIMIT 1000;  -- Limit to avoid performance impact
END$$
DELIMITER ;

-- ============================================================
-- TRIGGER 6: Prevent Re-use of Recently Used OTP
-- Purpose: Ensure OTP codes cannot be reused within a session
-- ============================================================
DELIMITER $$
CREATE TRIGGER trg_PreventOTPReuse
BEFORE UPDATE ON OTP_Tokens
FOR EACH ROW
BEGIN
    -- Prevent changing IsUsed from 1 to 0 (marking as unused)
    IF OLD.IsUsed = 1 AND NEW.IsUsed = 0 THEN
        -- Log the security violation attempt
        INSERT INTO Audit_Log (UserID, Action, Description, Status)
        VALUES (NEW.UserID, 'OTP_REUSE_ATTEMPT', 'Attempt to reuse a previously used OTP code', 'SECURITY_VIOLATION');
        
        -- Signal an error
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cannot reuse OTP codes';
    END IF;
END$$
DELIMITER ;

-- ============================================================
-- TRIGGER 7: Auto-Unlock Expired Lockouts
-- Purpose: Automatically unlock accounts when lockout duration expires
-- ============================================================
DELIMITER $$
CREATE TRIGGER trg_AutoUnlockExpiredLockout
AFTER INSERT ON Login_Attempts
FOR EACH ROW
BEGIN
    -- Check and unlock any accounts with expired lockout duration
    UPDATE Users
    SET IsLocked = 0, LockUntil = NULL
    WHERE IsLocked = 1 
    AND LockUntil IS NOT NULL
    AND LockUntil < NOW();
    
    -- Log unlock events
    INSERT INTO Audit_Log (UserID, Action, Description, Status)
    SELECT UserID, 'ACCOUNT_AUTO_UNLOCKED', 'Account automatically unlocked after lockout duration expired', 'SECURITY_ACTION'
    FROM Users
    WHERE IsLocked = 0 AND LockUntil IS NULL;
END$$
DELIMITER ;

-- ============================================================
-- TRIGGER 8: Audit User Status Changes
-- Purpose: Log all changes to user active status
-- ============================================================
DELIMITER $$
CREATE TRIGGER trg_AuditUserStatusChange
AFTER UPDATE ON Users
FOR EACH ROW
BEGIN
    IF OLD.IsActive != NEW.IsActive THEN
        INSERT INTO Audit_Log (UserID, Action, Description, Status)
        VALUES (NEW.UserID, 'USER_STATUS_CHANGED', 
                CONCAT('User status changed from ', IF(OLD.IsActive = 1, 'ACTIVE', 'INACTIVE'), 
                       ' to ', IF(NEW.IsActive = 1, 'ACTIVE', 'INACTIVE')), 
                'ADMIN_ACTION');
    END IF;
    
    IF OLD.IsLocked != NEW.IsLocked THEN
        INSERT INTO Audit_Log (UserID, Action, Description, Status)
        VALUES (NEW.UserID, 'USER_LOCK_STATUS_CHANGED',
                CONCAT('User lock status changed from ', IF(OLD.IsLocked = 1, 'LOCKED', 'UNLOCKED'),
                       ' to ', IF(NEW.IsLocked = 1, 'LOCKED', 'UNLOCKED')),
                'SECURITY_ACTION');
    END IF;
END$$
DELIMITER ;

-- ============================================================
-- TRIGGER 9: Prevent Direct OTP_Hash Updates
-- Purpose: Prevent SQL injection through direct OTP hash manipulation
-- ============================================================
DELIMITER $$
CREATE TRIGGER trg_ProtectOTPHash
BEFORE UPDATE ON OTP_Tokens
FOR EACH ROW
BEGIN
    -- Prevent changing OTP hash directly
    IF OLD.OTP_Hash != NEW.OTP_Hash THEN
        -- Log security violation
        INSERT INTO Audit_Log (UserID, Action, Description, Status)
        VALUES (NEW.UserID, 'OTP_HASH_MANIPULATION_ATTEMPT', 
                'Attempt to modify OTP hash directly detected', 'SECURITY_VIOLATION');
        
        -- Restore original hash
        SET NEW.OTP_Hash = OLD.OTP_Hash;
    END IF;
END$$
DELIMITER ;

-- ============================================================
-- Triggers Creation Complete
-- ============================================================

-- ============================================================
-- Optional: Create Event Scheduler for Periodic Cleanup
-- Uncomment to enable (requires EVENT privilege)
-- ============================================================
/*
DELIMITER $$
CREATE EVENT IF NOT EXISTS evt_DailyAuditCleanup
ON SCHEDULE EVERY 1 DAY
STARTS CURRENT_TIMESTAMP
DO
BEGIN
    -- Keep last 90 days of audit logs
    DELETE FROM Audit_Log
    WHERE LoggedAt < DATE_SUB(NOW(), INTERVAL 90 DAY);
    
    -- Remove login attempts older than 30 days
    DELETE FROM Login_Attempts
    WHERE AttemptedAt < DATE_SUB(NOW(), INTERVAL 30 DAY);
END$$
DELIMITER ;
*/
