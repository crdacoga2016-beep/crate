import 'package:flutter/material.dart';

import '../../util/format.dart';

class SeekBar extends StatefulWidget {
  const SeekBar({
    super.key,
    required this.position,
    required this.duration,
    required this.onSeek,
    this.accent = Colors.white,
  });

  final Duration position;
  final Duration? duration;
  final ValueChanged<Duration> onSeek;
  final Color accent;

  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final totalMs = widget.duration?.inMilliseconds ?? 0;
    final positionMs = widget.position.inMilliseconds;
    final max = totalMs > 0 ? totalMs.toDouble() : 1.0;
    final value = (_dragValue ?? positionMs.toDouble()).clamp(0.0, max);
    final displayPosition = _dragValue != null
        ? Duration(milliseconds: _dragValue!.round())
        : widget.position;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: widget.accent,
            thumbColor: widget.accent,
            inactiveTrackColor: Colors.white.withValues(alpha: 0.18),
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
          ),
          child: Slider(
            value: value,
            max: max,
            onChanged: totalMs <= 0
                ? null
                : (v) => setState(() => _dragValue = v),
            onChangeEnd: totalMs <= 0
                ? null
                : (v) {
                    widget.onSeek(Duration(milliseconds: v.round()));
                    setState(() => _dragValue = null);
                  },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                formatDuration(displayPosition),
                style: const TextStyle(
                  fontSize: 11.5,
                  color: Color(0xFF8A8A9A),
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                formatDuration(widget.duration),
                style: const TextStyle(
                  fontSize: 11.5,
                  color: Color(0xFF8A8A9A),
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
