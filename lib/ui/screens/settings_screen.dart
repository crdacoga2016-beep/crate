import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        final wide = MediaQuery.sizeOf(context).width >= 760;
        final pad = wide ? 32.0 : 16.0;

        return ListView(
          padding: EdgeInsets.fromLTRB(pad, wide ? 30 : 18, pad, 32),
          children: [
            Text(
              'Ajustes',
              style: TextStyle(
                fontSize: wide ? 32 : 26,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.6,
              ),
            ),
            const SizedBox(height: 20),
            _Section(
              title: 'Biblioteca',
              children: [
                for (final root in state.musicRoots)
                  ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(
                      root,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: IconButton(
                      tooltip: 'Quitar carpeta',
                      onPressed: () => state.removeRoot(root),
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
                  ),
                ListTile(
                  leading: const Icon(Icons.create_new_folder_outlined),
                  title: const Text('Añadir carpeta'),
                  subtitle: const Text(
                    'Salsa, bachata, rock… todas las que quieras',
                  ),
                  trailing: const Icon(Icons.add_rounded),
                  onTap: () => _addRoot(context, state),
                ),
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Añadir ruta manual'),
                  subtitle: const Text('Ej: /storage/emulated/0/Music'),
                  onTap: () => _addManualRoot(context, state),
                ),
                ListTile(
                  leading: Icon(
                    state.scanning
                        ? Icons.hourglass_top_rounded
                        : Icons.refresh_rounded,
                  ),
                  title: const Text('Volver a escanear'),
                  subtitle: Text(
                    state.scanning
                        ? '${state.scanDone} / ${state.scanTotal}'
                        : 'Lee etiquetas y portadas de tus archivos',
                  ),
                  trailing: FilledButton(
                    onPressed: state.scanning ? null : state.rescan,
                    child: const Text('Escanear'),
                  ),
                ),
                if (Platform.isWindows && state.musicRoots.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.open_in_new_rounded),
                    title: const Text('Abrir primera carpeta'),
                    onTap: () =>
                        Process.run('explorer', [state.musicRoots.first]),
                  ),
                ListTile(
                  leading: const Icon(Icons.auto_awesome_rounded),
                  title: const Text('Análisis musical'),
                  subtitle: Text(
                    state.analyzing
                        ? 'Analizando ${state.analysisDone}/${state.analysisTotal}'
                            ' · ${state.analysisCurrent}'
                        : '${state.library.where((t) => t.analysis != null).length} '
                            'de ${state.library.length} pistas con BPM y beats',
                  ),
                  trailing: state.analyzing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : TextButton(
                          onPressed: () => _analyzeAll(context, state),
                          child: const Text('Analizar todo'),
                        ),
                ),
                SwitchListTile(
                  value: state.autoAnalyze,
                  onChanged: state.setAutoAnalyze,
                  secondary: const Icon(Icons.auto_awesome_rounded),
                  title: const Text('Analizar automáticamente'),
                  subtitle: const Text(
                    'Analiza la pista actual y las siguientes',
                  ),
                ),
                if (Platform.isAndroid)
                  ListTile(
                    leading: Icon(
                      state.notificationReady
                          ? Icons.notifications_active_outlined
                          : Icons.notifications_off_outlined,
                    ),
                    title: const Text(
                      'Notificación y pantalla bloqueada',
                    ),
                    subtitle: Text(
                      state.notificationSummary,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    isThreeLine: true,
                    trailing: Icon(
                      state.notificationReady
                          ? Icons.check_circle_outline
                          : Icons.error_outline,
                      color: state.notificationReady
                          ? Colors.green
                          : Colors.orange,
                    ),
                  ),
                if (Platform.isAndroid)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () =>
                                state.requestNotificationPermission(force: true),
                            child: const Text('Permiso'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              final ok =
                                  await state.testNotification();
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    ok
                                        ? 'Notificación de prueba enviada'
                                        : 'No se pudo enviar la notificación',
                                  ),
                                ),
                              );
                            },
                            child: const Text('Probar'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: state.openNotificationSettings,
                            child: const Text('Ajustes'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ListTile(
                  leading: const Icon(Icons.file_open_outlined),
                  title: const Text('Importar analysis.json'),
                  subtitle: const Text(
                    'Desde el PC, para AutoMix con BPM y beats',
                  ),
                  trailing: TextButton(
                    onPressed: () => _importAnalysis(context, state),
                    child: const Text('Importar'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _Section(
              title: 'Reproducción',
              children: [
                SwitchListTile(
                  value: state.automix,
                  onChanged: state.setAutomix,
                  secondary: const Icon(Icons.auto_awesome_rounded),
                  title: const Text('AutoMix'),
                  subtitle: const Text(
                    'Transiciones beat-matched entre canciones',
                  ),
                ),
                SwitchListTile(
                  value: state.crossfade,
                  onChanged: state.setCrossfade,
                  secondary: const Icon(Icons.compare_arrows_rounded),
                  title: const Text('Crossfade'),
                  subtitle: const Text('Mezcla el final con el inicio'),
                ),
                ListTile(
                  leading: const Icon(Icons.timer_outlined),
                  title: const Text('Duración del crossfade'),
                  subtitle: Slider(
                    value: state.crossfadeSeconds,
                    min: 1,
                    max: 12,
                    divisions: 11,
                    label: '${state.crossfadeSeconds.round()} s',
                    onChanged:
                        state.crossfade ? state.setCrossfadeSeconds : null,
                  ),
                  trailing: Text('${state.crossfadeSeconds.round()} s'),
                ),
                SwitchListTile(
                  value: state.gapless,
                  onChanged: state.setGapless,
                  secondary: const Icon(Icons.link_rounded),
                  title: const Text('Reproducción sin pausas'),
                  subtitle: const Text('Elimina el silencio entre pistas'),
                ),
                SwitchListTile(
                  value: state.skipSilence,
                  onChanged: state.setSkipSilence,
                  secondary: const Icon(Icons.content_cut_rounded),
                  title: const Text('Saltar silencio'),
                  subtitle: const Text(
                    'Salta silencios al inicio y final de cada pista',
                  ),
                ),
                SwitchListTile(
                  value: state.normalize,
                  onChanged: state.setNormalize,
                  secondary: const Icon(Icons.graphic_eq_rounded),
                  title: const Text('Normalizar volumen'),
                  subtitle: const Text('Iguala el volumen entre canciones'),
                ),
                SwitchListTile(
                  value: state.smartShuffle,
                  onChanged: state.setSmartShuffle,
                  secondary: const Icon(Icons.psychology_alt_rounded),
                  title: const Text('Smart Shuffle'),
                  subtitle: const Text(
                    'Recomendaciones por similitud acústica (opcional)',
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.auto_awesome_motion_rounded),
                  title: const Text('Estilo de transición'),
                  subtitle: const Text(
                    'Auto usa tempo/energía; puedes forzar uno',
                  ),
                  trailing: DropdownButton<String>(
                    value: state.transitionStyle,
                    dropdownColor: const Color(0xFF1B1B25),
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(value: 'auto', child: Text('Auto')),
                      DropdownMenuItem(value: 'latin', child: Text('Latino')),
                      DropdownMenuItem(value: 'dance', child: Text('Dance')),
                      DropdownMenuItem(value: 'hipHop', child: Text('Hip-Hop')),
                      DropdownMenuItem(value: 'pop', child: Text('Pop')),
                      DropdownMenuItem(value: 'ballad', child: Text('Balada')),
                      DropdownMenuItem(value: 'smooth', child: Text('Suave')),
                    ],
                    onChanged: (value) {
                      if (value != null) state.setTransitionStyle(value);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _Section(
              title: 'Sonido',
              children: [
                ListTile(
                  leading: const Icon(Icons.bolt_rounded),
                  title: const Text('Preamp'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Slider(
                        value: state.preampDb.clamp(-12, 6),
                        min: -12,
                        max: 6,
                        divisions: 90,
                        label: '${state.preampDb.toStringAsFixed(1)} dB',
                        onChanged: state.setPreamp,
                      ),
                      const Text(
                        'Pasos de 0.2 dB. Si distorsiona, usa -1.0 o menos.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF8A8A9A),
                        ),
                      ),
                    ],
                  ),
                  trailing: TextButton(
                    onPressed: () => _preampDialog(context, state),
                    child: Text('${state.preampDb.toStringAsFixed(1)} dB'),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.speaker_rounded),
                  title: const Text('Graves'),
                  subtitle: Slider(
                    value: state.bassDb,
                    min: -12,
                    max: 12,
                    divisions: 24,
                    label: '${state.bassDb.toStringAsFixed(1)} dB',
                    onChanged: state.setBass,
                  ),
                  trailing: Text('${state.bassDb.toStringAsFixed(1)} dB'),
                ),
                ListTile(
                  leading: const Icon(Icons.hearing_rounded),
                  title: const Text('Agudos'),
                  subtitle: Slider(
                    value: state.trebleDb,
                    min: -12,
                    max: 12,
                    divisions: 24,
                    label: '${state.trebleDb.toStringAsFixed(1)} dB',
                    onChanged: state.setTreble,
                  ),
                  trailing: Text('${state.trebleDb.toStringAsFixed(1)} dB'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _Section(
              title: 'Acerca de',
              children: const [
                ListTile(
                  leading: Icon(Icons.info_outline_rounded),
                  title: Text('Crate'),
                  subtitle: Text(
                    'Reproductor local con AutoMix. v0.5.0',
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.storage_rounded),
                  title: Text('100% local'),
                  subtitle: Text(
                    'Tu música nunca sale de tu dispositivo.',
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Future<void> _preampDialog(
    BuildContext context,
    AppState state,
  ) async {
    final controller = TextEditingController(
      text: state.preampDb.toStringAsFixed(1),
    );
    final result = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF15151E),
        title: const Text('Preamp (dB)'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '-1.0',
            helperText: 'Rango -12 a +6 dB. Si distorsiona, baja.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final value = double.tryParse(controller.text.trim());
              Navigator.of(dialogContext).pop(value);
            },
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result != null) state.setPreamp(result);
  }

  Future<void> _importAnalysis(
    BuildContext context,
    AppState state,
  ) async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      dialogTitle: 'Elegir analysis.json',
    );
    final path = files.isNotEmpty ? files.first.path : null;
    if (path == null || path.isEmpty) return;
    final result = await state.importAnalysis(path);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.ok
              ? 'Análisis importado: ${result.entries} pistas. '
                  'Coincidencias: ${result.matches}/${result.total}.'
              : 'No se pudo importar el análisis.',
        ),
      ),
    );
  }

  Future<void> _analyzeAll(
    BuildContext context,
    AppState state,
  ) async {
    if (Platform.isAndroid && state.isPlaying) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pausa la reproducción para analizar'),
        ),
      );
      return;
    }
    await state.analyzeNow();
  }

  Future<void> _addRoot(BuildContext context, AppState state) async {
    final path = await FilePicker.getDirectoryPath(
      dialogTitle: 'Elegir carpeta de música',
    );
    if (path != null && path.isNotEmpty) {
      await state.addRoot(path);
    }
  }

  Future<void> _addManualRoot(BuildContext context, AppState state) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF15151E),
        title: const Text('Añadir ruta de música'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '/storage/emulated/0/Music',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Añadir y escanear'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      await state.addRoot(result);
    }
    controller.dispose();
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 6, bottom: 8),
          child: Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 10.5,
              letterSpacing: 1.3,
              color: Color(0xFF8A8A9A),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF15151E),
            borderRadius: BorderRadius.circular(14),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(children: children),
        ),
      ],
    );
  }
}



