from flask import Flask, jsonify, request

import db
from config import Settings
from otp_delivery import DeliveryError, get_delivery_service

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
        if not result["success"]:
            return jsonify(result), 400

        delivery_service, contact_field = get_delivery_service(Settings.OTP_DELIVERY_PROVIDER)
        user_contact = db.get_user_contact(user_id)
        if not user_contact:
            return jsonify({"error": "User not found or inactive"}), 404

        destination = user_contact["PhoneNumber"] if contact_field == "phone_number" else user_contact["Email"]
        if not destination:
            return jsonify({"error": f"No {contact_field} available for user"}), 400

        delivery_service.send_otp(destination, result["otp_code"], purpose)
        response = {
            "success": True,
            "message": "OTP generated and delivered",
            "provider": Settings.OTP_DELIVERY_PROVIDER,
        }
        if Settings.OTP_INCLUDE_IN_RESPONSE:
            response["otp_code"] = result["otp_code"]
        return jsonify(response), 200
    except DeliveryError as exc:
        return jsonify({"error": str(exc)}), 502
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
