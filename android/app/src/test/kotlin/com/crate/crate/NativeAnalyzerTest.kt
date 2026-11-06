package com.crate.crate

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.exp
import kotlin.random.Random

class NativeAnalyzerTest {
    private fun clickTrack(rate: Int, seconds: Int, bpm: Double): FloatArray {
        val samples = FloatArray(rate * seconds)
        val random = Random(7)
        val interval = 60.0 / bpm
        var time = 0.0
        while (time < seconds - 0.2) {
            val start = (time * rate).toInt()
            for (i in 0 until 140) {
                val index = start + i
                if (index >= samples.size) break
                val envelope = exp(-i / 28.0).toFloat()
                samples[index] = (random.nextFloat() * 2f - 1f) * envelope
            }
            time += interval
        }
        return samples
    }

    private fun analyze(bpm: Double) {
        val rate = 11025
        val seconds = 24
        val samples = clickTrack(rate, seconds, bpm)
        val result = NativeAnalyzer.analyzeSamples(samples, rate, seconds.toDouble())
        assertTrue("analysis should not be null", result != null)
        val detected = (result!!["bpm"] as Double)
        assertEquals(bpm, detected, 4.0)
        val features = result["features"] as List<*>
        assertEquals(18, features.size)
        val mixIn = result["mixIn"] as Double
        val mixOut = result["mixOut"] as Double
        assertTrue("mixOut must be after mixIn", mixOut > mixIn)
    }

    @Test
    fun detects120Bpm() {
        analyze(120.0)
    }

    @Test
    fun detects90Bpm() {
        analyze(90.0)
    }

    @Test
    fun detects128Bpm() {
        analyze(128.0)
    }
}
