# OTP Auth REST API (Step 4-5)

This API integrates with the existing SQL stored procedures from this repository.

## Endpoints

- `GET /health`
- `POST /api/register`
- `POST /api/otp/generate`
- `POST /api/otp/verify`
- `POST /api/login-attempt`

## Setup

```bash
cd api
python -m venv .venv
.venv\\Scripts\\activate
pip install -r requirements.txt
```

Copy `.env.example` to `.env` and set values.

## Run

```bash
cd api
python app.py
```

The API defaults to `http://localhost:8000`.

## OTP Delivery Providers (Step 5)

Set the provider with `OTP_DELIVERY_PROVIDER`:

- `console` (default): logs OTP to server console
- `twilio`: sends OTP via SMS
- `sendgrid`: sends OTP via email

Environment variables:

- `OTP_DELIVERY_PROVIDER=console|twilio|sendgrid`
- `OTP_INCLUDE_IN_RESPONSE=true|false`
- `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_FROM_NUMBER`
- `SENDGRID_API_KEY`, `SENDGRID_FROM_EMAIL`
