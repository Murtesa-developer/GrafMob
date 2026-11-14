# Security Policy

## Reporting a vulnerability

Please do not open a public issue for security problems. Report them privately using GitHub's **"Report a vulnerability"** button on the repository's Security tab (private vulnerability reporting). Include the affected version, steps to reproduce and the impact. You will get an acknowledgement and a fix or mitigation plan as soon as possible.

## Supported versions

Only the latest release receives security fixes.

## How GrafMod protects your data

- **Credentials** are stored only on the device, in the Android Keystore (encrypted storage) or the iOS Keychain (first-unlock, this-device-only). They are never sent anywhere except to the Grafana server you enter.
- **HTTPS by default.** Plain `http://` servers are rejected unless you explicitly turn on "Allow insecure HTTP" on the sign-in screen. Use this only on a network you trust (LAN or VPN).
- **Locked-down dashboard view.** The in-app browser only loads pages from your Grafana server. External links and other schemes are blocked.
- **Sign out** removes the stored password and clears the dashboard web session.
- **No backups.** App data is excluded from Android cloud backup and device transfer.
- **No analytics, ads or third-party tracking.**

## Known limitations

- Self-signed TLS certificates are not trusted. Use a valid certificate.
- Sign-in uses HTTP Basic authentication, so the Grafana account must have a local password. Prefer a dedicated account with the Viewer role.
- Android allows cleartext traffic at the OS level so the opt-in HTTP option works; the app itself enforces HTTPS unless you opt in.

## For contributors

- Never commit keystores, `key.properties`, `.env` files or credentials.
- Do not add logging of URLs, usernames or passwords.
- Keep new dependencies to a minimum and review their licenses.
