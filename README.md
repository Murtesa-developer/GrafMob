# GrafMod

An open source mobile app for self-hosted Grafana, built with Flutter for Android and iOS.

Sign in to your own Grafana server, browse your dashboards and watch your alerts from your phone. GrafMod checks your alerts itself and sounds a local alarm when one starts firing, with no notification server or Firebase needed.

## Developer

Developed by **Murtesa**.

## Terms

Use of GrafMod is subject to the [Terms of Use](TERMS.md). The app is provided as is, and the developer is not responsible for anything that happens through its use.

## Security

See [SECURITY.md](SECURITY.md) for how GrafMod protects your data and how to report a vulnerability.

## License

Released under the [MIT License](LICENSE).

GrafMod is an independent project and is not affiliated with or endorsed by Grafana Labs. Grafana is a trademark of Grafana Labs.

## Critical alarm page and check interval

- When a critical alert fires while the app is closed, GrafMod wakes the
  screen and shows a full-screen page listing **every** critical alert that is
  firing. The page updates live when more alerts start or resolve, without
  restarting the sound. The alarm keeps sounding (and is sounded again every
  check) even if the app opens, the screen wakes or the notification is
  swiped away. Only the buttons on the alarm page stop it: **Acknowledge Alert** (sound off, page stays), **Slide to snooze (15m)** (hold the knob and drag it left to right; pressing the power button snoozes too), **Dismiss**, or **Open Full App Dashboard**.
- Account → Alert alarms → **Check every** sets how often Grafana is checked
  in the background: 10 s, 20 s ... up to 2 min (default 20 s).
- On Android 14+ allow **Full-screen alarm** (Account screen) so the page can
  appear over the lock screen.
