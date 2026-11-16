import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Android: back on a home screen first shows "Press back again to close
/// the app"; a second back within 2 seconds closes it. Screens opened on
/// top still go back as usual (this only acts on the home screen itself).
class DoubleBackToClose extends StatefulWidget {
  const DoubleBackToClose({super.key, required this.child});

  final Widget child;

  @override
  State<DoubleBackToClose> createState() => _DoubleBackToCloseState();
}

class _DoubleBackToCloseState extends State<DoubleBackToClose> {
  DateTime? _lastBack;

  void _onBack() {
    final now = DateTime.now();
    if (_lastBack != null &&
        now.difference(_lastBack!) < const Duration(seconds: 2)) {
      SystemNavigator.pop();
      return;
    }
    _lastBack = now;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Press back again to close the app'),
          duration: Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: widget.child,
    );
  }
}
