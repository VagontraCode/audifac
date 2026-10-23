package com.gtongfa.audifac.dsp

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.Random

class ConvolutionTest {
    private val rate = 48_000
    private val block = 1024 // short responses

    private fun run(c: Convolver, input: FloatArray, chunk: Int = 777): FloatArray {
        val out = input.copyOf()
        var f = 0
        val frames = input.size / 2
        while (f < frames) {
            val n = minOf(chunk, frames - f)
            c.process(out, n, f * 2)
            f += n
        }
        return out
    }

    private fun noise(frames: Int, seed: Long) = Random(seed).let { r -> FloatArray(frames * 2) { r.nextFloat() - 0.5f } }

    @Test
    fun identityResponseOnlyDelaysByOneBlock() {
        val c = Convolver(ImpulseResponse("id", rate, listOf(floatArrayOf(1f))), rate, 2)
        assertEquals(1.0, c.gain, 1e-9)
        val input = noise(10_000, 1)
        val out = run(c, input)
        for (i in 0 until (10_000 - block) * 2) assertEquals(input[i], out[i + block * 2], 1e-5f)
        for (i in 0 until block * 2) assertEquals(0f, out[i], 1e-6f)
    }

    @Test
    fun matchesDirectConvolution() {
        // Stereo response, 3000 taps (3 partitions): left and right differ.
        val r = Random(7)
        val hl = FloatArray(3000) { (r.nextFloat() - 0.5f) * 0.1f }
        val hr = FloatArray(3000) { (r.nextFloat() - 0.5f) * 0.1f }
        val c = Convolver(ImpulseResponse("st", rate, listOf(hl, hr)), rate, 2)
        val input = noise(9000, 3)
        val out = run(c, input)
        for (t in 4000 until 9000 - block step 37) {
            var el = 0.0
            var er = 0.0
            for (k in hl.indices) {
                val s = t - k
                if (s < 0) break
                el += hl[k] * input[s * 2]
                er += hr[k] * input[s * 2 + 1]
            }
            assertEquals(el * c.gain, out[(t + block) * 2].toDouble(), 1e-5)
            assertEquals(er * c.gain, out[(t + block) * 2 + 1].toDouble(), 1e-5)
        }
    }

    @Test
    fun trueStereoCrossPaths() {
        // Only L→R: a delayed copy of the left input appears on the right.
        val zero = FloatArray(200)
        val lr = FloatArray(200).also { it[100] = 1f }
        val c = Convolver(ImpulseResponse("x", rate, listOf(zero, lr, zero, zero)), rate, 2)
        val input = noise(6000, 5)
        val out = run(c, input)
        for (t in 2000 until 4000) {
            assertEquals(0f, out[(t + block) * 2], 1e-5f)
            assertEquals(input[(t - 100) * 2], out[(t + block) * 2 + 1], 1e-5f)
        }
    }

    @Test
    fun responseAtAnotherRateIsConverted() {
        // A 44.1 kHz single impulse stays (close to) an impulse at 48 kHz: unity gain overall.
        val ir = ImpulseResponse("r", 44_100, listOf(FloatArray(64).also { it[0] = 1f }))
        val c = Convolver(ir, rate, 2)
        val input = FloatArray(8000 * 2) { 0.25f } // DC
        val out = run(c, input)
        assertEquals(0.25f, out[6000 * 2], 2e-3f)
    }

    private fun wav(channels: Int, frames: Int, sample: (Int, Int) -> Short): ByteArray {
        val data = frames * channels * 2
        val b = ByteBuffer.allocate(44 + data).order(ByteOrder.LITTLE_ENDIAN)
        b.put("RIFF".toByteArray()).putInt(36 + data).put("WAVE".toByteArray())
        b.put("fmt ".toByteArray()).putInt(16).putShort(1).putShort(channels.toShort()).putInt(rate)
            .putInt(rate * channels * 2).putShort((channels * 2).toShort()).putShort(16)
        b.put("data".toByteArray()).putInt(data)
        for (f in 0 until frames) for (c in 0 until channels) b.putShort(sample(f, c))
        return b.array()
    }

    @Test
    fun readsWavFiles() {
        val ir = ImpulseResponse.parseWav(wav(2, 10) { f, c -> if (f == 0) (if (c == 0) 16384 else -16384).toShort() else 0 }, "t")
        assertNotNull(ir)
        ir!!
        assertEquals(rate, ir.rate)
        assertEquals(2, ir.channels.size)
        assertEquals(10, ir.frames)
        assertEquals(0.5f, ir.channels[0][0], 1e-6f)
        assertEquals(-0.5f, ir.channels[1][0], 1e-6f)
        // 3 channels: not a layout we know.
        assertNull(ImpulseResponse.parseWav(wav(3, 10) { _, _ -> 0 }, "t"))
        assertNull(ImpulseResponse.parseWav("not a wav file".toByteArray(), "t"))
    }

    @Test
    fun longResponsesUseLongerBlocks() {
        assertEquals(1024, Convolver.blockFor(1))
        assertEquals(1024, Convolver.blockFor(8000))
        assertEquals(4096, Convolver.blockFor(24_000))
        assertEquals(8192, Convolver.blockFor(1 shl 17))
        // Still exact: a delay of 20 000 frames through 4096-frame blocks.
        val h = FloatArray(24_000).also { it[20_000] = 1f }
        val c = Convolver(ImpulseResponse("d", rate, listOf(h)), rate, 2)
        assertEquals(4096, c.block)
        val input = noise(40_000, 9)
        val out = run(c, input)
        for (t in 21_000 until 40_000 - c.block) assertEquals(input[(t - 20_000) * 2], out[(t + c.block) * 2], 1e-5f)
    }
}
