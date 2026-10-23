// Hot loops of the DSP, in C++ with NEON (4 multiply-adds per instruction).
// The Kotlin side owns all state; these functions only do the arithmetic.

#include <jni.h>
#include <cstdint>
#if defined(__aarch64__)
#include <arm_neon.h>
#endif

namespace {

// Dot products of one filter phase with the left and right histories.
// w, l and r all run forward (the table is stored reversed for this).
inline void dot2(const float* w, const float* l, const float* r, int n, float& outL, float& outR) {
    int j = 0;
    float accL = 0.f, accR = 0.f;
#if defined(__aarch64__)
    float32x4_t sl = vdupq_n_f32(0.f), sr = vdupq_n_f32(0.f);
    float32x4_t sl2 = vdupq_n_f32(0.f), sr2 = vdupq_n_f32(0.f);
    for (; j + 8 <= n; j += 8) {
        float32x4_t w0 = vld1q_f32(w + j), w1 = vld1q_f32(w + j + 4);
        sl = vfmaq_f32(sl, w0, vld1q_f32(l + j));
        sr = vfmaq_f32(sr, w0, vld1q_f32(r + j));
        sl2 = vfmaq_f32(sl2, w1, vld1q_f32(l + j + 4));
        sr2 = vfmaq_f32(sr2, w1, vld1q_f32(r + j + 4));
    }
    accL = vaddvq_f32(vaddq_f32(sl, sl2));
    accR = vaddvq_f32(vaddq_f32(sr, sr2));
#endif
    for (; j < n; j++) {
        accL += w[j] * l[j];
        accR += w[j] * r[j];
    }
    outL = accL;
    outR = accR;
}

}  // namespace

extern "C" JNIEXPORT jint JNICALL
Java_com_gtongfa_audifac_dsp_NativeDsp_produceStereo(
        JNIEnv* env, jclass, jfloatArray jTableRev, jint taps, jint up, jint down, jlong delay,
        jfloatArray jL, jfloatArray jR, jlong histStart, jlong lastIn, jlong outCount, jint max,
        jfloatArray jOut) {
    auto* table = static_cast<float*>(env->GetPrimitiveArrayCritical(jTableRev, nullptr));
    auto* l = static_cast<float*>(env->GetPrimitiveArrayCritical(jL, nullptr));
    auto* r = static_cast<float*>(env->GetPrimitiveArrayCritical(jR, nullptr));
    auto* out = static_cast<float*>(env->GetPrimitiveArrayCritical(jOut, nullptr));
    int n = 0;
    if (table && l && r && out) {
        while (n < max) {
            const int64_t pos = outCount * down + delay;
            int64_t i = pos / up;
            if (pos < 0 && pos % up != 0) i--;  // floor division
            if (i > lastIn) break;
            const int phase = static_cast<int>(pos - i * up);
            // Newest needed input is x[i]; the window is x[i - taps + 1 .. i].
            const int64_t first = i - taps + 1 - histStart;
            dot2(table + static_cast<int64_t>(phase) * taps, l + first, r + first, taps, out[2 * n], out[2 * n + 1]);
            n++;
            outCount++;
        }
    }
    if (out) env->ReleasePrimitiveArrayCritical(jOut, out, 0);
    if (r) env->ReleasePrimitiveArrayCritical(jR, r, JNI_ABORT);
    if (l) env->ReleasePrimitiveArrayCritical(jL, l, JNI_ABORT);
    if (table) env->ReleasePrimitiveArrayCritical(jTableRev, table, JNI_ABORT);
    return n;
}
