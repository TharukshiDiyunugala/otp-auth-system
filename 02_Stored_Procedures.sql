-- ============================================================
-- OTP Authentication System - Stored Procedures
-- Step 2: Create Core Stored Procedures
-- ============================================================

USE OTPAuthDB;

-- ============================================================
-- SP 1: Register New User
-- Purpose: Create a new user account with hashed password
-- ============================================================
DELIMITER $$
CREATE PROCEDURE sp_RegisterUser(
    IN p_Username VARCHAR(50),
    IN p_Email VARCHAR(100),
    IN p_PhoneNumber VARCHAR(15),
    IN p_PasswordHash VARCHAR(255),
    OUT p_UserID INT,
    OUT p_Success BIT,
    OUT p_Message VARCHAR(255)
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        SET p_Success = 0;
        SET p_Message = 'Database error during registration';
        ROLLBACK;
    END;
    
    START TRANSACTION;
    
    -- Validate input
    IF p_Username IS NULL OR p_Username = '' THEN
        SET p_Success = 0;
        SET p_Message = 'Username cannot be empty';
        ROLLBACK;
    ELSEIF p_Email IS NULL OR p_Email = '' THEN
        SET p_Success = 0;
        SET p_Message = 'Email cannot be empty';
        ROLLBACK;
    ELSEIF p_PhoneNumber IS NULL OR p_PhoneNumber = '' THEN
        SET p_Success = 0;
        SET p_Message = 'Phone number cannot be empty';
        ROLLBACK;
    ELSE
        -- Insert the user
        INSERT INTO Users (Username, Email, PhoneNumber, PasswordHash, IsActive)
        VALUES (p_Username, p_Email, p_PhoneNumber, p_PasswordHash, 1);
        
        SET p_UserID = LAST_INSERT_ID();
        SET p_Success = 1;
        SET p_Message = 'User registered successfully';
        
        -- Log audit entry
        INSERT INTO Audit_Log (UserID, Action, Description, Status)
        VALUES (p_UserID, 'USER_REGISTRATION', CONCAT('User ', p_Username, ' registered'), 'SUCCESS');
        
        COMMIT;
    END IF;
END$$
DELIMITER ;

-- ============================================================
-- SP 2: Generate OTP
-- Purpose: Generate and store a new OTP code for the user
-- ============================================================
DELIMITER $$
CREATE PROCEDURE sp_GenerateOTP(
    IN p_UserID INT,
    IN p_Purpose VARCHAR(50),
    OUT p_OTP_Code VARCHAR(6),
    OUT p_Success BIT,
    OUT p_Message VARCHAR(255)
)
BEGIN
    DECLARE v_OTP_Code VARCHAR(6);
    DECLARE v_OTP_Hash VARCHAR(255);
    DECLARE v_ExpiresAt DATETIME;
    DECLARE v_PolicyID INT;
    DECLARE v_IsLocked BIT;
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        SET p_Success = 0;
        SET p_Message = 'Database error during OTP generation';
        ROLLBACK;
    END;
    
    START TRANSACTION;
    
    -- Check if user exists and is active
    IF NOT EXISTS (SELECT 1 FROM Users WHERE UserID = p_UserID AND IsActive = 1) THEN
        SET p_Success = 0;
        SET p_Message = 'User not found or inactive';
        ROLLBACK;
    ELSE
        -- Check if account is locked
        SET v_IsLocked = IsAccountLocked(p_UserID);
        IF v_IsLocked = 1 THEN
            SET p_Success = 0;
            SET p_Message = 'Account is locked. Please try again later';
            ROLLBACK;
        ELSE
            -- Get current lockout policy
            SET v_PolicyID = GetCurrentPolicy();
            
            -- Generate random 6-digit OTP
            SET v_OTP_Code = LPAD(FLOOR(RAND() * 1000000), 6, '0');
            
            -- Hash the OTP using SHA256
            SET v_OTP_Hash = SHA2(v_OTP_Code, 256);
            
            -- Calculate expiration time
            SET v_ExpiresAt = DATE_ADD(NOW(), INTERVAL (SELECT OTP_ExpirationMinutes FROM Account_Lockout_Policies WHERE PolicyID = v_PolicyID) MINUTE);
            
            -- Invalidate any existing unused OTPs for this user
            UPDATE OTP_Tokens 
            SET IsUsed = 1 
            WHERE UserID = p_UserID AND IsUsed = 0 AND Purpose = p_Purpose;
            
            -- Insert new OTP
            INSERT INTO OTP_Tokens (UserID, OTP_Code, OTP_Hash, Purpose, ExpiresAt)
            VALUES (p_UserID, v_OTP_Code, v_OTP_Hash, p_Purpose, v_ExpiresAt);
            
            SET p_OTP_Code = v_OTP_Code;
            SET p_Success = 1;
            SET p_Message = 'OTP generated successfully';
            
            -- Log audit entry
            INSERT INTO Audit_Log (UserID, Action, Description, Status)
            VALUES (p_UserID, 'OTP_GENERATED', CONCAT('OTP generated for purpose: ', p_Purpose), 'SUCCESS');
            
            COMMIT;
        END IF;
    END IF;
END$$
DELIMITER ;

-- ============================================================
-- SP 3: Verify OTP Code
-- Purpose: Verify the OTP code provided by user
-- ============================================================
DELIMITER $$
CREATE PROCEDURE sp_VerifyOTP(
    IN p_UserID INT,
    IN p_OTP_Code VARCHAR(6),
    IN p_Purpose VARCHAR(50),
    OUT p_IsValid BIT,
    OUT p_Message VARCHAR(255)
)
BEGIN
    DECLARE v_OTP_Hash VARCHAR(255);
    DECLARE v_IsUsed BIT;
    DECLARE v_Attempts INT;
    DECLARE v_ExpiresAt DATETIME;
    DECLARE v_MaxAttempts INT;
    DECLARE v_PolicyID INT;
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        SET p_IsValid = 0;
        SET p_Message = 'Database error during OTP verification';
        ROLLBACK;
    END;
    
    START TRANSACTION;
    
    -- Get current policy
    SET v_PolicyID = GetCurrentPolicy();
    SELECT OTP_MaxAttempts INTO v_MaxAttempts FROM Account_Lockout_Policies WHERE PolicyID = v_PolicyID;
    
    -- Check if user exists
    IF NOT EXISTS (SELECT 1 FROM Users WHERE UserID = p_UserID) THEN
        SET p_IsValid = 0;
        SET p_Message = 'User not found';
        ROLLBACK;
    ELSE
        -- Get the active OTP for this user
        SELECT OTP_Hash, IsUsed, Attempts, ExpiresAt 
        INTO v_OTP_Hash, v_IsUsed, v_Attempts, v_ExpiresAt
        FROM OTP_Tokens 
        WHERE UserID = p_UserID AND Purpose = p_Purpose AND IsUsed = 0
        ORDER BY CreatedAt DESC LIMIT 1;
        
        -- Check if OTP exists
        IF v_OTP_Hash IS NULL THEN
            SET p_IsValid = 0;
            SET p_Message = 'No active OTP found for this user';
            INSERT INTO Audit_Log (UserID, Action, Description, Status)
            VALUES (p_UserID, 'OTP_VERIFICATION_FAILED', 'No active OTP found', 'FAILED');
            ROLLBACK;
        -- Check if OTP has expired
        ELSEIF v_ExpiresAt < NOW() THEN
            SET p_IsValid = 0;
            SET p_Message = 'OTP has expired';
            UPDATE OTP_Tokens SET IsUsed = 1 WHERE UserID = p_UserID AND Purpose = p_Purpose AND IsUsed = 0;
            INSERT INTO Audit_Log (UserID, Action, Description, Status)
            VALUES (p_UserID, 'OTP_EXPIRED', 'OTP expired during verification', 'FAILED');
            ROLLBACK;
        -- Check attempt limit
        ELSEIF v_Attempts >= v_MaxAttempts THEN
            SET p_IsValid = 0;
            SET p_Message = CONCAT('Maximum OTP attempts exceeded. Please request a new OTP');
            UPDATE OTP_Tokens SET IsUsed = 1 WHERE UserID = p_UserID AND Purpose = p_Purpose AND IsUsed = 0;
            INSERT INTO Audit_Log (UserID, Action, Description, Status)
            VALUES (p_UserID, 'OTP_MAX_ATTEMPTS_EXCEEDED', 'Max OTP attempts reached', 'FAILED');
            ROLLBACK;
        ELSE
            -- Verify OTP code
            IF VerifyOTPHash(p_OTP_Code, v_OTP_Hash) = 1 THEN
                -- OTP is valid - mark as used
                UPDATE OTP_Tokens 
                SET IsUsed = 1, UsedAt = NOW()
                WHERE UserID = p_UserID AND Purpose = p_Purpose AND IsUsed = 0;
                
                SET p_IsValid = 1;
                SET p_Message = 'OTP verified successfully';
                
                INSERT INTO Audit_Log (UserID, Action, Description, Status)
                VALUES (p_UserID, 'OTP_VERIFIED', CONCAT('OTP verified for purpose: ', p_Purpose), 'SUCCESS');
                
                COMMIT;
            ELSE
                -- OTP is incorrect - increment attempt counter
                UPDATE OTP_Tokens 
                SET Attempts = Attempts + 1
                WHERE UserID = p_UserID AND Purpose = p_Purpose AND IsUsed = 0 AND ExpiresAt > NOW();
                
                SET p_IsValid = 0;
                SET @NewAttempts = v_Attempts + 1;
                SET p_Message = CONCAT('Invalid OTP. Attempts remaining: ', (v_MaxAttempts - @NewAttempts));
                
                INSERT INTO Audit_Log (UserID, Action, Description, Status)
                VALUES (p_UserID, 'OTP_VERIFICATION_FAILED', 'Invalid OTP code provided', 'FAILED');
                
                COMMIT;
            END IF;
        END IF;
    END IF;
END$$
DELIMITER ;

-- ============================================================
-- SP 4: Record Login Attempt
-- Purpose: Record user login attempt (success or failure)
-- ============================================================
DELIMITER $$
CREATE PROCEDURE sp_RecordLoginAttempt(
    IN p_UserID INT,
    IN p_IPAddress VARCHAR(45),
    IN p_Status VARCHAR(50),
    IN p_ErrorMessage VARCHAR(255)
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        -- Log error but don't throw
        INSERT INTO Audit_Log (UserID, Action, Description, Status)
        VALUES (p_UserID, 'LOGIN_ATTEMPT_LOG_ERROR', 'Error recording login attempt', 'FAILED');
    END;
    
    INSERT INTO Login_Attempts (UserID, IPAddress, Attempt_Status, ErrorMessage)
    VALUES (p_UserID, p_IPAddress, p_Status, p_ErrorMessage);
END$$
DELIMITER ;

-- ============================================================
-- SP 5: Unlock Account
-- Purpose: Manually unlock a user account (admin function)
-- ============================================================
DELIMITER $$
CREATE PROCEDURE sp_UnlockAccount(
    IN p_UserID INT,
    IN p_AdminID INT,
    OUT p_Success BIT,
    OUT p_Message VARCHAR(255)
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        SET p_Success = 0;
        SET p_Message = 'Database error during account unlock';
        ROLLBACK;
    END;
    
    START TRANSACTION;
    
    IF NOT EXISTS (SELECT 1 FROM Users WHERE UserID = p_UserID) THEN
        SET p_Success = 0;
        SET p_Message = 'User not found';
        ROLLBACK;
    ELSE
        UPDATE Users 
        SET IsLocked = 0, LockUntil = NULL
        WHERE UserID = p_UserID;
        
        SET p_Success = 1;
        SET p_Message = 'Account unlocked successfully';
        
        -- Log audit entry
        INSERT INTO Audit_Log (UserID, Action, Description, Status)
        VALUES (p_AdminID, 'ACCOUNT_UNLOCKED', CONCAT('Manually unlocked user ID: ', p_UserID), 'SUCCESS');
        
        COMMIT;
    END IF;
END$$
DELIMITER ;

-- ============================================================
-- SP 6: Deactivate User
-- Purpose: Deactivate or reactivate a user account
-- ============================================================
DELIMITER $$
CREATE PROCEDURE sp_SetUserActive(
    IN p_UserID INT,
    IN p_IsActive BIT,
    OUT p_Success BIT,
    OUT p_Message VARCHAR(255)
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        SET p_Success = 0;
        SET p_Message = 'Database error during user status update';
        ROLLBACK;
    END;
    
    START TRANSACTION;
    
    IF NOT EXISTS (SELECT 1 FROM Users WHERE UserID = p_UserID) THEN
        SET p_Success = 0;
        SET p_Message = 'User not found';
        ROLLBACK;
    ELSE
        UPDATE Users SET IsActive = p_IsActive WHERE UserID = p_UserID;
        
        SET p_Success = 1;
        SET p_Message = CONCAT('User status updated to: ', IF(p_IsActive = 1, 'ACTIVE', 'INACTIVE'));
        
        INSERT INTO Audit_Log (UserID, Action, Description, Status)
        VALUES (p_UserID, 'USER_STATUS_CHANGED', CONCAT('User status changed to: ', IF(p_IsActive = 1, 'ACTIVE', 'INACTIVE')), 'SUCCESS');
        
        COMMIT;
    END IF;
END$$
DELIMITER ;

-- ============================================================
-- Stored Procedures Creation Complete
-- ============================================================
