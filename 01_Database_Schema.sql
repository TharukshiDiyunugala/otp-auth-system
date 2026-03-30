-- ============================================================
-- OTP-Based Authentication System - Database Schema
-- Step 1: Create Database and Tables
-- ============================================================

-- Create Database
CREATE DATABASE IF NOT EXISTS OTPAuthDB;
USE OTPAuthDB;

-- ============================================================
-- Table 1: Users - Store user account information
-- ============================================================
CREATE TABLE IF NOT EXISTS Users (
    UserID INT PRIMARY KEY AUTO_INCREMENT,
    Username VARCHAR(50) NOT NULL UNIQUE,
    Email VARCHAR(100) NOT NULL UNIQUE,
    PasswordHash VARCHAR(255) NOT NULL,
    PhoneNumber VARCHAR(15) NOT NULL UNIQUE,
    IsActive BIT NOT NULL DEFAULT 1,
    IsLocked BIT NOT NULL DEFAULT 0,
    LockUntil DATETIME NULL,
    CreatedAt DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UpdatedAt DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_username (Username),
    INDEX idx_email (Email),
    INDEX idx_phone (PhoneNumber)
);

-- ============================================================
-- Table 2: OTP_Tokens - Store OTP verification tokens
-- ============================================================
CREATE TABLE IF NOT EXISTS OTP_Tokens (
    OTP_ID INT PRIMARY KEY AUTO_INCREMENT,
    UserID INT NOT NULL,
    OTP_Code VARCHAR(6) NOT NULL,
    OTP_Hash VARCHAR(255) NOT NULL,
    Purpose ENUM('LOGIN', 'PASSWORD_RESET', 'EMAIL_VERIFICATION') NOT NULL DEFAULT 'LOGIN',
    IsUsed BIT NOT NULL DEFAULT 0,
    Attempts INT NOT NULL DEFAULT 0,
    CreatedAt DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    ExpiresAt DATETIME NOT NULL,
    UsedAt DATETIME NULL,
    FOREIGN KEY (UserID) REFERENCES Users(UserID) ON DELETE CASCADE,
    INDEX idx_user_active (UserID, IsUsed, ExpiresAt),
    INDEX idx_expires (ExpiresAt)
);

-- ============================================================
-- Table 3: Login_Attempts - Track failed login attempts
-- ============================================================
CREATE TABLE IF NOT EXISTS Login_Attempts (
    AttemptID BIGINT PRIMARY KEY AUTO_INCREMENT,
    UserID INT,
    IPAddress VARCHAR(45) NOT NULL,
    Attempt_Status ENUM('SUCCESS', 'FAILED_OTP', 'FAILED_CREDENTIALS', 'ACCOUNT_LOCKED') NOT NULL,
    ErrorMessage VARCHAR(255),
    AttemptedAt DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (UserID) REFERENCES Users(UserID) ON DELETE SET NULL,
    INDEX idx_user_recent (UserID, AttemptedAt),
    INDEX idx_recent_attempts (AttemptedAt),
    INDEX idx_ip_address (IPAddress)
);

-- ============================================================
-- Table 4: Account_Lockout_Policies - Security policies configuration
-- ============================================================
CREATE TABLE IF NOT EXISTS Account_Lockout_Policies (
    PolicyID INT PRIMARY KEY AUTO_INCREMENT,
    MaxFailedAttempts INT NOT NULL DEFAULT 5,
    LockoutDurationMinutes INT NOT NULL DEFAULT 30,
    OTP_ExpirationMinutes INT NOT NULL DEFAULT 5,
    OTP_MaxAttempts INT NOT NULL DEFAULT 3,
    PolicyName VARCHAR(100) NOT NULL UNIQUE,
    IsActive BIT NOT NULL DEFAULT 1,
    CreatedAt DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UpdatedAt DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- ============================================================
-- Table 5: Audit_Log - Track all security-related activities
-- ============================================================
CREATE TABLE IF NOT EXISTS Audit_Log (
    LogID BIGINT PRIMARY KEY AUTO_INCREMENT,
    UserID INT,
    Action VARCHAR(100) NOT NULL,
    Description VARCHAR(255),
    IPAddress VARCHAR(45),
    Status VARCHAR(50),
    LoggedAt DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (UserID) REFERENCES Users(UserID) ON DELETE SET NULL,
    INDEX idx_user_log (UserID, LoggedAt),
    INDEX idx_action (Action, LoggedAt)
);

-- ============================================================
-- Insert Default Lockout Policy
-- ============================================================
INSERT INTO Account_Lockout_Policies (PolicyName, MaxFailedAttempts, LockoutDurationMinutes, OTP_ExpirationMinutes, OTP_MaxAttempts)
VALUES ('DEFAULT', 5, 30, 5, 3);

-- ============================================================
-- Create Helper Functions
-- ============================================================

-- Function to get current lockout policy
DELIMITER $$
CREATE FUNCTION GetCurrentPolicy() RETURNS INT
DETERMINISTIC
BEGIN
    DECLARE policyID INT;
    SELECT PolicyID INTO policyID FROM Account_Lockout_Policies WHERE IsActive = 1 LIMIT 1;
    RETURN IFNULL(policyID, 1);
END$$
DELIMITER ;

-- Function to check if user account is locked
DELIMITER $$
CREATE FUNCTION IsAccountLocked(p_UserID INT) RETURNS BIT
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE isLocked BIT;
    DECLARE lockUntil DATETIME;
    
    SELECT IsLocked, LockUntil INTO isLocked, lockUntil FROM Users WHERE UserID = p_UserID;
    
    -- If lock time has passed, unlock the account
    IF isLocked = 1 AND lockUntil < NOW() THEN
        UPDATE Users SET IsLocked = 0, LockUntil = NULL WHERE UserID = p_UserID;
        RETURN 0;
    END IF;
    
    RETURN isLocked;
END$$
DELIMITER ;

-- Function to verify OTP hash using simple comparison (in production, use bcrypt)
DELIMITER $$
CREATE FUNCTION VerifyOTPHash(p_OTP_Code VARCHAR(6), p_OTP_Hash VARCHAR(255)) RETURNS BIT
DETERMINISTIC
BEGIN
    -- In production, use proper bcrypt verification
    -- For now, using SHA256 comparison
    IF SHA2(p_OTP_Code, 256) = p_OTP_Hash THEN
        RETURN 1;
    END IF;
    RETURN 0;
END$$
DELIMITER ;

-- ============================================================
-- Schema Creation Complete
-- ============================================================
