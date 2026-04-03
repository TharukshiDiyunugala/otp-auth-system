import requests

from config import Settings


class DeliveryError(Exception):
    pass


class OTPDeliveryService:
    def send_otp(self, destination, otp_code, purpose):
        raise NotImplementedError


class ConsoleDeliveryService(OTPDeliveryService):
    def send_otp(self, destination, otp_code, purpose):
        print(f"[OTP:{purpose}] destination={destination} otp={otp_code}")


class TwilioDeliveryService(OTPDeliveryService):
    def send_otp(self, destination, otp_code, purpose):
        if not Settings.TWILIO_ACCOUNT_SID or not Settings.TWILIO_AUTH_TOKEN or not Settings.TWILIO_FROM_NUMBER:
            raise DeliveryError("Twilio configuration is incomplete")

        url = f"https://api.twilio.com/2010-04-01/Accounts/{Settings.TWILIO_ACCOUNT_SID}/Messages.json"
        message = f"Your OTP for {purpose} is {otp_code}. It expires soon."
        response = requests.post(
            url,
            data={
                "To": destination,
                "From": Settings.TWILIO_FROM_NUMBER,
                "Body": message,
            },
            auth=(Settings.TWILIO_ACCOUNT_SID, Settings.TWILIO_AUTH_TOKEN),
            timeout=10,
        )
        if response.status_code not in (200, 201):
            raise DeliveryError(f"Twilio delivery failed: {response.text}")


class SendGridDeliveryService(OTPDeliveryService):
    def send_otp(self, destination, otp_code, purpose):
        if not Settings.SENDGRID_API_KEY or not Settings.SENDGRID_FROM_EMAIL:
            raise DeliveryError("SendGrid configuration is incomplete")

        response = requests.post(
            "https://api.sendgrid.com/v3/mail/send",
            headers={
                "Authorization": f"Bearer {Settings.SENDGRID_API_KEY}",
                "Content-Type": "application/json",
            },
            json={
                "personalizations": [{"to": [{"email": destination}]}],
                "from": {"email": Settings.SENDGRID_FROM_EMAIL},
                "subject": "Your OTP code",
                "content": [
                    {
                        "type": "text/plain",
                        "value": f"Your OTP for {purpose} is {otp_code}. It expires soon.",
                    }
                ],
            },
            timeout=10,
        )
        if response.status_code != 202:
            raise DeliveryError(f"SendGrid delivery failed: {response.text}")


def get_delivery_service(provider):
    if provider == "twilio":
        return TwilioDeliveryService(), "phone_number"
    if provider == "sendgrid":
        return SendGridDeliveryService(), "email"
    return ConsoleDeliveryService(), "phone_number"
