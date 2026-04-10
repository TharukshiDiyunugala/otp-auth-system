import unittest
from unittest.mock import patch
import sys
import types

if "mysql" not in sys.modules:
    mysql_module = types.ModuleType("mysql")
    connector_module = types.ModuleType("mysql.connector")
    connector_module.Error = Exception
    connector_module.connect = lambda **_kwargs: None
    mysql_module.connector = connector_module
    sys.modules["mysql"] = mysql_module
    sys.modules["mysql.connector"] = connector_module

import app as app_module


class APITestCase(unittest.TestCase):
    def setUp(self):
        app_module.app.config["TESTING"] = True
        self.client = app_module.app.test_client()

    def test_health_endpoint(self):
        response = self.client.get("/health")

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json()["status"], "ok")
        self.assertEqual(response.headers.get("X-Content-Type-Options"), "nosniff")

    def test_generate_otp_requires_json_content_type(self):
        response = self.client.post("/api/otp/generate", data="not-json")

        self.assertEqual(response.status_code, 415)
        self.assertIn("Content-Type must be application/json", response.get_json()["error"])

    def test_generate_otp_invalid_user_id_type(self):
        response = self.client.post(
            "/api/otp/generate",
            json={"user_id": "abc", "purpose": "LOGIN"},
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn("Missing required field: user_id", response.get_json()["error"])

    def test_record_login_attempt_invalid_user_id_type(self):
        response = self.client.post(
            "/api/login-attempt",
            json={"user_id": "bad-id", "status": "FAILED_OTP"},
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn("user_id must be an integer", response.get_json()["error"])

    @patch("app.get_delivery_service")
    @patch("app.db.get_user_contact")
    @patch("app.db.sp_generate_otp")
    def test_generate_otp_success(
        self,
        mock_sp_generate_otp,
        mock_get_user_contact,
        mock_get_delivery_service,
    ):
        mock_sp_generate_otp.return_value = {
            "otp_code": "123456",
            "success": True,
            "message": "OTP generated",
        }
        mock_get_user_contact.return_value = {
            "UserID": 1,
            "Email": "user@example.com",
            "PhoneNumber": "+123456789",
        }

        class FakeDelivery:
            def send_otp(self, _destination, _otp_code, _purpose):
                return None

        mock_get_delivery_service.return_value = (FakeDelivery(), "phone_number")

        response = self.client.post(
            "/api/otp/generate",
            json={"user_id": 1, "purpose": "LOGIN"},
        )

        self.assertEqual(response.status_code, 200)
        body = response.get_json()
        self.assertTrue(body["success"])
        self.assertEqual(body["provider"], app_module.Settings.OTP_DELIVERY_PROVIDER)

    @patch("app.db.sp_generate_otp", side_effect=Exception("boom"))
    def test_generate_otp_unexpected_error_is_sanitized(self, _mock_sp_generate_otp):
        response = self.client.post(
            "/api/otp/generate",
            json={"user_id": 1, "purpose": "LOGIN"},
        )

        self.assertEqual(response.status_code, 500)
        self.assertEqual(response.get_json()["error"], "Internal server error")

    def test_request_payload_too_large(self):
        original_max = app_module.app.config.get("MAX_CONTENT_LENGTH")
        app_module.app.config["MAX_CONTENT_LENGTH"] = 64
        try:
            response = self.client.post(
                "/api/register",
                json={
                    "username": "a" * 80,
                    "email": "user@example.com",
                    "phone_number": "+123456789",
                    "password": "secret123",
                },
            )
        finally:
            app_module.app.config["MAX_CONTENT_LENGTH"] = original_max

        self.assertEqual(response.status_code, 413)
        self.assertEqual(response.get_json()["error"], "Request payload too large")


if __name__ == "__main__":
    unittest.main()
