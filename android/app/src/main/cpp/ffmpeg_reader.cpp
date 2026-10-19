// Demuxes and decodes WMA / APE / WavPack / TTA with a minimal FFmpeg build
// (tools/ffmpeg/build.sh) and hands interleaved PCM to Kotlin
// (com.gtongfa.audifac.extract.FfmpegReader), which feeds it to ExoPlayer as
// raw audio. The file is read through its descriptor with pread().

#include <jni.h>
#include <android/log.h>
#include <sys/stat.h>
#include <unistd.h>
#include <cerrno>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>

extern "C" {
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/channel_layout.h>
#include <libavutil/mathematics.h>
}

#define LOG_TAG "AudifacFfmpeg"
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, LOG_TAG, __VA_ARGS__)

namespace {

// Output sample formats, as told to Kotlin.
constexpr int OUT_S16 = 16;
constexpr int OUT_FLOAT = 32;

struct Reader {
    int fd = -1;
    int64_t pos = 0;
    int64_t size = 0;
    AVIOContext *io = nullptr;
    AVFormatContext *fmt = nullptr;
    AVCodecContext *codec = nullptr;
    AVPacket *packet = nullptr;
    AVFrame *frame = nullptr;
    int stream = -1;
    int outFormat = OUT_FLOAT;
    int channels = 0;
    int sampleRate = 0;
    bool demuxEnded = false;
    bool flushed = false;
    int64_t nextPtsUs = 0;   // used when frames carry no timestamp
    int64_t framePtsUs = 0;  // timestamp of the last decoded frame
    std::vector<uint8_t> pcm;
};

int readPacket(void *opaque, uint8_t *buf, int size) {
    auto *r = static_cast<Reader *>(opaque);
    ssize_t n;
    do {
        n = pread(r->fd, buf, size, r->pos);
    } while (n < 0 && errno == EINTR);
    if (n < 0) return AVERROR(errno);
    if (n == 0) return AVERROR_EOF;
    r->pos += n;
    return static_cast<int>(n);
}

int64_t seekPacket(void *opaque, int64_t offset, int whence) {
    auto *r = static_cast<Reader *>(opaque);
    switch (whence & ~AVSEEK_FORCE) {
        case AVSEEK_SIZE: return r->size;
        case SEEK_SET: r->pos = offset; break;
        case SEEK_CUR: r->pos += offset; break;
        case SEEK_END: r->pos = r->size + offset; break;
        default: return -1;
    }
    return r->pos;
}

void destroy(Reader *r) {
    if (!r) return;
    av_frame_free(&r->frame);
    av_packet_free(&r->packet);
    avcodec_free_context(&r->codec);
    if (r->fmt) avformat_close_input(&r->fmt);
    if (r->io) {
        av_freep(&r->io->buffer);
        avio_context_free(&r->io);
    }
    if (r->fd >= 0) close(r->fd);
    delete r;
}

bool isLossy(AVCodecID id) {
    return id == AV_CODEC_ID_WMAV1 || id == AV_CODEC_ID_WMAV2 || id == AV_CODEC_ID_WMAPRO;
}

int64_t toUs(int64_t ts, AVRational tb) { return av_rescale_q(ts, tb, AVRational{1, 1000000}); }

/// One sample of any FFmpeg format, as float (-1..1).
inline float sampleAt(const AVFrame *f, AVSampleFormat fmt, int ch, int i, int channels) {
    const bool planar = av_sample_fmt_is_planar(fmt);
    const int idx = planar ? i : i * channels + ch;
    const uint8_t *data = planar ? f->extended_data[ch] : f->extended_data[0];
    switch (av_get_packed_sample_fmt(fmt)) {
        case AV_SAMPLE_FMT_U8: return (data[idx] - 128) / 128.0f;
        case AV_SAMPLE_FMT_S16: return reinterpret_cast<const int16_t *>(data)[idx] / 32768.0f;
        case AV_SAMPLE_FMT_S32: return static_cast<float>(reinterpret_cast<const int32_t *>(data)[idx] / 2147483648.0);
        case AV_SAMPLE_FMT_S64: return static_cast<float>(reinterpret_cast<const int64_t *>(data)[idx] / 9223372036854775808.0);
        case AV_SAMPLE_FMT_FLT: return reinterpret_cast<const float *>(data)[idx];
        case AV_SAMPLE_FMT_DBL: return static_cast<float>(reinterpret_cast<const double *>(data)[idx]);
        default: return 0.0f;
    }
}

/// Converts the decoded frame to interleaved S16 or float in r->pcm.
void convert(Reader *r) {
    const AVFrame *f = r->frame;
    const auto fmt = static_cast<AVSampleFormat>(f->format);
    const int n = f->nb_samples, ch = r->channels;
    if (r->outFormat == OUT_S16) {
        r->pcm.resize(static_cast<size_t>(n) * ch * 2);
        auto *out = reinterpret_cast<int16_t *>(r->pcm.data());
        const bool s16 = av_get_packed_sample_fmt(fmt) == AV_SAMPLE_FMT_S16;
        const bool planar = av_sample_fmt_is_planar(fmt);
        for (int i = 0; i < n; i++) {
            for (int c = 0; c < ch; c++) {
                if (s16) {
                    // Exact copy (lossless 16-bit sources).
                    const auto *d = reinterpret_cast<const int16_t *>(planar ? f->extended_data[c] : f->extended_data[0]);
                    out[i * ch + c] = d[planar ? i : i * ch + c];
                } else {
                    float v = sampleAt(f, fmt, c, i, ch) * 32768.0f;
                    v = std::fmax(-32768.0f, std::fmin(32767.0f, std::nearbyint(v)));
                    out[i * ch + c] = static_cast<int16_t>(v);
                }
            }
        }
    } else {
        r->pcm.resize(static_cast<size_t>(n) * ch * 4);
        auto *out = reinterpret_cast<float *>(r->pcm.data());
        for (int i = 0; i < n; i++)
            for (int c = 0; c < ch; c++) out[i * ch + c] = sampleAt(f, fmt, c, i, ch);
    }
}

/// Decodes the next frame into r->pcm. Returns its byte size, -1 at the end,
/// -2 on an error that ends the stream.
int decodeNext(Reader *r) {
    while (true) {
        int ret = avcodec_receive_frame(r->codec, r->frame);
        if (ret == 0) {
            if (r->frame->nb_samples <= 0) continue;
            const AVStream *s = r->fmt->streams[r->stream];
            int64_t ts = r->frame->best_effort_timestamp;
            if (ts != AV_NOPTS_VALUE) {
                int64_t start = s->start_time != AV_NOPTS_VALUE ? s->start_time : 0;
                r->framePtsUs = toUs(ts - start, s->time_base);
            } else {
                r->framePtsUs = r->nextPtsUs;
            }
            r->nextPtsUs = r->framePtsUs + av_rescale(r->frame->nb_samples, 1000000, r->sampleRate);
            convert(r);
            return static_cast<int>(r->pcm.size());
        }
        if (ret == AVERROR_EOF) return -1;
        if (ret != AVERROR(EAGAIN)) {
            LOGW("decode error %d", ret);
            return -2;
        }
        // The decoder wants more input.
        if (r->demuxEnded) {
            if (r->flushed) return -1;
            avcodec_send_packet(r->codec, nullptr);
            r->flushed = true;
            continue;
        }
        ret = av_read_frame(r->fmt, r->packet);
        if (ret < 0) {
            r->demuxEnded = true;
            continue;
        }
        if (r->packet->stream_index == r->stream) {
            int sent = avcodec_send_packet(r->codec, r->packet);
            // A damaged packet: skip it rather than ending the song.
            if (sent < 0 && sent != AVERROR(EAGAIN)) LOGW("bad packet %d", sent);
        }
        av_packet_unref(r->packet);
    }
}

Reader *get(jlong handle) { return reinterpret_cast<Reader *>(handle); }

}  // namespace

extern "C" {

JNIEXPORT jlong JNICALL
Java_com_gtongfa_audifac_extract_FfmpegReader_nativeOpen(JNIEnv *, jclass, jint fd) {
    av_log_set_level(AV_LOG_ERROR);
    auto *r = new Reader();
    r->fd = dup(fd);
    struct stat st {};
    if (r->fd < 0 || fstat(r->fd, &st) != 0) {
        destroy(r);
        return 0;
    }
    r->size = st.st_size;
    constexpr int kBuffer = 64 * 1024;
    auto *buffer = static_cast<uint8_t *>(av_malloc(kBuffer));
    r->io = avio_alloc_context(buffer, kBuffer, 0, r, readPacket, nullptr, seekPacket);
    r->fmt = avformat_alloc_context();
    if (!r->io || !r->fmt) {
        destroy(r);
        return 0;
    }
    r->fmt->pb = r->io;
    r->fmt->flags |= AVFMT_FLAG_CUSTOM_IO;
    if (avformat_open_input(&r->fmt, nullptr, nullptr, nullptr) < 0) {
        r->fmt = nullptr;  // freed by avformat_open_input on failure
        destroy(r);
        return 0;
    }
    if (avformat_find_stream_info(r->fmt, nullptr) < 0) LOGW("no stream info");
    const AVCodec *dec = nullptr;
    r->stream = av_find_best_stream(r->fmt, AVMEDIA_TYPE_AUDIO, -1, -1, &dec, 0);
    if (r->stream < 0 || !dec) {
        destroy(r);
        return 0;
    }
    // Only the audio stream is read (cover art / other streams are skipped).
    for (unsigned i = 0; i < r->fmt->nb_streams; i++)
        if (static_cast<int>(i) != r->stream) r->fmt->streams[i]->discard = AVDISCARD_ALL;
    const AVCodecParameters *par = r->fmt->streams[r->stream]->codecpar;
    r->codec = avcodec_alloc_context3(dec);
    if (!r->codec || avcodec_parameters_to_context(r->codec, par) < 0 || avcodec_open2(r->codec, dec, nullptr) < 0) {
        destroy(r);
        return 0;
    }
    r->channels = r->codec->ch_layout.nb_channels;
    r->sampleRate = r->codec->sample_rate;
    if (r->channels <= 0 || r->sampleRate <= 0) {
        destroy(r);
        return 0;
    }
    int bits = par->bits_per_raw_sample > 0 ? par->bits_per_raw_sample : par->bits_per_coded_sample;
    // Lossy WMA decodes to float; lossless keeps 16-bit sources exact as S16
    // and carries deeper ones in float (exact up to 24 bits).
    r->outFormat = (!isLossy(par->codec_id) && bits > 0 && bits <= 16) ? OUT_S16 : OUT_FLOAT;
    r->packet = av_packet_alloc();
    r->frame = av_frame_alloc();
    if (!r->packet || !r->frame) {
        destroy(r);
        return 0;
    }
    return reinterpret_cast<jlong>(r);
}

/// [sampleRate, channels, outBits (16 / 32 = float), durationUs, sourceBits, bitrate]
JNIEXPORT jlongArray JNICALL
Java_com_gtongfa_audifac_extract_FfmpegReader_nativeInfo(JNIEnv *env, jclass, jlong handle) {
    Reader *r = get(handle);
    const AVStream *s = r->fmt->streams[r->stream];
    int64_t durationUs = s->duration != AV_NOPTS_VALUE ? toUs(s->duration, s->time_base)
                         : r->fmt->duration != AV_NOPTS_VALUE ? r->fmt->duration : -1;
    const AVCodecParameters *par = s->codecpar;
    int bits = par->bits_per_raw_sample > 0 ? par->bits_per_raw_sample : par->bits_per_coded_sample;
    if (isLossy(par->codec_id)) bits = 0;
    int64_t bitrate = par->bit_rate > 0 ? par->bit_rate : r->fmt->bit_rate;
    jlong values[6] = {r->sampleRate, r->channels, r->outFormat, durationUs, bits, bitrate};
    jlongArray out = env->NewLongArray(6);
    env->SetLongArrayRegion(out, 0, 6, values);
    return out;
}

JNIEXPORT jstring JNICALL
Java_com_gtongfa_audifac_extract_FfmpegReader_nativeCodec(JNIEnv *env, jclass, jlong handle) {
    return env->NewStringUTF(avcodec_get_name(get(handle)->fmt->streams[get(handle)->stream]->codecpar->codec_id));
}

/// Tags as [key0, value0, key1, value1, …] (container and stream tags).
JNIEXPORT jobjectArray JNICALL
Java_com_gtongfa_audifac_extract_FfmpegReader_nativeTags(JNIEnv *env, jclass, jlong handle) {
    Reader *r = get(handle);
    std::vector<std::string> kv;
    for (AVDictionary *dict : {r->fmt->metadata, r->fmt->streams[r->stream]->metadata}) {
        const AVDictionaryEntry *e = nullptr;
        while ((e = av_dict_iterate(dict, e))) {
            kv.emplace_back(e->key);
            kv.emplace_back(e->value);
        }
    }
    jobjectArray out = env->NewObjectArray(static_cast<jsize>(kv.size()), env->FindClass("java/lang/String"), nullptr);
    for (size_t i = 0; i < kv.size(); i++) {
        jstring s = env->NewStringUTF(kv[i].c_str());
        env->SetObjectArrayElement(out, static_cast<jsize>(i), s);
        env->DeleteLocalRef(s);
    }
    return out;
}

/// Decodes the next frame; returns its PCM size in bytes, -1 at the end, -2 on error.
JNIEXPORT jint JNICALL
Java_com_gtongfa_audifac_extract_FfmpegReader_nativeDecode(JNIEnv *, jclass, jlong handle) {
    return decodeNext(get(handle));
}

/// Copies the last decoded frame's PCM into [dst] (at least its size).
JNIEXPORT void JNICALL
Java_com_gtongfa_audifac_extract_FfmpegReader_nativeCopy(JNIEnv *env, jclass, jlong handle, jbyteArray dst) {
    Reader *r = get(handle);
    env->SetByteArrayRegion(dst, 0, static_cast<jsize>(r->pcm.size()), reinterpret_cast<const jbyte *>(r->pcm.data()));
}

JNIEXPORT jlong JNICALL
Java_com_gtongfa_audifac_extract_FfmpegReader_nativeFrameTimeUs(JNIEnv *, jclass, jlong handle) {
    return get(handle)->framePtsUs;
}

/// How far into the file the demuxer has read, in bytes.
JNIEXPORT jlong JNICALL
Java_com_gtongfa_audifac_extract_FfmpegReader_nativeBytePosition(JNIEnv *, jclass, jlong handle) {
    return get(handle)->pos;
}

JNIEXPORT jboolean JNICALL
Java_com_gtongfa_audifac_extract_FfmpegReader_nativeSeek(JNIEnv *, jclass, jlong handle, jlong timeUs) {
    Reader *r = get(handle);
    const AVStream *s = r->fmt->streams[r->stream];
    int64_t start = s->start_time != AV_NOPTS_VALUE ? s->start_time : 0;
    int64_t ts = av_rescale_q(timeUs, AVRational{1, 1000000}, s->time_base) + start;
    int ret = av_seek_frame(r->fmt, r->stream, ts, AVSEEK_FLAG_BACKWARD);
    if (ret < 0) ret = av_seek_frame(r->fmt, r->stream, ts, AVSEEK_FLAG_BACKWARD | AVSEEK_FLAG_ANY);
    avcodec_flush_buffers(r->codec);
    r->demuxEnded = false;
    r->flushed = false;
    r->nextPtsUs = timeUs;
    return ret >= 0;
}

JNIEXPORT void JNICALL
Java_com_gtongfa_audifac_extract_FfmpegReader_nativeClose(JNIEnv *, jclass, jlong handle) {
    destroy(get(handle));
}

}  // extern "C"
