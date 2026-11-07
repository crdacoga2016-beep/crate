#pragma once

#if defined(_WIN32) && defined(CRATE_AUDIO_CORE_EXPORTS)
#define CRATE_AUDIO_CORE_API __declspec(dllexport)
#else
#define CRATE_AUDIO_CORE_API
#endif

#ifdef __cplusplus
extern "C" {
#endif

CRATE_AUDIO_CORE_API const char* crate_audio_core_version(void);
CRATE_AUDIO_CORE_API float crate_audio_core_process_limiter(float* buffer, int num_samples, float ceiling_db);
CRATE_AUDIO_CORE_API float crate_audio_core_process_limiter_advanced(float* buffer, int num_samples, float ceiling_db, float lookahead_ms, float attack_ms, float release_ms, int sample_rate);

#ifdef __cplusplus
}
#endif
