import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import '../../util/eq_model.dart';

class EqWidget extends StatelessWidget {
  const EqWidget({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final headroom = state.eqSmartHeadroomDb;
    final sacrificed = headroom < -0.05;
    final presetId = state.selectedEqPresetId;
    final presetValue = eqPresetById(presetId) != null ? presetId : 'custom';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<AudioOutputProfile>(
                  key: ValueKey(state.eqOutput),
                  initialValue: state.eqOutput,
                  decoration: const InputDecoration(labelText: 'Dispositivo'),
                  items: [
                    for (final profile in AudioOutputProfile.values)
                      DropdownMenuItem(
                        value: profile,
                        child: Text(profile.label),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) state.selectEqOutput(value);
                  },
                ),
              ),
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<String>(
                  key: ValueKey(presetValue),
                  initialValue: presetValue,
                  decoration: const InputDecoration(labelText: 'Preset'),
                  items: [
                    for (final preset in eqPresets)
                      DropdownMenuItem(
                        value: preset.id,
                        child: Text(preset.label),
                      ),
                    const DropdownMenuItem(
                      value: 'custom',
                      child: Text('Personalizado'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null && value != 'custom') {
                      state.applyEqPreset(value);
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Bypass'),
            subtitle: const Text(
              'Mantiene la curva guardada sin aplicar el EQ',
            ),
            value: state.eqBypass,
            onChanged: state.setEqBypass,
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 120,
            child: CustomPaint(painter: _EqCurvePainter(state.currentEq)),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: sacrificed
                  ? const Color(0x33FFC107)
                  : const Color(0x221B5E20),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  sacrificed
                      ? Icons.warning_amber_rounded
                      : Icons.check_circle_outline,
                  color: sacrificed ? const Color(0xFFFFC107) : Colors.green,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Headroom automático: ${headroom.toStringAsFixed(1)} dB',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        sacrificed
                            ? 'Volumen reducido para evitar clipping'
                            : 'Sin reducción de volumen por el EQ',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFFB9B9C7),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 680 ? 5 : 2;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: eqBandFrequencies.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  childAspectRatio: 2.1,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 10,
                ),
                itemBuilder: (context, index) {
                  final frequency = eqBandFrequencies[index];
                  final gain = state.eqGainsDb[index];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(_frequencyLabel(frequency)),
                          Text(
                            '${gain.toStringAsFixed(1)} dB',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFFB9B9C7),
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: gain,
                        min: eqMinimumGainDb,
                        max: eqMaximumGainDb,
                        divisions: 48,
                        label: '${gain.toStringAsFixed(1)} dB',
                        onChanged: state.eqBypass
                            ? null
                            : (value) => state.setEqBand(index, value),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

String _frequencyLabel(int frequency) {
  if (frequency < 1000) return '$frequency Hz';
  return '${(frequency / 1000).toStringAsFixed(1)} kHz';
}

class _EqCurvePainter extends CustomPainter {
  const _EqCurvePainter(this.eq);

  final EqState eq;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final gridPaint = Paint()
      ..color = const Color(0xFF2A2A35)
      ..strokeWidth = 1;
    final zeroPaint = Paint()
      ..color = const Color(0xFF4A4A58)
      ..strokeWidth = 1.2;
    final curvePaint = Paint()
      ..color = const Color(0xFF7B8CFF)
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final gainDb in [-12.0, -6.0, 0.0, 6.0, 12.0]) {
      final y = _gainToY(gainDb, size.height);
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        gainDb == 0.0 ? zeroPaint : gridPaint,
      );
    }

    final path = Path();
    const points = 180;
    for (var index = 0; index <= points; index++) {
      final fraction = index / points;
      final frequency = 20.0 * math.pow(1000.0, fraction).toDouble();
      final response = eq.responseDbAtHz(frequency);
      final x = _frequencyToX(frequency, size.width);
      final y = _gainToY(response, size.height);
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, curvePaint);

    final pointPaint = Paint()..color = const Color(0xFFBBD7FF);
    for (final frequency in eqBandFrequencies) {
      final response = eq.responseDbAtHz(frequency.toDouble());
      canvas.drawCircle(
        Offset(
          _frequencyToX(frequency.toDouble(), size.width),
          _gainToY(response, size.height),
        ),
        2.6,
        pointPaint,
      );
    }
  }

  double _frequencyToX(double frequency, double width) {
    return width * math.log(frequency / 20.0) / math.log(1000.0);
  }

  double _gainToY(double gainDb, double height) {
    final clamped = gainDb.clamp(-15.0, 15.0);
    return height / 2.0 - clamped / 30.0 * height;
  }

  @override
  bool shouldRepaint(covariant _EqCurvePainter oldDelegate) {
    return oldDelegate.eq != eq;
  }
}
