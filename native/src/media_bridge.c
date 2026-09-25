#include "media_bridge.h"

#include <math.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/avutil.h>
#include <libavutil/display.h>
#include <libavutil/imgutils.h>
#include <libavutil/pixdesc.h>
#include <libswscale/swscale.h>

const char *mb_version(void) { return av_version_info(); }

void mb_free(void *ptr) { free(ptr); }

/* ---------- tiny JSON writer ---------- */

typedef struct {
  char *buf;
  size_t len, cap;
  int oom;
} Json;

static void j_reserve(Json *j, size_t extra) {
  if (j->oom || j->len + extra + 1 <= j->cap) return;
  size_t cap = j->cap ? j->cap : 1024;
  while (cap < j->len + extra + 1) cap *= 2;
  char *next = realloc(j->buf, cap);
  if (!next) {
    j->oom = 1;
    return;
  }
  j->buf = next;
  j->cap = cap;
}

static void j_raw(Json *j, const char *s) {
  size_t n = strlen(s);
  j_reserve(j, n);
  if (j->oom) return;
  memcpy(j->buf + j->len, s, n);
  j->len += n;
  j->buf[j->len] = 0;
}

static void j_fmt(Json *j, const char *fmt, ...) {
  char tmp[256];
  va_list ap;
  va_start(ap, fmt);
  vsnprintf(tmp, sizeof tmp, fmt, ap);
  va_end(ap);
  j_raw(j, tmp);
}

static void j_str(Json *j, const char *s) {
  if (!s) {
    j_raw(j, "null");
    return;
  }
  j_raw(j, "\"");
  for (const unsigned char *p = (const unsigned char *)s; *p; p++) {
    char esc[8];
    switch (*p) {
      case '"': j_raw(j, "\\\""); break;
      case '\\': j_raw(j, "\\\\"); break;
      case '\n': j_raw(j, "\\n"); break;
      case '\r': j_raw(j, "\\r"); break;
      case '\t': j_raw(j, "\\t"); break;
      default:
        if (*p < 0x20) {
          snprintf(esc, sizeof esc, "\\u%04x", *p);
          j_raw(j, esc);
        } else {
          char c[2] = {(char)*p, 0};  // UTF-8 bytes pass through
          j_raw(j, c);
        }
    }
  }
  j_raw(j, "\"");
}

static void j_key(Json *j, int *first, const char *key) {
  if (!*first) j_raw(j, ",");
  *first = 0;
  j_str(j, key);
  j_raw(j, ":");
}

static void j_kv_str(Json *j, int *first, const char *key, const char *value) {
  if (!value) return;
  j_key(j, first, key);
  j_str(j, value);
}

static void j_kv_int(Json *j, int *first, const char *key, int64_t value) {
  j_key(j, first, key);
  j_fmt(j, "%lld", (long long)value);
}

static void j_kv_rate(Json *j, int *first, const char *key, AVRational r) {
  char tmp[64];
  snprintf(tmp, sizeof tmp, "%d/%d", r.num, r.den);
  j_kv_str(j, first, key, tmp);
}

static void j_tags(Json *j, int *first, const AVDictionary *dict) {
  if (!dict || av_dict_count(dict) == 0) return;
  j_key(j, first, "tags");
  j_raw(j, "{");
  int f = 1;
  const AVDictionaryEntry *e = NULL;
  while ((e = av_dict_iterate(dict, e))) j_kv_str(j, &f, e->key, e->value);
  j_raw(j, "}");
}

static char *json_error(const char *msg) {
  Json j = {0};
  int first = 1;
  j_raw(&j, "{");
  j_kv_str(&j, &first, "error", msg);
  j_raw(&j, "}");
  return j.oom ? NULL : j.buf;
}

static char *av_error_json(const char *what, int err) {
  char e[AV_ERROR_MAX_STRING_SIZE] = {0};
  char msg[512];
  av_strerror(err, e, sizeof e);
  snprintf(msg, sizeof msg, "%s: %s", what, e);
  return json_error(msg);
}

/* Display rotation in degrees counter-clockwise (ffprobe's "rotation"). */
static int stream_rotation(const AVStream *st, int *has) {
  const AVPacketSideData *sd = av_packet_side_data_get(st->codecpar->coded_side_data,
                                                       st->codecpar->nb_coded_side_data,
                                                       AV_PKT_DATA_DISPLAYMATRIX);
  *has = 0;
  if (!sd || sd->size < 9 * sizeof(int32_t)) return 0;
  double r = av_display_rotation_get((const int32_t *)sd->data);
  if (isnan(r)) return 0;
  *has = 1;
  return (int)lrint(r);
}

char *mb_probe(const char *path) {
  if (!path) return json_error("null path");
  AVFormatContext *fmt = NULL;
  int ret = avformat_open_input(&fmt, path, NULL, NULL);
  if (ret < 0) return av_error_json(path, ret);
  ret = avformat_find_stream_info(fmt, NULL);
  if (ret < 0) {
    avformat_close_input(&fmt);
    return av_error_json("find_stream_info", ret);
  }

  Json j = {0};
  j_raw(&j, "{\"streams\":[");
  for (unsigned i = 0; i < fmt->nb_streams; i++) {
    const AVStream *st = fmt->streams[i];
    const AVCodecParameters *par = st->codecpar;
    const AVCodecDescriptor *desc = avcodec_descriptor_get(par->codec_id);
    int f = 1;
    if (i) j_raw(&j, ",");
    j_raw(&j, "{");
    j_kv_int(&j, &f, "index", st->index);
    j_kv_str(&j, &f, "codec_type", av_get_media_type_string(par->codec_type));
    j_kv_str(&j, &f, "codec_name", avcodec_get_name(par->codec_id));
    if (desc) j_kv_str(&j, &f, "codec_long_name", desc->long_name);
    j_kv_str(&j, &f, "profile", avcodec_profile_name(par->codec_id, par->profile));
    if (par->bit_rate > 0) j_kv_int(&j, &f, "bit_rate", par->bit_rate);
    if (par->bits_per_raw_sample > 0) j_kv_int(&j, &f, "bits_per_raw_sample", par->bits_per_raw_sample);

    if (par->codec_type == AVMEDIA_TYPE_VIDEO) {
      j_kv_int(&j, &f, "width", par->width);
      j_kv_int(&j, &f, "height", par->height);
      j_kv_str(&j, &f, "pix_fmt", av_get_pix_fmt_name((enum AVPixelFormat)par->format));
      if (par->color_trc != AVCOL_TRC_UNSPECIFIED) {
        j_kv_str(&j, &f, "color_transfer", av_color_transfer_name(par->color_trc));
      }
      j_kv_rate(&j, &f, "avg_frame_rate", st->avg_frame_rate);
      j_kv_rate(&j, &f, "r_frame_rate", st->r_frame_rate);
      int has_rot = 0;
      int rot = stream_rotation(st, &has_rot);
      if (has_rot) {
        j_key(&j, &f, "side_data_list");
        j_fmt(&j, "[{\"side_data_type\":\"Display Matrix\",\"rotation\":%d}]", rot);
      }
    } else if (par->codec_type == AVMEDIA_TYPE_AUDIO) {
      j_kv_int(&j, &f, "sample_rate", par->sample_rate);
      j_kv_int(&j, &f, "channels", par->ch_layout.nb_channels);
      char layout[128];
      if (av_channel_layout_describe(&par->ch_layout, layout, sizeof layout) > 0) {
        j_kv_str(&j, &f, "channel_layout", layout);
      }
    }

    j_key(&j, &f, "disposition");
    j_fmt(&j, "{\"default\":%d,\"attached_pic\":%d}", !!(st->disposition & AV_DISPOSITION_DEFAULT),
          !!(st->disposition & AV_DISPOSITION_ATTACHED_PIC));
    j_tags(&j, &f, st->metadata);
    j_raw(&j, "}");
  }

  j_raw(&j, "],\"format\":{");
  int f = 1;
  j_kv_str(&j, &f, "filename", path);
  j_kv_int(&j, &f, "nb_streams", fmt->nb_streams);
  j_kv_str(&j, &f, "format_name", fmt->iformat->name);
  j_kv_str(&j, &f, "format_long_name", fmt->iformat->long_name);
  if (fmt->duration != AV_NOPTS_VALUE) {
    j_key(&j, &f, "duration");
    j_fmt(&j, "\"%.6f\"", fmt->duration / (double)AV_TIME_BASE);
  }
  int64_t size = fmt->pb ? avio_size(fmt->pb) : -1;
  if (size >= 0) j_kv_int(&j, &f, "size", size);
  if (fmt->bit_rate > 0) j_kv_int(&j, &f, "bit_rate", fmt->bit_rate);
  j_tags(&j, &f, fmt->metadata);
  j_raw(&j, "}}");

  avformat_close_input(&fmt);
  if (j.oom) {
    free(j.buf);
    return NULL;
  }
  return j.buf;
}

/* ---------- frame decoding ---------- */

static void set_error(char *out, int32_t len, const char *fmt, ...) {
  if (!out || len <= 0) return;
  va_list ap;
  va_start(ap, fmt);
  vsnprintf(out, (size_t)len, fmt, ap);
  va_end(ap);
}

/* Prefers a real video stream; falls back to embedded cover art. */
static int pick_stream(AVFormatContext *fmt, int *is_cover) {
  int cover = -1;
  for (unsigned i = 0; i < fmt->nb_streams; i++) {
    const AVStream *st = fmt->streams[i];
    if (st->codecpar->codec_type != AVMEDIA_TYPE_VIDEO) continue;
    if (st->disposition & AV_DISPOSITION_ATTACHED_PIC) {
      if (cover < 0) cover = (int)i;
    } else {
      *is_cover = 0;
      return (int)i;
    }
  }
  *is_cover = cover >= 0;
  return cover;
}

/* Rotates an RGBA image clockwise by 90 * quarter turns into a new buffer. */
static uint8_t *rotate_rgba(const uint8_t *src, int w, int h, int quarters, int *ow, int *oh) {
  quarters = ((quarters % 4) + 4) % 4;
  *ow = (quarters % 2) ? h : w;
  *oh = (quarters % 2) ? w : h;
  uint8_t *dst = malloc((size_t)w * h * 4);
  if (!dst) return NULL;
  const uint32_t *s = (const uint32_t *)src;
  uint32_t *d = (uint32_t *)dst;
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      int nx, ny;
      switch (quarters) {
        case 1: nx = h - 1 - y; ny = x; break;          // 90° cw
        case 2: nx = w - 1 - x; ny = h - 1 - y; break;  // 180°
        case 3: nx = y; ny = w - 1 - x; break;          // 270° cw
        default: nx = x; ny = y;
      }
      d[ny * *ow + nx] = s[y * w + x];
    }
  }
  return dst;
}

static uint8_t *frame_to_rgba(const AVFrame *frame, int quarters, int32_t max_w, int32_t max_h,
                              int32_t *out_w, int32_t *out_h, char *err, int32_t err_len) {
  // Fit in the *displayed* orientation, then scale in the stored orientation.
  int disp_w = (quarters % 2) ? frame->height : frame->width;
  int disp_h = (quarters % 2) ? frame->width : frame->height;
  double scale = 1.0;
  if (max_w > 0 && disp_w > max_w) scale = fmin(scale, (double)max_w / disp_w);
  if (max_h > 0 && disp_h > max_h) scale = fmin(scale, (double)max_h / disp_h);
  int dw = (int)lrint(frame->width * scale), dh = (int)lrint(frame->height * scale);
  if (dw < 1) dw = 1;
  if (dh < 1) dh = 1;

  struct SwsContext *sws = sws_getContext(frame->width, frame->height, (enum AVPixelFormat)frame->format, dw,
                                          dh, AV_PIX_FMT_RGBA, SWS_BILINEAR, NULL, NULL, NULL);
  if (!sws) {
    set_error(err, err_len, "unsupported pixel format %s", av_get_pix_fmt_name(frame->format));
    return NULL;
  }
  uint8_t *rgba = malloc((size_t)dw * dh * 4);
  if (!rgba) {
    sws_freeContext(sws);
    set_error(err, err_len, "out of memory");
    return NULL;
  }
  uint8_t *dst[4] = {rgba, NULL, NULL, NULL};
  int dst_stride[4] = {dw * 4, 0, 0, 0};
  sws_scale(sws, (const uint8_t *const *)frame->data, frame->linesize, 0, frame->height, dst, dst_stride);
  sws_freeContext(sws);

  if (quarters % 4 == 0) {
    *out_w = dw;
    *out_h = dh;
    return rgba;
  }
  int rw, rh;
  uint8_t *rotated = rotate_rgba(rgba, dw, dh, quarters, &rw, &rh);
  free(rgba);
  if (!rotated) {
    set_error(err, err_len, "out of memory");
    return NULL;
  }
  *out_w = rw;
  *out_h = rh;
  return rotated;
}

uint8_t *mb_decode_frame(const char *path, int64_t time_us, int32_t max_width, int32_t max_height,
                         int32_t *out_width, int32_t *out_height, char *error_out, int32_t error_len) {
  AVFormatContext *fmt = NULL;
  AVCodecContext *dec = NULL;
  AVPacket *pkt = NULL;
  AVFrame *frame = NULL, *best = NULL;
  uint8_t *result = NULL;
  int ret;

  if (!path || !out_width || !out_height) return NULL;
  if ((ret = avformat_open_input(&fmt, path, NULL, NULL)) < 0 ||
      (ret = avformat_find_stream_info(fmt, NULL)) < 0) {
    char e[AV_ERROR_MAX_STRING_SIZE];
    av_strerror(ret, e, sizeof e);
    set_error(error_out, error_len, "%s", e);
    goto done;
  }

  int is_cover = 0;
  int idx = pick_stream(fmt, &is_cover);
  if (idx < 0) {
    set_error(error_out, error_len, "no picture stream");
    goto done;
  }
  AVStream *st = fmt->streams[idx];
  const AVCodec *codec = avcodec_find_decoder(st->codecpar->codec_id);
  if (!codec) {
    set_error(error_out, error_len, "no decoder for %s", avcodec_get_name(st->codecpar->codec_id));
    goto done;
  }
  dec = avcodec_alloc_context3(codec);
  avcodec_parameters_to_context(dec, st->codecpar);
  dec->thread_count = 0;
  dec->thread_type = FF_THREAD_SLICE;  // frame threading only adds latency here
  if ((ret = avcodec_open2(dec, codec, NULL)) < 0) {
    set_error(error_out, error_len, "cannot open decoder");
    goto done;
  }
  for (unsigned i = 0; i < fmt->nb_streams; i++) {
    if ((int)i != idx) fmt->streams[i]->discard = AVDISCARD_ALL;
  }

  pkt = av_packet_alloc();
  frame = av_frame_alloc();
  best = av_frame_alloc();
  int have = 0;

  if (is_cover) {
    if (avcodec_send_packet(dec, &st->attached_pic) >= 0 && avcodec_receive_frame(dec, frame) >= 0) {
      av_frame_move_ref(best, frame);
      have = 1;
    }
  } else {
    int64_t target = AV_NOPTS_VALUE;
    if (time_us > 0) {
      target = av_rescale_q(time_us, AV_TIME_BASE_Q, st->time_base);
      if (st->start_time != AV_NOPTS_VALUE) target += st->start_time;
      if (av_seek_frame(fmt, idx, target, AVSEEK_FLAG_BACKWARD) < 0) target = AV_NOPTS_VALUE;
    }
    // Decode forward until we reach the requested timestamp (accurate seek),
    // bounded so a pathological GOP can't stall the UI.
    int decoded = 0, eof = 0;
    while (!eof && decoded < 1200) {
      ret = av_read_frame(fmt, pkt);
      if (ret < 0) {
        eof = 1;
        avcodec_send_packet(dec, NULL);
      } else if (pkt->stream_index != idx) {
        av_packet_unref(pkt);
        continue;
      } else {
        avcodec_send_packet(dec, pkt);
        av_packet_unref(pkt);
      }
      int done_decoding = 0;
      while (avcodec_receive_frame(dec, frame) >= 0) {
        decoded++;
        av_frame_unref(best);
        av_frame_move_ref(best, frame);
        have = 1;
        int64_t pts = best->best_effort_timestamp;
        if (target == AV_NOPTS_VALUE || pts == AV_NOPTS_VALUE || pts >= target) {
          done_decoding = 1;
          break;
        }
      }
      if (done_decoding) break;
    }
  }

  if (!have) {
    set_error(error_out, error_len, "no frame decoded");
    goto done;
  }
  int has_rot = 0;
  int rot_ccw = is_cover ? 0 : stream_rotation(st, &has_rot);
  int quarters = (int)lrint(((-rot_ccw % 360) + 360) % 360 / 90.0);
  result = frame_to_rgba(best, quarters, max_width, max_height, out_width, out_height, error_out, error_len);

done:
  av_frame_free(&frame);
  av_frame_free(&best);
  av_packet_free(&pkt);
  avcodec_free_context(&dec);
  avformat_close_input(&fmt);
  return result;
}
