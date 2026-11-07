#include "crate_audio_core.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <vector>

extern "C" CRATE_AUDIO_CORE_API const char* crate_audio_core_version() {
  return "0.1.0";
}

extern "C" CRATE_AUDIO_CORE_API float crate_audio_core_measure_true_peak_db(const float* buffer, int num_samples, int sample_rate) {
  if (buffer == nullptr || num_samples <= 0 || sample_rate <= 0) {
    return -96.0f;
  }

  const std::size_t sampleCount = static_cast<std::size_t>(num_samples);
  float peak = 0.0f;
  for (std::size_t index = 0; index < sampleCount; ++index) {
    const float sample = buffer[index];
    if (std::isfinite(sample)) {
      peak = std::max(peak, std::abs(sample));
    }
  }

  for (std::size_t index = 0; index + 1 < sampleCount; ++index) {
    const float p0 = index == 0 ? buffer[index] : buffer[index - 1];
    const float p1 = buffer[index];
    const float p2 = buffer[index + 1];
    const float p3 = index + 2 < sampleCount ? buffer[index + 2] : p2;
    constexpr float fractions[3] = {0.25f, 0.5f, 0.75f};
    for (const float fraction : fractions) {
      const float t = fraction;
      const float t2 = t * t;
      const float t3 = t2 * t;
      const float interpolated = 0.5f * (
        2.0f * p1 +
        (-p0 + p2) * t +
        (2.0f * p0 - 5.0f * p1 + 4.0f * p2 - p3) * t2 +
        (-p0 + 3.0f * p1 - 3.0f * p2 + p3) * t3);
      if (std::isfinite(interpolated)) {
        peak = std::max(peak, std::abs(interpolated));
      }
    }
  }

  if (peak <= 1e-12f) {
    return -96.0f;
  }
  return 20.0f * std::log10(peak);
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

extern "C" CRATE_AUDIO_CORE_API float crate_audio_core_process_limiter_advanced(float* buffer, int num_samples, float ceiling_db, float lookahead_ms, float attack_ms, float release_ms, int sample_rate) {
  if (buffer == nullptr || num_samples <= 0 || sample_rate <= 0) {
    return 1.0f;
  }

  const float safeCeilingDb = std::clamp(ceiling_db, -12.0f, 6.0f);
  const float ceiling = std::pow(10.0f, safeCeilingDb / 20.0f);
  const float safeLookaheadMs = std::clamp(lookahead_ms, 0.0f, 50.0f);
  const float safeAttackMs = std::clamp(attack_ms, 0.01f, 10.0f);
  const float safeReleaseMs = std::clamp(release_ms, 1.0f, 500.0f);
  const std::size_t sampleCount = static_cast<std::size_t>(num_samples);
  const std::size_t delaySamples = std::min(
    sampleCount == 0 ? 0 : sampleCount - 1,
    static_cast<std::size_t>(std::ceil((safeLookaheadMs / 1000.0f) * static_cast<float>(sample_rate))));
  const std::size_t ringSize = delaySamples + 1;
  std::vector<float> delayLine(ringSize, 0.0f);

  for (std::size_t index = 0; index < ringSize; ++index) {
    const float sample = buffer[index];
    delayLine[index] = std::isfinite(sample) ? sample : 0.0f;
  }

  const float attackCoefficient = std::exp(
    -2.2f / ((safeAttackMs / 1000.0f) * static_cast<float>(sample_rate)));
  const float releaseCoefficient = std::exp(
    -1.0f / ((safeReleaseMs / 1000.0f) * static_cast<float>(sample_rate)));
  float currentGain = 1.0f;

  for (std::size_t index = 0; index < sampleCount; ++index) {
    float futurePeak = 0.0f;
    for (std::size_t offset = 0; offset < ringSize; ++offset) {
      futurePeak = std::max(futurePeak, std::abs(delayLine[(index + offset) % ringSize]));
    }
    const float targetGain = futurePeak > ceiling ? ceiling / futurePeak : 1.0f;
    if (targetGain < currentGain) {
      currentGain = targetGain + (currentGain - targetGain) * attackCoefficient;
    } else {
      currentGain = targetGain + (currentGain - targetGain) * releaseCoefficient;
    }
    const float sample = buffer[index];
    buffer[index] = std::isfinite(sample) ? sample * currentGain : 0.0f;
    const std::size_t nextIndex = index + ringSize;
    if (nextIndex < sampleCount) {
      const float futureSample = buffer[nextIndex];
      delayLine[index % ringSize] = std::isfinite(futureSample) ? futureSample : 0.0f;
    }
  }

  return currentGain;
}
