import 'dart:async';
import 'package:flutter/material.dart';

class TypingText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final Duration speed;
  final bool showCursor;

  const TypingText({
    super.key,
    required this.text,
    this.style,
    this.speed = const Duration(milliseconds: 35),
    this.showCursor = true,
  });

  @override
  State<TypingText> createState() => _TypingTextState();
}

class _TypingTextState extends State<TypingText> {
  String _displayedText = '';
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTyping();
  }

  void _startTyping() {
    _timer = Timer.periodic(widget.speed, (timer) {
      if (_index < widget.text.length) {
        _index++;
        setState(() {
          _displayedText = widget.text.substring(0, _index);
        });
      } else {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: widget.style ??
            const TextStyle(
              fontSize: 15,
              color: Colors.white,
              height: 1.4,
            ),
        children: [
          TextSpan(text: _displayedText),
          if (widget.showCursor)
            TextSpan(
              text: _index < widget.text.length ? '▍' : '',
              style: const TextStyle(color: Colors.white70),
            ),
        ],
      ),
    );
  }
}
