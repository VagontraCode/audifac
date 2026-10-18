import 'package:flutter/material.dart';

/// Marks the moment a screen appeared, so list items inside it can play a
/// staggered entrance only on first display (not when scrolled back into view).
class EntranceScope extends StatefulWidget {
  const EntranceScope({super.key, required this.child});

  final Widget child;

  @override
  State<EntranceScope> createState() => _EntranceScopeState();
}

class _EntranceScopeState extends State<EntranceScope> {
  final _shownAt = DateTime.now();

  @override
  Widget build(BuildContext context) =>
      _EntranceTime(shownAt: _shownAt, child: widget.child);
}

class _EntranceTime extends InheritedWidget {
  const _EntranceTime({required this.shownAt, required super.child});

  final DateTime shownAt;

  @override
  bool updateShouldNotify(_EntranceTime old) => old.shownAt != shownAt;
}

/// Fades and slides its child in, delayed by [index] for a stagger effect.
class Entrance extends StatefulWidget {
  const Entrance({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  static const _maxStaggered = 12;
  static const _window = Duration(milliseconds: 700);

  @override
  State<Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<Entrance> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  late final _curve = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    final scope = context.getInheritedWidgetOfExactType<_EntranceTime>();
    final fresh = scope != null &&
        DateTime.now().difference(scope.shownAt) < Entrance._window &&
        widget.index < Entrance._maxStaggered;
    final reduceMotion =
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;

    if (!fresh || reduceMotion) {
      _controller.value = 1;
    } else {
      Future.delayed(Duration(milliseconds: 40 * widget.index), () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _curve,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.12), end: Offset.zero).animate(_curve),
        child: widget.child,
      ),
    );
  }
}
