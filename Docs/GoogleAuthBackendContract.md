# Google Auth Contract For Speechara macOS

## Production base URL

The macOS app now defaults to:

`https://api.speechara.ai`

The Settings screen only needs an auth backend URL when you want to override production for local or staging testing.

## Why the desktop flow uses loopback

Speechara for macOS opens Google auth in the system browser and listens on a temporary local callback URL:

`http://127.0.0.1:{random-port}/oauth/google/callback`

This is intentional. For desktop apps, the current Google installed-app guidance recommends a loopback redirect for macOS/Linux/Windows desktop clients instead of a custom app URL scheme.

## Client flow

1. The app creates a PKCE pair: `state`, `code_verifier`, `code_challenge`.
2. The app starts a temporary local HTTP listener on `127.0.0.1`.
3. The app calls the backend start endpoint.
4. The backend returns a Google authorization URL.
5. The app opens that URL in the default browser.
6. After Google consent, the browser redirects to the local callback URL.
7. The app extracts `code` and `state`.
8. The app calls the backend exchange endpoint.
9. The backend exchanges the Google code and returns a Speechara app session.
10. The app stores that session in Keychain and unlocks the main UI.

## Required endpoints

### 1. Start Google auth

`POST /v1/auth/google/native/start`

Request:

```json
{
  "redirect_uri": "http://127.0.0.1:58241/oauth/google/callback",
  "state": "f93d6d4bbf7d4d28a2e1f8c8b6b27e7a",
  "code_challenge": "zYQ6Tz...",
  "code_challenge_method": "S256",
  "device": {
    "platform": "macOS",
    "deviceName": "Alex MacBook Pro",
    "appVersion": "1.0",
    "buildNumber": "1"
  }
}
```

Response:

```json
{
  "authorization_url": "https://accounts.google.com/o/oauth2/v2/auth?..."
}
```

Backend responsibilities:

- Build the Google authorization URL.
- Use the Google desktop/native OAuth client.
- Pass through the exact `redirect_uri`, `state`, and `code_challenge` from the client.
- Request at least `openid email profile`.
- Use `response_type=code`.
- Use offline access if you want refresh tokens.

### 2. Exchange Google code for Speechara session

`POST /v1/auth/google/native/exchange`

Request:

```json
{
  "code": "4/0AQSTgQ...",
  "state": "f93d6d4bbf7d4d28a2e1f8c8b6b27e7a",
  "code_verifier": "3a3f1d6c...",
  "redirect_uri": "http://127.0.0.1:58241/oauth/google/callback",
  "device": {
    "platform": "macOS",
    "deviceName": "Alex MacBook Pro",
    "appVersion": "1.0",
    "buildNumber": "1"
  }
}
```

Response:

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
    "avatar_url": "https://lh3.googleusercontent.com/..."
  }
}
```

Backend responsibilities:

- Verify `state` if you keep it server-side.
- Exchange the Google `code` with Google using the same `redirect_uri`.
- Validate the Google identity.
- Find or create the Speechara user.
- Issue first-party Speechara access/refresh tokens.
- Return the normalized user payload shown above.

### 3. Refresh Speechara session

`POST /v1/auth/session/refresh`

Request:

```json
{
  "refresh_token": "speechara_refresh_token"
}
```

Response:

```json
{
  "access_token": "speechara_access_token",
  "refresh_token": "speechara_refresh_token",
  "token_type": "Bearer",
  "expires_at": "2026-04-05T23:30:00Z",
  "user": {
    "id": "usr_123",
    "email": "alex@example.com",
    "display_name": "Alex Dementyev",
    "avatar_url": "https://lh3.googleusercontent.com/..."
  }
}
```

### 4. Logout

`POST /v1/auth/logout`

Headers:

`Authorization: Bearer <speechara_access_token>`

Request:

```json
{
  "refresh_token": "speechara_refresh_token"
}
```

Response:

- `204 No Content` is enough.

### 5. Fetch current user

`GET /v1/auth/me`

Headers:

`Authorization: Bearer <speechara_access_token>`

Response:

```json
{
  "id": "usr_123",
  "email": "alex@example.com",
  "display_name": "Alex Dementyev",
  "avatar_url": "https://lh3.googleusercontent.com/..."
}
```

This endpoint is not required for the first version already implemented in the macOS app, but it is strongly recommended for future session validation and profile refresh.

## Error format

All auth endpoints should return a consistent JSON error body:

```json
{
  "error": "invalid_request",
  "message": "Google sign-in is not enabled for this workspace."
}
```

Recommended HTTP statuses:

- `400` for malformed requests
- `401` for invalid/expired Speechara tokens
- `403` for workspace restrictions
- `409` for account-linking conflicts
- `500` for unexpected failures

## Google / backend configuration notes

- Register a Google OAuth client suitable for desktop/native flow.
- Allow the loopback redirect URI pattern used by the desktop client flow.
- Requested scopes should start with: `openid email profile`
- The backend should own mapping from Google identity to Speechara account and should issue Speechara tokens, not expose internal user logic to the app.

## Current app assumptions

The current macOS implementation expects:

- The auth backend base URL defaults to `https://api.speechara.ai`
- `SPEECHARA_AUTH_BASE_URL` or the Settings override should only be used for non-production environments
- `expires_at` to be ISO 8601 UTC, for example `2026-04-05T21:30:00Z`
- `display_name` and `avatar_url` fields already normalized by the backend
