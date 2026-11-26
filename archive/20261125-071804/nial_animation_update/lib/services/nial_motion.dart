import 'package:material_ui/material_ui.dart';

Duration nialMotionDuration(BuildContext context, [int milliseconds = 220]) =>
    MediaQuery.disableAnimationsOf(context)
        ? Duration.zero : Duration(milliseconds: milliseconds);

// Animate the incoming page only: no duplicate forms, players or GlobalKeys.
class NialEntrance extends StatefulWidget {
  const NialEntrance({super.key, required this.child,
    this.offset = const Offset(0, .018), this.milliseconds = 240});
  final Widget child;
  final Offset offset;
  final int milliseconds;
  @override
  State<NialEntrance> createState() => _NialEntranceState();
}

class _NialEntranceState extends State<NialEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _curve;
  late final Animation<Offset> _slide;
  bool _started = false;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this,
      duration: Duration(milliseconds: widget.milliseconds));
    _curve = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _slide = Tween<Offset>(begin: widget.offset, end: Offset.zero).animate(_curve);
  }
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
      _started = true;
    } else if (!_started) {
      _started = true;
      _controller.forward();
    }
  }
  @override
  void dispose() { _curve.dispose(); _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _curve,
    child: SlideTransition(position: _slide, child: widget.child));
}

class NialPressFeedback extends StatefulWidget {
  const NialPressFeedback({super.key, required this.child});
  final Widget child;
  @override
  State<NialPressFeedback> createState() => _NialPressFeedbackState();
}
class _NialPressFeedbackState extends State<NialPressFeedback> {
  final _pointers = <int>{};
  void _release(int pointer) {
    if (_pointers.remove(pointer) && mounted) setState(() {});
  }
  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (event) => setState(() => _pointers.add(event.pointer)),
    onPointerUp: (event) => _release(event.pointer),
    onPointerCancel: (event) => _release(event.pointer),
    child: AnimatedScale(
      scale: _pointers.isEmpty ? 1 : .95,
      duration: nialMotionDuration(context, 120),
      curve: Curves.easeOutCubic,
      child: widget.child));
}
