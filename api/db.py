import mysql.connector
from mysql.connector import Error

from config import Settings


def get_connection():
    return mysql.connector.connect(
        host=Settings.DB_HOST,
        port=Settings.DB_PORT,
        user=Settings.DB_USER,
        password=Settings.DB_PASSWORD,
        database=Settings.DB_NAME,
        autocommit=False,
    )


def _as_bool(value):
    if isinstance(value, (bytes, bytearray)):
        return bool(int.from_bytes(value, byteorder="little"))
    if isinstance(value, int):
        return bool(value)
    return bool(value)


def sp_register_user(username, email, phone_number, password_hash):
    conn = get_connection()
    cursor = conn.cursor()
    try:
        result = cursor.callproc(
            "sp_RegisterUser",
            [username, email, phone_number, password_hash, 0, 0, ""],
        )
        conn.commit()
        return {
            "user_id": int(result[4]) if result[4] else None,
            "success": _as_bool(result[5]),
            "message": result[6],
        }
    except Error as exc:
        conn.rollback()
        raise RuntimeError(str(exc)) from exc
    finally:
        cursor.close()
        conn.close()


def sp_generate_otp(user_id, purpose):
    conn = get_connection()
    cursor = conn.cursor()
    try:
        result = cursor.callproc("sp_GenerateOTP", [int(user_id), purpose, "", 0, ""])
        conn.commit()
        return {
            "otp_code": result[2],
            "success": _as_bool(result[3]),
            "message": result[4],
        }
    except Error as exc:
        conn.rollback()
        raise RuntimeError(str(exc)) from exc
    finally:
        cursor.close()
        conn.close()


def sp_verify_otp(user_id, otp_code, purpose):
    conn = get_connection()
    cursor = conn.cursor()
    try:
        result = cursor.callproc("sp_VerifyOTP", [int(user_id), otp_code, purpose, 0, ""])
        conn.commit()
        return {
            "is_valid": _as_bool(result[3]),
            "message": result[4],
        }
    except Error as exc:
        conn.rollback()
        raise RuntimeError(str(exc)) from exc
    finally:
        cursor.close()
        conn.close()


def sp_record_login_attempt(user_id, ip_address, status, error_message):
    conn = get_connection()
    cursor = conn.cursor()
    try:
        cursor.callproc(
            "sp_RecordLoginAttempt",
            [int(user_id) if user_id is not None else None, ip_address, status, error_message],
        )
        conn.commit()
        return {"success": True}
    except Error as exc:
        conn.rollback()
        raise RuntimeError(str(exc)) from exc
    finally:
        cursor.close()
        conn.close()


def get_user_contact(user_id):
    conn = get_connection()
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute(
            "SELECT UserID, Email, PhoneNumber FROM Users WHERE UserID = %s AND IsActive = 1 LIMIT 1",
            (int(user_id),),
        )
        return cursor.fetchone()
    except Error as exc:
        raise RuntimeError(str(exc)) from exc
    finally:
        cursor.close()
        conn.close()
