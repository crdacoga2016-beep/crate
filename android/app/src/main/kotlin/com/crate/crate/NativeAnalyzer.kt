package com.crate.crate

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.floor
import kotlin.math.ln
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.min
import kotlin.math.round
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Decodes a short excerpt of the track and computes everything AutoMix needs
 * (BPM, beats/downbeats, lead-in, audible end, mix points, energy and timbre
 * features) in native code, without writing a WAV or doing DSP in Dart.
 */
object NativeAnalyzer {
    private const val TARGET_RATE = 11025
    private const val MAX_SECONDS = 30
    private const val FRAME_SIZE = 2048
    private const val HOP = 512

    fun analyze(path: String): Map<String, Any?>? {
        val decoded = decodeExcerpt(path) ?: return null
        return analyzeSamples(
            decoded.samples,
            decoded.sampleRate,
            decoded.fullDuration,
        )
    }

    private class Decoded(
        val samples: FloatArray,
        val sampleRate: Int,
        val fullDuration: Double,
    )

    private fun decodeExcerpt(path: String): Decoded? {
        var extractor: MediaExtractor? = null
        var codec: MediaCodec? = null
        try {
            extractor = MediaExtractor()
            extractor.setDataSource(path)

            var trackIndex = -1
            var format: MediaFormat? = null
            for (index in 0 until extractor.trackCount) {
                val candidate = extractor.getTrackFormat(index)
                val mime = candidate.getString(MediaFormat.KEY_MIME) ?: continue
                if (mime.startsWith("audio/")) {
                    trackIndex = index
                    format = candidate
                    break
                }
            }
            if (trackIndex < 0 || format == null) return null
            extractor.selectTrack(trackIndex)

            val fullDuration = try {
                format.getLong(MediaFormat.KEY_DURATION) / 1_000_000.0
            } catch (_: Exception) {
                0.0
            }

            val mime = format.getString(MediaFormat.KEY_MIME) ?: return null
            codec = MediaCodec.createDecoderByType(mime)
            codec.configure(format, null, null, 0)
            codec.start()

            var sourceRate = try {
                format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            } catch (_: Exception) {
                TARGET_RATE
            }
            var channels = try {
                format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            } catch (_: Exception) {
                1
            }

            val capacity = MAX_SECONDS * TARGET_RATE
            val pcm = ShortArray(capacity)
            var pcmCount = 0

            var resampleStep = if (sourceRate > TARGET_RATE) {
                sourceRate.toDouble() / TARGET_RATE
            } else {
                1.0
            }
            var resamplePhase = 0.0
            var resampleSum = 0.0
            var resampleCount = 0

            val info = MediaCodec.BufferInfo()
            var inputDone = false
            var outputDone = false

            while (!outputDone) {
                if (!inputDone) {
                    val inputIndex = codec.dequeueInputBuffer(10_000)
                    if (inputIndex >= 0) {
                        val input = codec.getInputBuffer(inputIndex)!!
                        val size = extractor.readSampleData(input, 0)
                        if (size < 0) {
                            codec.queueInputBuffer(
                                inputIndex,
                                0,
                                0,
                                0,
                                MediaCodec.BUFFER_FLAG_END_OF_STREAM,
                            )
                            inputDone = true
                        } else {
                            codec.queueInputBuffer(
                                inputIndex,
                                0,
                                size,
                                extractor.sampleTime,
                                0,
                            )
                            extractor.advance()
                        }
                    }
                }

                val outputIndex = codec.dequeueOutputBuffer(info, 10_000)
                if (outputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    val outputFormat = codec.outputFormat
                    sourceRate = try {
                        outputFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                    } catch (_: Exception) {
                        sourceRate
                    }
                    channels = try {
                        outputFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                    } catch (_: Exception) {
                        channels
                    }
                    resampleStep = if (sourceRate > TARGET_RATE) {
                        sourceRate.toDouble() / TARGET_RATE
                    } else {
                        1.0
                    }
                    continue
                }

                if (outputIndex >= 0) {
                    val buffer = codec.getOutputBuffer(outputIndex)!!
                    if (info.size > 0) {
                        val bytes = ByteArray(info.size)
                        buffer.position(info.offset)
                        buffer.get(bytes)
                        val shorts = ByteBuffer.wrap(bytes)
                            .order(ByteOrder.nativeOrder())
                            .asShortBuffer()
                        val frameCount = shorts.remaining() / channels
                        for (frame in 0 until frameCount) {
                            var sum = 0
                            for (channel in 0 until channels) {
                                sum += shorts.get(frame * channels + channel).toInt()
                            }
                            val mono = sum / channels
                            resampleSum += mono
                            resampleCount++
                            resamplePhase += 1.0
                            if (resamplePhase >= resampleStep) {
                                val value = (resampleSum / resampleCount)
                                    .toInt()
                                    .coerceIn(-32768, 32767)
                                if (pcmCount < pcm.size) {
                                    pcm[pcmCount++] = value.toShort()
                                }
                                resampleSum = 0.0
                                resampleCount = 0
                                resamplePhase -= resampleStep
                                if (pcmCount >= pcm.size) {
                                    outputDone = true
                                    break
                                }
                            }
                        }
                    }
                    codec.releaseOutputBuffer(outputIndex, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                        outputDone = true
                    }
                }
            }

            if (resampleCount > 0 && pcmCount < pcm.size) {
                val value = (resampleSum / resampleCount)
                    .toInt()
                    .coerceIn(-32768, 32767)
                pcm[pcmCount++] = value.toShort()
            }
            if (pcmCount == 0) return null

            val samples = FloatArray(pcmCount)
            for (i in 0 until pcmCount) {
                samples[i] = pcm[i] / 32768f
            }
            return Decoded(samples, TARGET_RATE, fullDuration)
        } catch (_: Exception) {
            return null
        } finally {
            try {
                codec?.stop()
                codec?.release()
            } catch (_: Exception) {
            }
            try {
                extractor?.release()
            } catch (_: Exception) {
            }
        }
    }

    internal fun analyzeSamples(
        samples: FloatArray,
        sampleRate: Int,
        fullDuration: Double,
    ): Map<String, Any?>? {
        if (samples.isEmpty() || sampleRate <= 0) return null

        val wavDuration = samples.size.toDouble() / sampleRate
        val duration = if (fullDuration > wavDuration) fullDuration else wavDuration
        val rms = rmsStats(samples, sampleRate, wavDuration)
        val leadIn = rms.leadIn
        val audibleEnd = if (fullDuration > wavDuration) fullDuration else rms.audibleEnd

        val excerptStart = max(rms.leadIn, wavDuration * 0.15)
        var excerptEnd = min(rms.audibleEnd, excerptStart + 20.0)
        if (excerptEnd - excerptStart < 10.0) {
            excerptEnd = min(wavDuration, excerptStart + 20.0)
        }
        val startIndex = floor(excerptStart * sampleRate)
            .toInt()
            .coerceIn(0, samples.size)
        val endIndex = kotlin.math.ceil(excerptEnd * sampleRate)
            .toInt()
            .coerceIn(startIndex, samples.size)
        val excerpt = if (startIndex < endIndex) {
            samples.copyOfRange(startIndex, endIndex)
        } else {
            samples
        }

        val spectral = spectralFeatures(excerpt, sampleRate)
        val tempo = estimateTempo(spectral.flux, sampleRate)

        val barLength = 4 * 60 / tempo.bpm
        val phase = (excerptStart + tempo.phaseSeconds) % barLength
        val downbeats = ArrayList<Double>()
        var t = phase
        while (t < duration) {
            downbeats.add(t)
            t += barLength
        }

        var mixIn = leadIn
        for (downbeat in downbeats) {
            if (downbeat >= leadIn) {
                mixIn = downbeat
                break
            }
        }
        var mixOut = audibleEnd
        val limit = audibleEnd - 8 * barLength
        for (downbeat in downbeats) {
            if (downbeat <= limit) {
                mixOut = downbeat
            } else {
                break
            }
        }
        if (mixOut <= mixIn + barLength) {
            mixOut = audibleEnd
        }

        val features = ArrayList<Double>(17)
        repeat(12) { features.add(0.0) }
        features.add(((tempo.bpm / 200).coerceIn(0.0, 2.0)))
        features.add(rms.energy)
        features.add((spectral.centroid / 8000).coerceIn(0.0, 2.0))
        features.add(spectral.flatness.coerceIn(0.0, 1.0))
        features.add((spectral.rolloff / 8000).coerceIn(0.0, 2.0))
        features.add(spectral.zcr.coerceIn(0.0, 1.0))

        return mapOf(
            "version" to 5,
            "bpm" to rounded(tempo.bpm, 3),
            "beatsPerBar" to 4,
            "barLength" to rounded(barLength, 4),
            "downbeats" to downbeats.map { rounded(it, 3) },
            "downbeatPhase" to rounded(phase, 3),
            "duration" to rounded(duration, 3),
            "leadIn" to rounded(leadIn, 3),
            "audibleEnd" to rounded(audibleEnd, 3),
            "mixIn" to rounded(mixIn, 3),
            "mixOut" to rounded(mixOut, 3),
            "beatlessIntro" to false,
            "beatlessOutro" to false,
            "energy" to rounded(rms.energy, 4),
            "lufs" to null,
            "peakDb" to rounded(rms.peakDb, 2),
            "keyRoot" to 0,
            "isMinor" to false,
            "key" to "",
            "camelot" to "",
            "keyConfidence" to 0.0,
            "features" to features.map { rounded(it, 5) },
        )
    }

    private class Spectral(
        val flux: DoubleArray,
        val centroid: Double,
        val flatness: Double,
        val rolloff: Double,
        val zcr: Double,
    )

    private fun spectralFeatures(samples: FloatArray, sampleRate: Int): Spectral {
        val spectrumSize = FRAME_SIZE / 2
        val window = hann(FRAME_SIZE)
        val real = DoubleArray(FRAME_SIZE)
        val imaginary = DoubleArray(FRAME_SIZE)
        val previous = DoubleArray(spectrumSize)
        val current = DoubleArray(spectrumSize)
        val flux = ArrayList<Double>()
        var hasPrevious = false
        var centroidSum = 0.0
        var flatnessSum = 0.0
        var rolloffSum = 0.0
        var zcrSum = 0.0
        var frames = 0

        var start = 0
        while (start + FRAME_SIZE <= samples.size) {
            var zeroCrossings = 0
            var previousPositive = samples[start] >= 0f
            for (i in 0 until FRAME_SIZE) {
                val sample = samples[start + i]
                val positive = sample >= 0f
                if (positive != previousPositive) zeroCrossings++
                previousPositive = positive
                real[i] = sample.toDouble() * window[i]
                imaginary[i] = 0.0
            }
            fft(real, imaginary)

            var magnitudeSum = 0.0
            var logSum = 0.0
            var weighted = 0.0
            var energySum = 0.0
            for (bin in 0 until spectrumSize) {
                val magnitude = sqrt(real[bin] * real[bin] + imaginary[bin] * imaginary[bin])
                current[bin] = magnitude
                magnitudeSum += magnitude
                logSum += ln(magnitude + 1e-9)
                weighted += magnitude * bin * sampleRate / FRAME_SIZE
                energySum += magnitude * magnitude
            }

            if (hasPrevious) {
                var difference = 0.0
                for (bin in 0 until spectrumSize) {
                    val delta = current[bin] - previous[bin]
                    if (delta > 0) difference += delta
                }
                flux.add(difference)
            } else {
                flux.add(0.0)
                hasPrevious = true
            }

            centroidSum += if (magnitudeSum > 0) weighted / magnitudeSum else 0.0
            flatnessSum += if (magnitudeSum > 0) {
                exp(logSum / spectrumSize) / (magnitudeSum / spectrumSize)
            } else {
                0.0
            }

            var cumulative = 0.0
            var rolloff = 0.0
            val target = energySum * 0.85
            for (bin in 0 until spectrumSize) {
                cumulative += current[bin] * current[bin]
                if (cumulative >= target) {
                    rolloff = bin.toDouble() * sampleRate / FRAME_SIZE
                    break
                }
            }
            rolloffSum += rolloff
            zcrSum += zeroCrossings.toDouble() / FRAME_SIZE
            frames++
            System.arraycopy(current, 0, previous, 0, spectrumSize)
            start += HOP
        }

        val divisor = if (frames == 0) 1 else frames
        return Spectral(
            flux.toDoubleArray(),
            centroidSum / divisor,
            flatnessSum / divisor,
            rolloffSum / divisor,
            zcrSum / divisor,
        )
    }

    private class Tempo(val bpm: Double, val phaseSeconds: Double)

    private fun estimateTempo(flux: DoubleArray, sampleRate: Int): Tempo {
        if (flux.size < 16) return Tempo(120.0, 0.0)
        val frameRate = sampleRate.toDouble() / HOP
        var mean = 0.0
        for (value in flux) mean += value
        mean /= flux.size
        val normalized = DoubleArray(flux.size) { flux[it] - mean }
        val minLag = max(1, round(frameRate * 60 / 200).toInt())
        val maxLag = min(normalized.size - 2, round(frameRate * 60 / 60).toInt())
        if (maxLag < minLag) return Tempo(120.0, 0.0)

        val correlations = DoubleArray(maxLag + 1)
        for (lag in minLag..maxLag) {
            var sum = 0.0
            var i = 0
            while (i < normalized.size - lag) {
                sum += normalized[i] * normalized[i + lag]
                i++
            }
            correlations[lag] = sum / (normalized.size - lag)
        }

        class Candidate(val bpm: Double, val corr: Double, val beat: Double, val lag: Int)

        val candidates = ArrayList<Candidate>()
        for (lag in minLag..maxLag) {
            if (lag > minLag && correlations[lag] < correlations[lag - 1]) continue
            if (lag < maxLag && correlations[lag] < correlations[lag + 1]) continue
            var bestBeat = 0.0
            for (phase in 0 until lag) {
                var sum = 0.0
                var count = 0
                var position = phase
                while (position < flux.size) {
                    sum += flux[position]
                    count++
                    position += lag
                }
                val score = if (count == 0) 0.0 else sum / count
                if (score > bestBeat) bestBeat = score
            }
            candidates.add(
                Candidate(frameRate * 60 / lag, correlations[lag], bestBeat, lag),
            )
        }
        if (candidates.isEmpty()) return Tempo(120.0, 0.0)

        var maxCorr = 0.0
        var maxBeat = 0.0
        for (candidate in candidates) {
            if (candidate.corr > maxCorr) maxCorr = candidate.corr
            if (candidate.beat > maxBeat) maxBeat = candidate.beat
        }
        if (maxCorr <= 0) maxCorr = 1.0
        if (maxBeat <= 0) maxBeat = 1.0

        var best = candidates[0]
        var bestScore = -1.0
        for (candidate in candidates) {
            val prior = tempoPrior(candidate.bpm)
            val score = (0.55 * candidate.corr / maxCorr +
                0.45 * candidate.beat / maxBeat) * prior
            if (score > bestScore) {
                bestScore = score
                best = candidate
            }
        }

        var bestPhase = 0
        var bestPhaseScore = -1.0
        for (phase in 0 until best.lag) {
            var sum = 0.0
            var count = 0
            var position = phase
            while (position < flux.size) {
                sum += flux[position]
                count++
                position += best.lag
            }
            val score = if (count == 0) 0.0 else sum / count
            if (score > bestPhaseScore) {
                bestPhaseScore = score
                bestPhase = phase
            }
        }
        return Tempo(best.bpm, bestPhase.toDouble() * HOP / sampleRate)
    }

    private fun tempoPrior(bpm: Double): Double {
        val x = ln(bpm / 120) / ln(2.0)
        return exp(-0.5 * (x / 0.65) * (x / 0.65))
    }

    private class Rms(
        val leadIn: Double,
        val audibleEnd: Double,
        val energy: Double,
        val peakDb: Double,
    )

    private fun rmsStats(
        samples: FloatArray,
        sampleRate: Int,
        duration: Double,
    ): Rms {
        val rms = DoubleArray((samples.size / HOP) + 1)
        var count = 0
        var maxRms = 0.0
        var peak = 0.0
        var start = 0
        while (start + FRAME_SIZE <= samples.size) {
            var sum = 0.0
            for (i in 0 until FRAME_SIZE) {
                val sample = samples[start + i].toDouble()
                sum += sample * sample
                val absolute = abs(sample)
                if (absolute > peak) peak = absolute
            }
            val value = sqrt(sum / FRAME_SIZE)
            rms[count++] = value
            if (value > maxRms) maxRms = value
            start += HOP
        }

        val threshold = maxRms * 0.02
        var first = -1
        var last = -1
        for (i in 0 until count) {
            if (rms[i] >= threshold) {
                if (first < 0) first = i
                last = i
            }
        }
        val leadIn = if (first < 0) 0.0 else first.toDouble() * HOP / sampleRate
        val audibleEnd = if (last < 0) {
            duration
        } else {
            min(duration, (last * HOP + FRAME_SIZE).toDouble() / sampleRate)
        }
        var energySum = 0.0
        for (i in 0 until count) energySum += rms[i]
        val energy = if (maxRms > 0 && count > 0) {
            (energySum / count / maxRms).coerceIn(0.0, 1.0)
        } else {
            0.0
        }
        val peakDb = if (peak > 0) 20 * log10(peak) else -96.0
        return Rms(leadIn, audibleEnd, energy, peakDb)
    }

    private fun hann(size: Int): DoubleArray {
        val window = DoubleArray(size)
        for (i in 0 until size) {
            window[i] = 0.5 * (1 - cos(2 * Math.PI * i / (size - 1)))
        }
        return window
    }

    private fun fft(real: DoubleArray, imaginary: DoubleArray) {
        val n = real.size
        var j = 0
        for (i in 1 until n) {
            var bit = n shr 1
            while (j and bit != 0) {
                j = j xor bit
                bit = bit shr 1
            }
            j = j or bit
            if (i < j) {
                val tr = real[i]
                real[i] = real[j]
                real[j] = tr
                val ti = imaginary[i]
                imaginary[i] = imaginary[j]
                imaginary[j] = ti
            }
        }
        var length = 2
        while (length <= n) {
            val angle = -2.0 * Math.PI / length
            val wLengthReal = cos(angle)
            val wLengthImaginary = sin(angle)
            var i = 0
            while (i < n) {
                var wReal = 1.0
                var wImaginary = 0.0
                val half = length / 2
                for (k in 0 until half) {
                    val uReal = real[i + k]
                    val uImaginary = imaginary[i + k]
                    val vReal = real[i + k + half] * wReal -
                        imaginary[i + k + half] * wImaginary
                    val vImaginary = real[i + k + half] * wImaginary +
                        imaginary[i + k + half] * wReal
                    real[i + k] = uReal + vReal
                    imaginary[i + k] = uImaginary + vImaginary
                    real[i + k + half] = uReal - vReal
                    imaginary[i + k + half] = uImaginary - vImaginary
                    val nextReal = wReal * wLengthReal - wImaginary * wLengthImaginary
                    wImaginary = wReal * wLengthImaginary + wImaginary * wLengthReal
                    wReal = nextReal
                }
                i += length
            }
            length = length shl 1
        }
    }

    private fun rounded(value: Double, places: Int): Double {
        if (!value.isFinite()) return 0.0
        val factor = Math.pow(10.0, places.toDouble())
        return round(value * factor) / factor
    }
}
