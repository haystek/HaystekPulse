import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// iPhone: a "Done" bar on top of the keyboard, on every screen.
/// Tapping Done closes the keyboard. The screen is told the keyboard is a
/// little taller, so the bar never covers a text box or a Send button.
/// Android has its own hide-keyboard button, so nothing changes there.
class KeyboardDoneBar extends StatelessWidget {
  const KeyboardDoneBar({super.key, required this.child});

  final Widget child;

  static const double _height = 44;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final keyboard = mq.viewInsets.bottom;
    final show = !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.iOS &&
        keyboard > 0;
    return Stack(
      children: [
        // Same widget tree with or without the bar, so no screen is rebuilt.
        Positioned.fill(
          child: MediaQuery(
            data: show
                ? mq.copyWith(
                    viewInsets:
                        mq.viewInsets.copyWith(bottom: keyboard + _height),
                  )
                : mq,
            child: child,
          ),
        ),
        if (show)
          Positioned(
            left: 0,
            right: 0,
            bottom: keyboard,
            height: _height,
            child: Material(
              color: const Color(0xFFF1F3F6),
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Color(0xFFD9DEE7))),
                ),
                child: Row(
                  children: [
                    const Spacer(),
                    TextButton(
                      onPressed: () =>
                          FocusManager.instance.primaryFocus?.unfocus(),
                      child: const Text(
                        'Done',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
