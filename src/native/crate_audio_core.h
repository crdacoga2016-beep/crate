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

#ifdef __cplusplus
}
#endif
