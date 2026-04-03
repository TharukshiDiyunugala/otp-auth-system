from flask import Flask, jsonify, request

import db
from config import Settings

app = Flask(__name__)


@app.get("/health")
def health():
    return jsonify({"status": "ok"}), 200


@app.post("/api/register")
def register_user():
    payload = request.get_json(silent=True) or {}
    required_fields = ["username", "email", "phone_number", "password_hash"]
    missing = [name for name in required_fields if not payload.get(name)]
    if missing:
        return jsonify({"error": f"Missing required fields: {', '.join(missing)}"}), 400

    try:
        result = db.sp_register_user(
            payload["username"],
            payload["email"],
            payload["phone_number"],
            payload["password_hash"],
        )
        return jsonify(result), 200 if result["success"] else 400
    except RuntimeError as exc:
        return jsonify({"error": str(exc)}), 500


@app.post("/api/otp/generate")
def generate_otp():
    payload = request.get_json(silent=True) or {}
    user_id = payload.get("user_id")
    purpose = payload.get("purpose", "LOGIN")

    if not user_id:
        return jsonify({"error": "Missing required field: user_id"}), 400

    try:
        result = db.sp_generate_otp(user_id, purpose)
        return jsonify(result), 200 if result["success"] else 400
    except RuntimeError as exc:
        return jsonify({"error": str(exc)}), 500


@app.post("/api/otp/verify")
def verify_otp():
    payload = request.get_json(silent=True) or {}
    user_id = payload.get("user_id")
    otp_code = payload.get("otp_code")
    purpose = payload.get("purpose", "LOGIN")

    if not user_id or not otp_code:
        return jsonify({"error": "Missing required fields: user_id, otp_code"}), 400

    try:
        result = db.sp_verify_otp(user_id, otp_code, purpose)
        return jsonify(result), 200 if result["is_valid"] else 400
    except RuntimeError as exc:
        return jsonify({"error": str(exc)}), 500


@app.post("/api/login-attempt")
def record_login_attempt():
    payload = request.get_json(silent=True) or {}
    user_id = payload.get("user_id")
    status = payload.get("status")
    error_message = payload.get("error_message")
    ip_address = request.headers.get("X-Forwarded-For", request.remote_addr)

    if not status:
        return jsonify({"error": "Missing required field: status"}), 400

    try:
        result = db.sp_record_login_attempt(user_id, ip_address, status, error_message)
        return jsonify(result), 200
    except RuntimeError as exc:
        return jsonify({"error": str(exc)}), 500


if __name__ == "__main__":
    app.run(host=Settings.API_HOST, port=Settings.API_PORT, debug=Settings.DEBUG)
