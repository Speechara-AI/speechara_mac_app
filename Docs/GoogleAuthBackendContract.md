# Auth Backend Contract For Speechara Apps

This document describes the auth backend contract used by the current Speechara macOS app and intended to be mirrored by the iOS app.

The file was originally Google-specific, but the app now supports:

- Google OAuth
- Microsoft OAuth
- Email/password login
- Email registration
- Email code verification
- TOTP MFA
- Session refresh/logout/profile
- Account security settings

## Production Base URL

`https://api.speechara.ai`

The app should only override this URL for local, staging, or QA environments.

macOS resolves the auth backend URL from:

- `SPEECHARA_AUTH_BASE_URL`
- `SpeecharaAuthBackendBaseURL` in `Info.plist`
- Settings override
- default value: `https://api.speechara.ai`

## Common Request Rules

All app-to-backend auth requests use JSON unless stated otherwise:

```http
Content-Type: application/json
Accept: application/json
```

Authenticated requests must include:

```http
Authorization: Bearer <access_token>
```

Access and refresh tokens must be stored in Keychain.

The app should refresh the session when `expires_at` is less than or equal to 60 seconds away. If refresh fails, clear the local session and ask the user to sign in again.

## Common Session Response

Login, provider exchange, registration completion, MFA verification, and refresh endpoints return the same session shape:

```json
{
  "access_token": "speechara_access_token",
  "refresh_token": "speechara_refresh_token",
  "token_type": "Bearer",
  "expires_at": "2026-04-05T21:30:00Z",
  "user": {
    "id": "usr_123",
    "email": "alex@example.com",
    "display_name": "Alex Dementyev",
    "avatar_url": "https://lh3.googleusercontent.com/...",
    "workspace_id": "workspace_123",
    "default_workspace_id": "workspace_123",
    "current_workspace_id": "workspace_123",
    "newbie": false,
    "workspace": {
      "id": "workspace_123"
    },
    "default_workspace": {
      "id": "workspace_123"
    },
    "current_workspace": {
      "id": "workspace_123"
    },
    "workspaces": [
      {
        "id": "workspace_123"
      }
    ]
  }
}
```

Required fields:

- `access_token`
- `refresh_token`
- `token_type`
- `expires_at`
- `user.id`
- `user.email`

Recommended user fields:

- `display_name`
- `avatar_url`
- `newbie`
- workspace references

The backend should return `expires_at` as ISO 8601 UTC. The macOS app can also decode `expires_in`, but new clients should prefer `expires_at`.

The macOS decoder accepts both snake_case and camelCase for token and user fields, but new backend responses should use snake_case.

## Google OAuth

Speechara for macOS opens Google auth in the system browser. The backend owns the Google callback page and then opens the app through a custom deep link.

The current app deep link is:

```text
speechara://auth/callback?code=<desktopAuthCode>&state=<state>
```

Access and refresh tokens must never be placed in the deep link. The deep link may only contain a short-lived, one-time auth code.

### Client Flow

1. The app creates a cryptographically random `state` and stores it in memory for the active sign-in attempt.
2. The app opens the backend Google start URL in the system browser or `ASWebAuthenticationSession`.
3. The backend redirects the user through Google OAuth.
4. After Google consent, the browser lands on the backend callback.
5. The backend creates or links the Speechara user.
6. The backend creates a short-lived, one-time auth code.
7. The backend renders a branded completion page and opens the app deep link.
8. The app receives the deep link, extracts `code` and `state`, and validates that `state` matches the active attempt.
9. The app exchanges the code for a Speechara session.
10. The app stores the session in Keychain and unlocks the main UI.

### Start Google Auth

```http
GET /api/auth/google/desktop/start?state=<state>
```

Backend responsibilities:

- Validate and preserve the exact `state` from the client.
- Redirect to Google OAuth.
- Request at least `openid email profile`.
- Use `response_type=code`.
- Use the backend callback URL for Google.

### Complete Browser Callback

```http
GET /api/auth/google/desktop/callback
```

Backend responsibilities:

- Validate the Google response.
- Create or link the Speechara user.
- Create a short-lived, one-time auth code.
- Render a branded HTML completion page.
- Open the app deep link:

```text
speechara://auth/callback?code=<desktopAuthCode>&state=<state>
```

### Exchange Auth Code

```http
POST /api/auth/desktop/exchange
```

Request:

```json
{
  "code": "desktop_auth_code",
  "state": "f93d6d4bbf7d4d28a2e1f8c8b6b27e7a"
}
```

Response: common session response.

Backend responsibilities:

- Validate `state`.
- Validate that `code` is one-time and not expired.
- Issue first-party Speechara access/refresh tokens.

## Microsoft OAuth

The current macOS app performs Microsoft OAuth with PKCE directly against Microsoft, receives an `id_token`, and exchanges that `id_token` with the Speechara backend.

### Microsoft Authorize URL

```text
https://login.microsoftonline.com/common/oauth2/v2.0/authorize
```

Query parameters:

```text
client_id=<microsoft_client_id>
response_type=code
redirect_uri=<client_redirect_uri>
response_mode=query
scope=openid profile email
state=<state>
code_challenge=<S256_code_challenge>
code_challenge_method=S256
prompt=select_account
```

macOS uses a local loopback callback. iOS should use its platform-appropriate callback, for example a custom scheme or universal link registered for the app.

The app must validate returned `state`.

### Microsoft Token Exchange

This request goes to Microsoft, not to the Speechara backend.

```http
POST https://login.microsoftonline.com/common/oauth2/v2.0/token
Content-Type: application/x-www-form-urlencoded
Accept: application/json
```

Form body:

```text
client_id=<microsoft_client_id>
scope=openid profile email
code=<authorization_code>
redirect_uri=<same_redirect_uri>
grant_type=authorization_code
code_verifier=<pkce_code_verifier>
```

The app must read `id_token` from the Microsoft response.

### Exchange Microsoft ID Token With Speechara

```http
POST /api/auth/microsoft
```

Request:

```json
{
  "idToken": "microsoft_id_token"
}
```

Response: common session response.

Backend responsibilities:

- Validate the Microsoft ID token.
- Create or link the Speechara user.
- Issue first-party Speechara access/refresh tokens.

## Email/Password Auth

### Start Email Registration

```http
POST /api/auth/email/register
```

Request:

```json
{
  "email": "alex@example.com",
  "name": "Alex Dementyev"
}
```

Response:

```json
{
  "challengeId": "challenge_123",
  "email": "alex@example.com",
  "maskedEmail": "a***@example.com",
  "purpose": "registration",
  "linkedAuthProviders": [],
  "expiresIn": 600,
  "expiresAt": "2026-04-05T21:30:00Z",
  "resendAfter": 30
}
```

### Verify Email Code

```http
POST /api/auth/email/verify
```

Request:

```json
{
  "challengeId": "challenge_123",
  "email": "alex@example.com",
  "code": "123456"
}
```

Response:

```json
{
  "challengeId": "challenge_123",
  "email": "alex@example.com",
  "maskedEmail": "a***@example.com",
  "verified": true,
  "purpose": "registration",
  "linkedAuthProviders": [],
  "verificationToken": "verification_token",
  "expiresIn": 600,
  "expiresAt": "2026-04-05T21:30:00Z"
}
```

### Setup TOTP During Registration

```http
POST /api/auth/email/totp/setup
```

Request:

```json
{
  "challengeId": "challenge_123",
  "email": "alex@example.com",
  "verificationToken": "verification_token"
}
```

Response:

```json
{
  "setupId": "totp_setup_123",
  "otpauthUri": "otpauth://totp/...",
  "secret": "BASE32SECRET",
  "qrCodeDataUrl": "data:image/png;base64,...",
  "expiresIn": 600,
  "expiresAt": "2026-04-05T21:30:00Z"
}
```

### Complete Email Registration

```http
POST /api/auth/email/complete-registration
```

Request without MFA:

```json
{
  "challengeId": "challenge_123",
  "email": "alex@example.com",
  "name": "Alex Dementyev",
  "password": "StrongPass1!",
  "verificationToken": "verification_token",
  "mfa": null
}
```

Request with TOTP MFA:

```json
{
  "challengeId": "challenge_123",
  "email": "alex@example.com",
  "name": "Alex Dementyev",
  "password": "StrongPass1!",
  "verificationToken": "verification_token",
  "mfa": {
    "type": "totp",
    "setupId": "totp_setup_123",
    "code": "123456"
  }
}
```

Response: common session response.

### Email Login

```http
POST /api/auth/email/login
```

Request:

```json
{
  "email": "alex@example.com",
  "password": "StrongPass1!"
}
```

Response if MFA is not required: common session response.

Response if MFA is required:

```json
{
  "code": "MFA_REQUIRED",
  "challengeId": "mfa_challenge_123",
  "email": "alex@example.com",
  "maskedEmail": "a***@example.com",
  "type": "totp",
  "expiresIn": 300,
  "expiresAt": "2026-04-05T21:30:00Z"
}
```

### Verify Email MFA

```http
POST /api/auth/email/mfa/verify
```

Request:

```json
{
  "challengeId": "mfa_challenge_123",
  "email": "alex@example.com",
  "type": "totp",
  "code": "123456"
}
```

Response: common session response.

### Resend Email Code

```http
POST /api/auth/email/resend-code
```

Request:

```json
{
  "challengeId": "challenge_123",
  "email": "alex@example.com"
}
```

Response: same shape as start email registration.

## Session Lifecycle

### Refresh Session

```http
POST /v1/auth/session/refresh
```

Request:

```json
{
  "refresh_token": "speechara_refresh_token"
}
```

Response: common session response.

### Logout

```http
POST /v1/auth/logout
Authorization: Bearer <access_token>
```

Request:

```json
{
  "refresh_token": "speechara_refresh_token"
}
```

Response:

```http
204 No Content
```

Any 2xx response is acceptable. The client should clear local session data even if the backend logout request fails.

### Fetch Current User

```http
GET /v1/auth/me
Authorization: Bearer <access_token>
```

Response:

```json
{
  "id": "usr_123",
  "email": "alex@example.com",
  "display_name": "Alex Dementyev",
  "avatar_url": "https://lh3.googleusercontent.com/...",
  "newbie": false
}
```

### Update Current User

```http
PATCH /v1/auth/me
Authorization: Bearer <access_token>
```

Request:

```json
{
  "newbie": false
}
```

Response: current user profile response.

## Account Security

### Fetch Security Status

```http
GET /api/auth/security
Authorization: Bearer <access_token>
```

Response:

```json
{
  "passwordLoginEnabled": true,
  "mfa": {
    "totpEnabled": true,
    "enabledMethods": ["totp"],
    "enabledAt": "2026-04-05T21:30:00Z"
  }
}
```

### Change Password

```http
POST /api/auth/security/password/change
Authorization: Bearer <access_token>
Cookie: speechara_refresh_token=<refresh_token>
```

Request:

```json
{
  "currentPassword": "OldPass1!",
  "newPassword": "NewPass1!"
}
```

Response:

```json
{
  "passwordLoginEnabled": true,
  "changedAt": "2026-04-05T21:30:00Z"
}
```

### Start TOTP Setup

```http
POST /api/auth/security/mfa/totp/setup
Authorization: Bearer <access_token>
```

Request:

```json
{}
```

Response: TOTP setup response.

### Enable TOTP

```http
POST /api/auth/security/mfa/totp/enable
Authorization: Bearer <access_token>
```

Request:

```json
{
  "setupId": "totp_setup_123",
  "code": "123456"
}
```

Response: security status response.

### Disable TOTP

```http
POST /api/auth/security/mfa/totp/disable
Authorization: Bearer <access_token>
```

Request:

```json
{
  "code": "123456"
}
```

Response: security status response.

## Backend Error Format

All auth endpoints should return a consistent JSON error body:

```json
{
  "error": "invalid_request",
  "message": "Google sign-in is not enabled for this workspace."
}
```

The current macOS app can resolve the message from these fields, in priority order:

- `error_description`
- `message`
- `detail`
- `error`
- `title`

Recommended HTTP statuses:

- `400` for malformed requests
- `401` for invalid or expired Speechara tokens
- `403` for workspace restrictions
- `409` for account-linking conflicts
- `500` for unexpected failures

## iOS Implementation Notes

iOS should mirror the macOS session model and lifecycle:

- Use Keychain for persisted session storage.
- Keep active OAuth `state` only in memory.
- Validate OAuth `state` before exchanging codes or tokens.
- Use `ASWebAuthenticationSession` for provider auth where possible.
- Register the app callback scheme or universal link needed for Google and Microsoft flows.
- Never accept access or refresh tokens through a deep link.
- Refresh the session before protected API calls when the access token is close to expiry.
- Clear local session data if refresh fails.

The iOS team should confirm whether the backend wants to keep the current `/desktop/*` Google endpoint names for mobile clients or expose equivalent `/mobile/*` aliases. The payload and security rules should remain the same either way.
