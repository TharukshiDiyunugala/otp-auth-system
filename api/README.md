# OTP Auth REST API (Step 4-6)

This API integrates with the existing SQL stored procedures from this repository.

## Endpoints

- `GET /health`
- `POST /api/register`
- `POST /api/login/password-verify`
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

## Password Hashing (Step 6)

- Registration now expects plaintext `password` and hashes it with `bcrypt` before calling `sp_RegisterUser`.
- Login password checks use `POST /api/login/password-verify` with `login_id` (username or email) and `password`.

## API Hardening (Step 9)

- API write endpoints enforce `Content-Type: application/json`.
- Request payload size is limited with `MAX_REQUEST_SIZE_BYTES` (default `16384`).
- Security headers are added on responses:
	- `X-Content-Type-Options: nosniff`
	- `X-Frame-Options: DENY`
	- `Referrer-Policy: no-referrer`
	- `Cache-Control: no-store` for `/api/*` routes
- Unexpected server exceptions are sanitized to a generic `500` response.

## Automated API Tests (Step 10)

- Added test suite at `api/tests/test_app.py` using `unittest` and `unittest.mock`.
- Coverage includes:
	- health endpoint response and security headers
	- JSON content-type enforcement on write endpoints
	- input validation for `user_id`
	- OTP generation success path with mocked DB and delivery dependencies
	- generic 500 error sanitization for unexpected exceptions
	- request size limit enforcement (`413`)

Run tests:

```bash
cd api
python -m unittest discover -s tests -p "test_*.py"
```
