import 'package:flutter/material.dart';

import '../theme.dart';
import 'ui.dart';

/// Generic loader with pull-to-refresh, error and empty states.
class AsyncList<T> extends StatefulWidget {
  const AsyncList({
    super.key,
    required this.load,
    required this.builder,
    this.emptyTitle = 'Nothing here',
    this.emptyMessage,
    this.emptyIcon = Icons.inbox_rounded,
    this.emptyColor,
    this.autoRefresh,
    this.refreshOn,
  });

  final Future<List<T>> Function() load;
  final Widget Function(BuildContext, List<T>) builder;
  final String emptyTitle;
  final String? emptyMessage;
  final IconData emptyIcon;
  final Color? emptyColor;
  final Duration? autoRefresh;

  /// When this notifies, the list reloads silently.
  final Listenable? refreshOn;

  @override
  State<AsyncList<T>> createState() => _AsyncListState<T>();
}

class _AsyncListState<T> extends State<AsyncList<T>> {
  List<T>? _data;
  Object? _error;
  bool _loading = true;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    widget.refreshOn?.addListener(_onTick);
    refresh();
    _schedule();
  }

  void _onTick() => refresh(silent: true);

  void _schedule() {
    final d = widget.autoRefresh;
    if (d == null) return;
    Future.delayed(d, () async {
      if (_disposed) return;
      await refresh(silent: true);
      _schedule();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    widget.refreshOn?.removeListener(_onTick);
    super.dispose();
  }

  Future<void> refresh({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final r = await widget.load();
      if (!mounted) return;
      setState(() {
        _data = r;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        // Keep showing old data on silent refresh failures.
        if (!silent || _data == null) _error = e;
        _loading = false;
      });
    }
  }

  Widget _scrollable(Widget child) => RefreshIndicator(
        color: Pal.accent,
        onRefresh: refresh,
        child: LayoutBuilder(
          builder: (context, c) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: c.maxHeight),
              child: Center(child: child),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (_loading && _data == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _data == null) {
      return _scrollable(StateView(
        icon: Icons.cloud_off_rounded,
        color: Pal.red,
        title: 'Could not load',
        message: '$_error',
        onAction: refresh,
      ));
    }
    final data = _data ?? <T>[];
    if (data.isEmpty) {
      return _scrollable(StateView(
        icon: widget.emptyIcon,
        color: widget.emptyColor,
        title: widget.emptyTitle,
        message: widget.emptyMessage,
      ));
    }
    return RefreshIndicator(
      color: Pal.accent,
      onRefresh: refresh,
      child: widget.builder(context, data),
    );
  }
}
