// Hot loops of the DSP, in C++ with NEON (4 multiply-adds per instruction).
// The Kotlin side owns all state; these functions only do the arithmetic.

#include <jni.h>
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <vector>
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

// ---------------------------------------------------------------------------
// Partitioned convolution: the same algorithm as the Kotlin Convolver
// (Convolution.kt), in float, for speed. Kotlin prepares the response
// spectra; this owns the streaming state.

namespace {

struct FftF {
    int n;
    std::vector<float> c, s;
    std::vector<int> rev;
    explicit FftF(int size) : n(size), c(size / 2), s(size / 2), rev(size) {
        for (int i = 0; i < n / 2; i++) {
            c[i] = static_cast<float>(std::cos(2 * M_PI * i / n));
            s[i] = static_cast<float>(std::sin(2 * M_PI * i / n));
        }
        int bits = 0;
        while ((1 << bits) < n) bits++;
        for (int i = 0; i < n; i++) {
            int r = 0;
            for (int b = 0; b < bits; b++) if (i & (1 << b)) r |= 1 << (bits - 1 - b);
            rev[i] = r;
        }
    }
    void transform(float* re, float* im, bool inverse) const {
        for (int i = 0; i < n; i++) {
            int j = rev[i];
            if (i < j) { std::swap(re[i], re[j]); std::swap(im[i], im[j]); }
        }
        const float sign = inverse ? 1.f : -1.f;
        for (int len = 2; len <= n; len <<= 1) {
            const int half = len / 2, step = n / len;
            for (int i = 0; i < n; i += len) {
                int k = 0;
                for (int j = i; j < i + half; j++, k += step) {
                    const float wr = c[k], wi = sign * s[k];
                    const int a = j + half;
                    const float xr = re[a] * wr - im[a] * wi;
                    const float xi = re[a] * wi + im[a] * wr;
                    re[a] = re[j] - xr; im[a] = im[j] - xi;
                    re[j] += xr; im[j] += xi;
                }
            }
        }
    }
};

struct Conv {
    int B, N, bins, P;
    std::vector<float> path[2][2];  // [out][in]: P × (bins re, bins im); empty = silent
    std::vector<float> pending[2][2];  // takes over at the next block (cross-faded)
    bool hasPending = false;
    std::vector<float> fade[2];
    std::vector<float> fdlRe, fdlIm;  // [P][2][bins]
    int slot = 0;
    std::vector<float> window[2], outBlock[2];
    int fill = 0;
    std::vector<float> re, im, accRe[2], accIm[2];
    FftF fft;

    Conv(int block, int partitions) : B(block), N(block * 2), bins(block + 1), P(partitions), fft(block * 2) {
        fdlRe.assign(static_cast<size_t>(P) * 2 * bins, 0.f);
        fdlIm.assign(static_cast<size_t>(P) * 2 * bins, 0.f);
        for (int c = 0; c < 2; c++) {
            window[c].assign(N, 0.f);
            outBlock[c].assign(B, 0.f);
            fade[c].assign(B, 0.f);
            accRe[c].assign(bins, 0.f);
            accIm[c].assign(bins, 0.f);
        }
        re.assign(N, 0.f);
        im.assign(N, 0.f);
    }

    void reset() {
        std::fill(fdlRe.begin(), fdlRe.end(), 0.f);
        std::fill(fdlIm.begin(), fdlIm.end(), 0.f);
        for (int c = 0; c < 2; c++) {
            std::fill(window[c].begin(), window[c].end(), 0.f);
            std::fill(outBlock[c].begin(), outBlock[c].end(), 0.f);
        }
        fill = 0;
    }

    void runBlock() {
        for (int k = 0; k < N; k++) { re[k] = window[0][k]; im[k] = window[1][k]; }
        fft.transform(re.data(), im.data(), false);
        float* inRe = &fdlRe[static_cast<size_t>(slot) * 2 * bins];
        float* inIm = &fdlIm[static_cast<size_t>(slot) * 2 * bins];
        for (int k = 0; k < bins; k++) {
            const int m = (N - k) & (N - 1);
            inRe[k] = (re[k] + re[m]) * 0.5f;
            inIm[k] = (im[k] - im[m]) * 0.5f;
            inRe[bins + k] = (im[k] + im[m]) * 0.5f;
            inIm[bins + k] = (re[m] - re[k]) * 0.5f;
        }
        filter(path, outBlock);
        if (hasPending) {
            // New response: cross-fade old → new over this block (same input history).
            filter(pending, fade);
            for (int j = 0; j < B; j++) {
                const float t = (j + 0.5f) / B;
                for (int c = 0; c < 2; c++) outBlock[c][j] = outBlock[c][j] * (1 - t) + fade[c][j] * t;
            }
            for (int o = 0; o < 2; o++) for (int i = 0; i < 2; i++) path[o][i].swap(pending[o][i]);
            hasPending = false;
        }
        slot = (slot + 1) % P;
        for (int c = 0; c < 2; c++) std::copy(window[c].begin() + B, window[c].end(), window[c].begin());
    }

    void filter(std::vector<float> (&with)[2][2], std::vector<float> (&out)[2]) {
        for (int o = 0; o < 2; o++) {
            std::fill(accRe[o].begin(), accRe[o].end(), 0.f);
            std::fill(accIm[o].begin(), accIm[o].end(), 0.f);
        }
        for (int p = 0; p < P; p++) {
            const int s = (slot - p + P) % P;
            for (int o = 0; o < 2; o++) for (int i = 0; i < 2; i++) {
                if (with[o][i].empty()) continue;
                const float* hr = &with[o][i][static_cast<size_t>(p) * 2 * bins];
                const float* hi = hr + bins;
                const float* xr = &fdlRe[(static_cast<size_t>(s) * 2 + i) * bins];
                const float* xi = &fdlIm[(static_cast<size_t>(s) * 2 + i) * bins];
                float* ar = accRe[o].data();
                float* ai = accIm[o].data();
                for (int k = 0; k < bins; k++) {
                    ar[k] += xr[k] * hr[k] - xi[k] * hi[k];
                    ai[k] += xr[k] * hi[k] + xi[k] * hr[k];
                }
            }
        }
        for (int k = 0; k < N; k++) {
            if (k < bins) {
                re[k] = accRe[0][k] - accIm[1][k];
                im[k] = accIm[0][k] + accRe[1][k];
            } else {
                const int m = N - k;
                re[k] = accRe[0][m] + accIm[1][m];
                im[k] = -accIm[0][m] + accRe[1][m];
            }
        }
        fft.transform(re.data(), im.data(), true);
        const float scale = 1.f / N;
        for (int j = 0; j < B; j++) {
            out[0][j] = re[B + j] * scale;
            out[1][j] = im[B + j] * scale;
        }
    }

    void process(float* x, int frames, int channels) {
        const bool stereo = channels >= 2;
        for (int f = 0; f < frames; f++, x += channels) {
            window[0][B + fill] = x[0];
            window[1][B + fill] = stereo ? x[1] : 0.f;
            x[0] = outBlock[0][fill];
            if (stereo) x[1] = outBlock[1][fill];
            if (++fill == B) {
                runBlock();
                fill = 0;
            }
        }
    }
};

void copyPath(JNIEnv* env, std::vector<float>& dst, jfloatArray src) {
    if (src == nullptr) return;
    const jsize n = env->GetArrayLength(src);
    dst.resize(static_cast<size_t>(n));
    env->GetFloatArrayRegion(src, 0, n, dst.data());
}

}  // namespace

extern "C" JNIEXPORT jlong JNICALL
Java_com_gtongfa_audifac_dsp_NativeDsp_convCreate(JNIEnv* env, jclass, jint block, jint partitions,
                                                  jfloatArray ll, jfloatArray rl, jfloatArray lr, jfloatArray rr) {
    auto* c = new Conv(block, partitions);
    copyPath(env, c->path[0][0], ll);
    copyPath(env, c->path[0][1], rl);
    copyPath(env, c->path[1][0], lr);
    copyPath(env, c->path[1][1], rr);
    return reinterpret_cast<jlong>(c);
}

extern "C" JNIEXPORT void JNICALL
Java_com_gtongfa_audifac_dsp_NativeDsp_convProcess(JNIEnv* env, jclass, jlong handle, jfloatArray samples,
                                                   jint frames, jint offset, jint channels) {
    auto* c = reinterpret_cast<Conv*>(handle);
    auto* x = static_cast<float*>(env->GetPrimitiveArrayCritical(samples, nullptr));
    if (x == nullptr) return;
    c->process(x + offset, frames, channels);
    env->ReleasePrimitiveArrayCritical(samples, x, 0);
}

extern "C" JNIEXPORT void JNICALL
Java_com_gtongfa_audifac_dsp_NativeDsp_convReset(JNIEnv*, jclass, jlong handle) {
    reinterpret_cast<Conv*>(handle)->reset();
}

extern "C" JNIEXPORT void JNICALL
Java_com_gtongfa_audifac_dsp_NativeDsp_convDestroy(JNIEnv*, jclass, jlong handle) {
    delete reinterpret_cast<Conv*>(handle);
}

extern "C" JNIEXPORT void JNICALL
Java_com_gtongfa_audifac_dsp_NativeDsp_convUpdate(JNIEnv* env, jclass, jlong handle,
                                                  jfloatArray ll, jfloatArray rl, jfloatArray lr, jfloatArray rr) {
    auto* c = reinterpret_cast<Conv*>(handle);
    for (int o = 0; o < 2; o++) for (int i = 0; i < 2; i++) c->pending[o][i].clear();
    copyPath(env, c->pending[0][0], ll);
    copyPath(env, c->pending[0][1], rl);
    copyPath(env, c->pending[1][0], lr);
    copyPath(env, c->pending[1][1], rr);
    c->hasPending = true;
}
