# Changelog

## 0.5.0

- Analizador nativo en Android (`NativeAnalyzer.kt`): decodificación con
  `MediaCodec`, FFT, autocorrelación y downbeats en Kotlin. Fallback al método
  WAV + Dart.
- AutoMix multi-género: sin tonalidad/Camelot ni selección por género; usa
  BPM y energía.
- Notificación y pantalla bloqueada en Android con `CrateMediaService`
  (`MediaSessionCompat` + foreground service) reemplazando `audio_service`.
- `MainActivity` con `FlutterEngine` cacheado para conservar la reproducción
  al recrear la Activity.
- Ajustes de notificación con estado, permiso, prueba y acceso a los ajustes
  del sistema.
- Windows y Android: versión 0.5.0+14.

## 0.4.x

- Notificación/lockscreen y MediaSession iniciales.
- AutoMix con BPM/beats, crossfade, EQ, normalización y preamp.
- Análisis en dispositivo y análisis opcional con Python/librosa en PC.
- Interfaz responsive, cola, búsqueda y biblioteca multi-carpeta.

## 0.3.x

- Análisis musical en el dispositivo.
- Correcciones de UTF-8 en textos.

## 0.2.x

- EQ/bass swap, fase, normalización, multi-carpeta y preamp.
