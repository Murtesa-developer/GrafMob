import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/alarm_state.dart';

/// Full-screen page shown when critical alerts fire, also over the lock screen
/// (the phone wakes up for it). Lists every critical alert that is firing and
/// redraws live as they come and go. Always dark.
class AlarmScreen extends StatefulWidget {
  const AlarmScreen({
    super.key,
    required this.snapshot,
    required this.onAcknowledge,
    required this.onSnooze,
    required this.onDismiss,
    required this.onOpenApp,
  });

  final AlarmSnapshot snapshot;

  /// Stops the sound; the page stays so the details can be read.
  final VoidCallback onAcknowledge;

  /// Stops the sound and closes the page; rings again after 15 minutes.
  final VoidCallback onSnooze;

  /// Stops the sound and closes the page.
  final VoidCallback onDismiss;

  /// Unlocks if needed and opens the app on the alerts.
  final VoidCallback onOpenApp;

  @override
  State<AlarmScreen> createState() => _AlarmScreenState();
}

class _AlarmScreenState extends State<AlarmScreen>
    with SingleTickerProviderStateMixin {
  static const _red = Color(0xFFFF4D5E);

  // One slow loop drives the red glow of the siren, cards and button.
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat();
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    // Keeps "Updated" and the firing time current.
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _loop.dispose();
    super.dispose();
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final items = widget.snapshot.items;
    final count = items.length;
    final ringing = widget.snapshot.ringing;
    final at = widget.snapshot.updatedAt ?? DateTime.now();
    final updated = DateTime.now().isAfter(at) ? DateTime.now() : at;

    return Material(
      color: const Color(0xFF090A0D),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Faint red light from the top and from behind the main button.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -1.05),
                radius: 0.9,
                colors: [Color(0x40FF4D5E), Color(0x00FF4D5E)],
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, 0.72),
                radius: 0.75,
                colors: [Color(0x33FF4D5E), Color(0x00FF4D5E)],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(
                    loop: _loop,
                    count: count,
                    updated:
                        '${_two(updated.hour)}:${_two(updated.minute)}:${_two(updated.second)}',
                    // Power button: silences the alarm for 15 minutes, the
                    // same as the slider and the phone's own power button.
                    onPower: () {
                      HapticFeedback.heavyImpact();
                      widget.onSnooze();
                    },
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.only(bottom: 14),
                      itemCount: count,
                      separatorBuilder: (_, __) => const SizedBox(height: 14),
                      itemBuilder: (_, i) => _AlertCard(
                        // Keyed so a card keeps its place as others come/go.
                        key: ValueKey(items[i].key),
                        item: items[i],
                        loop: _loop,
                      ),
                    ),
                  ),
                  _PrimaryButton(
                    loop: _loop,
                    done: !ringing,
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      widget.onAcknowledge();
                    },
                  ),
                  const SizedBox(height: 10),
                  _SlideToSnooze(onDone: widget.onSnooze),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _SecondaryButton(
                          label: 'Dismiss',
                          color: Colors.white,
                          bold: true,
                          onTap: widget.onDismiss,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _SecondaryButton(
                          label: 'Open App',
                          color: Colors.white,
                          bold: true,
                          onTap: widget.onOpenApp,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.loop,
    required this.count,
    required this.updated,
    required this.onPower,
  });
  final Animation<double> loop;
  final int count;
  final String updated;
  final VoidCallback onPower;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedBuilder(
          animation: loop,
          builder: (_, __) {
            final glow = 0.35 + 0.35 * math.sin(loop.value * math.pi * 2);
            return Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: _AlarmScreenState._red, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: _AlarmScreenState._red.withOpacity(glow),
                    blurRadius: 18,
                  ),
                ],
              ),
              child: const Icon(Icons.crisis_alert_rounded,
                  color: _AlarmScreenState._red, size: 30),
            );
          },
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  count == 1 ? 'CRITICAL SYSTEM ALERT' : 'CRITICAL SYSTEM ALERTS',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text('Updated $updated',
                  style: const TextStyle(
                      color: Color(0xFFA5ABB8), fontSize: 15)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: 'Snooze 15 minutes',
          child: Material(
            color: const Color(0xFF14161B),
            shape: const CircleBorder(
              side: BorderSide(color: Color(0xFF2B2F38), width: 1.4),
            ),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onPower,
              child: const SizedBox(
                width: 44,
                height: 44,
                child: Icon(Icons.power_settings_new_rounded,
                    color: Color(0xFFFFB020), size: 24),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
              shape: BoxShape.circle, color: Color(0xFFE0243A)),
          child: Text('$count',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({super.key, required this.item, required this.loop});
  final AlarmItem item;
  final Animation<double> loop;

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _pretty(String key) {
    final k = key.replaceAll('_', ' ').replaceAll('-', ' ').trim();
    return k.isEmpty ? key : '${k[0].toUpperCase()}${k.substring(1)}';
  }

  /// A small icon that hints at what a label is about.
  static IconData _iconFor(String key) {
    final k = key.toLowerCase();
    if (RegExp(r'instance|host|node|pod|server|device|ip').hasMatch(k)) {
      return Icons.public_rounded;
    }
    if (RegExp(r'component|storage|disk|volume|database|db').hasMatch(k)) {
      return Icons.storage_rounded;
    }
    if (RegExp(r'folder|grafana|group|rule').hasMatch(k)) {
      return Icons.folder_open_rounded;
    }
    if (RegExp(r'job|service|app|team').hasMatch(k)) {
      return Icons.settings_outlined;
    }
    if (RegExp(r'cluster|namespace|region|zone|env|datacenter').hasMatch(k)) {
      return Icons.cloud_outlined;
    }
    return Icons.sell_outlined;
  }

  static String _duration(DateTime since) {
    final d = DateTime.now().difference(since);
    final s = d.isNegative ? Duration.zero : d;
    final h = s.inHours;
    return h > 0
        ? '$h:${_two(s.inMinutes % 60)}:${_two(s.inSeconds % 60)}'
        : '${_two(s.inMinutes)}:${_two(s.inSeconds % 60)}';
  }

  @override
  Widget build(BuildContext context) {
    final labels = item.labels.entries
        .where((e) =>
            !e.key.startsWith('__') &&
            e.key != 'alertname' &&
            e.key.toLowerCase() != 'severity')
        .toList();
    final tiles = labels.take(4).toList();
    final extra = labels.skip(4).take(2).toList();
    final since = item.startsAt;
    const red = _AlarmScreenState._red;
    const muted = Color(0xFFA5ABB8);

    return AnimatedBuilder(
      animation: loop,
      builder: (context, child) {
        // New alerts glow; ones already seen stay calm.
        final glow = item.isNew
            ? 0.5 + 0.35 * math.sin(loop.value * math.pi * 2)
            : 0.0;
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            color: const Color(0xFF14161B),
            border: Border.all(
              color: item.isNew ? red.withOpacity(0.6 + glow * 0.4) : const Color(0xFF2B2F38),
              width: 1.6,
            ),
            boxShadow: item.isNew
                ? [BoxShadow(color: red.withOpacity(glow * 0.45), blurRadius: 22)]
                : null,
          ),
          child: child,
        );
      },
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    item.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                ),
                if (item.isNew) ...[
                  const SizedBox(width: 10),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: red.withOpacity(0.28),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(color: red.withOpacity(0.35), blurRadius: 10),
                      ],
                    ),
                    child: const Text('NEW',
                        style: TextStyle(
                            color: Color(0xFFFFD0D5),
                            fontSize: 13,
                            fontWeight: FontWeight.w800)),
                  ),
                ],
              ],
            ),
            if ((item.summary ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(item.summary!,
                  style: const TextStyle(
                      color: Color(0xFFD9DCE3), fontSize: 15, height: 1.35)),
            ],
            if (tiles.isNotEmpty) ...[
              const SizedBox(height: 14),
              LayoutBuilder(builder: (context, c) {
                final w = (c.maxWidth - 10) / 2;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final e in tiles)
                      SizedBox(
                        width: w,
                        child: _Tile(
                            icon: _iconFor(e.key),
                            label: '${_pretty(e.key)}:',
                            value: e.value),
                      ),
                  ],
                );
              }),
            ],
            const SizedBox(height: 14),
            const Divider(height: 1, color: Color(0xFF262A32)),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // How long it has been firing, live.
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B1E24),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: const [
                          Icon(Icons.timer_outlined, size: 16, color: muted),
                          SizedBox(width: 6),
                          Text('Firing for',
                              style: TextStyle(color: muted, fontSize: 13)),
                        ]),
                        const SizedBox(height: 6),
                        Text(_duration(since),
                            style: const TextStyle(
                              color: Color(0xFFFF6B79),
                              fontSize: 30,
                              fontWeight: FontWeight.w700,
                              fontFeatures: [FontFeature.tabularFigures()],
                            )),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Line(
                        icon: Icons.circle,
                        iconSize: 8,
                        color: red,
                        text: 'Firing since ${_two(since.hour)}:${_two(since.minute)}',
                      ),
                      _Line(
                        icon: Icons.check_rounded,
                        color: item.isNew ? red : const Color(0xFF38D39F),
                        text: 'Status: ${item.isNew ? 'Active Firing' : 'Acknowledged'}',
                        textColor:
                            item.isNew ? const Color(0xFFFF6B79) : const Color(0xFF38D39F),
                      ),
                      if ((item.severity ?? '').isNotEmpty)
                        _Line(
                          icon: Icons.check_rounded,
                          color: const Color(0xFF38D39F),
                          text: 'Severity: ${_pretty(item.severity!)}',
                        ),
                      for (final e in extra)
                        _Line(
                          icon: Icons.check_rounded,
                          color: const Color(0xFF38D39F),
                          text: '${_pretty(e.key)}: ${e.value}',
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1E24),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFB4BAC6), size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Color(0xFFE6E8EC),
                        fontSize: 14.5,
                        fontWeight: FontWeight.w500)),
                Text(value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({
    required this.icon,
    required this.color,
    required this.text,
    this.textColor = const Color(0xFFE6E8EC),
    this.iconSize = 16,
  });
  final IconData icon;
  final Color color;
  final String text;
  final Color textColor;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 18,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icon, size: iconSize, color: color),
            ),
          ),
          Expanded(
            child: Text(text,
                style: TextStyle(color: textColor, fontSize: 14, height: 1.25)),
          ),
        ],
      ),
    );
  }
}

/// The big glowing button. After it is pressed the sound is off and it shows
/// "Acknowledged"; the page stays until Dismiss.
class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton(
      {required this.loop, required this.done, required this.onTap});
  final Animation<double> loop;
  final bool done;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: loop,
      builder: (context, child) {
        final glow = done ? 0.0 : 0.35 + 0.3 * math.sin(loop.value * math.pi * 2);
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: _AlarmScreenState._red.withOpacity(glow),
                blurRadius: 30,
                spreadRadius: 1,
              ),
            ],
          ),
          child: child,
        );
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: done ? null : onTap,
          child: Ink(
            height: 64,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: done
                    ? const [Color(0xFF20242B), Color(0xFF181B20)]
                    : const [Color(0xFF4A3036), Color(0xFF2A1A1F)],
              ),
              border: Border.all(
                color: done
                    ? const Color(0xFF2F343D)
                    : const Color(0xFFE8A9B0).withOpacity(0.75),
                width: 1.6,
              ),
            ),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (done) ...[
                    const Icon(Icons.check_circle_rounded,
                        color: Color(0xFF38D39F), size: 24),
                    const SizedBox(width: 10),
                  ],
                  Text(
                    done ? 'Acknowledged' : 'Acknowledge Alert',
                    style: TextStyle(
                      color: done ? const Color(0xFFB4BAC6) : Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({
    required this.label,
    required this.color,
    required this.onTap,
    this.bold = false,
    this.height = 54,
  });
  final String label;
  final Color color;
  final bool bold;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: const Color(0xFF14161B),
            border: Border.all(color: const Color(0xFF2B2F38), width: 1.4),
          ),
          child: Center(
            child: Text(label,
                style: TextStyle(
                  color: color,
                  fontSize: 17,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                )),
          ),
        ),
      ),
    );
  }
}

/// Hold the knob and drag it from left to right to snooze for 15 minutes. A
/// slide cannot be triggered by a stray tap while the phone is picked up.
class _SlideToSnooze extends StatefulWidget {
  const _SlideToSnooze({required this.onDone});
  final VoidCallback onDone;

  @override
  State<_SlideToSnooze> createState() => _SlideToSnoozeState();
}

class _SlideToSnoozeState extends State<_SlideToSnooze> {
  static const _h = 66.0;
  static const _knob = 54.0;
  static const _pad = 6.0;
  static const _amber = Color(0xFFFFB020);

  double _x = 0;
  bool _dragging = false;
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Snooze for 15 minutes',
      onTap: widget.onDone,
      child: LayoutBuilder(
        builder: (context, c) {
          final max = math.max(0.0, c.maxWidth - _knob - _pad * 2);
          final p = max == 0 ? 0.0 : (_x / max).clamp(0.0, 1.0);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (_) => setState(() => _dragging = true),
            onHorizontalDragUpdate: (d) =>
                setState(() => _x = (_x + d.delta.dx).clamp(0.0, max)),
            onHorizontalDragCancel: () => setState(() {
              _dragging = false;
              if (!_done) _x = 0;
            }),
            onHorizontalDragEnd: (_) {
              if (!_done && p > 0.85) {
                _done = true;
                HapticFeedback.heavyImpact();
                setState(() {
                  _dragging = false;
                  _x = max;
                });
                widget.onDone();
              } else {
                setState(() {
                  _dragging = false;
                  _x = 0;
                });
              }
            },
            child: Container(
              height: _h,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(_h / 2),
                color: const Color(0xFF14161B),
                border: Border.all(color: const Color(0xFF2B2F38), width: 1.4),
              ),
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  // Amber fill that follows the knob.
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: _pad + _knob + _x,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(_h / 2),
                        color: _amber.withOpacity(0.22),
                      ),
                    ),
                  ),
                  Center(
                    child: Opacity(
                      opacity: 1 - p,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          SizedBox(width: _knob),
                          Text('Slide to snooze (15m)',
                              style: TextStyle(
                                color: Color(0xFFB4BAC6),
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              )),
                          SizedBox(width: 8),
                          Icon(Icons.keyboard_double_arrow_right_rounded,
                              color: Color(0xFF7C8290)),
                        ],
                      ),
                    ),
                  ),
                  AnimatedPositioned(
                    duration: _dragging
                        ? Duration.zero
                        : const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    left: _pad + _x,
                    child: Container(
                      width: _knob,
                      height: _knob,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [Color(0xFFFFC857), Color(0xFFFF9A1F)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: const Icon(Icons.snooze_rounded,
                          color: Colors.white, size: 28),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
