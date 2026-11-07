#include "crate_audio_core.h"

#include <algorithm>
#include <cmath>

extern "C" CRATE_AUDIO_CORE_API const char* crate_audio_core_version() {
  return "0.1.0";
}

extern "C" CRATE_AUDIO_CORE_API float crate_audio_core_process_limiter(float* buffer, int num_samples, float ceiling_db) {
  if (buffer == nullptr || num_samples <= 0) {
    return 1.0f;
  }

  const float safeCeilingDb = std::clamp(ceiling_db, -12.0f, 6.0f);
  const float ceiling = std::pow(10.0f, safeCeilingDb / 20.0f);
  float peak = 0.0f;

  for (int index = 0; index < num_samples; ++index) {
    const float sample = buffer[index];
    if (!std::isfinite(sample)) {
      buffer[index] = 0.0f;
      continue;
    }
    peak = std::max(peak, std::abs(sample));
  }

  if (peak <= ceiling) {
    return 1.0f;
  }

  const float gain = ceiling / peak;
  for (int index = 0; index < num_samples; ++index) {
    if (std::isfinite(buffer[index])) {
      buffer[index] *= gain;
    }
  }
  return gain;
}
