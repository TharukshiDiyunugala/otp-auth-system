# OTP Auth REST API (Step 4)

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
