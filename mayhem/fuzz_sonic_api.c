/* Broader Sonic API harness: every sample format, every setter, parameter changes between chunks. */
#include "sonic.h"
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
  sonicStream stream;
  short shortOut[2048];
  float floatOut[2048];
  unsigned char byteOut[2048];
  size_t pos = 12;
  int mode, rounds;

  if (size < 12) return -1;
  stream = sonicCreateStream(2000 + data[0] * 200 + data[1], 1 + (data[2] & 1));
  if (!stream) return -1;
  mode = data[3] % 3;
  rounds = 1 + (data[4] & 3);
  sonicSetSpeed(stream, 0.05f + data[5] / 16.0f);
  sonicSetPitch(stream, 0.1f + data[6] / 32.0f);
  sonicSetRate(stream, 0.1f + data[7] / 32.0f);
  sonicSetVolume(stream, data[8] / 32.0f);
  sonicSetQuality(stream, data[9] & 1);
  sonicSetChordPitch(stream, data[10] & 1);

  while (rounds-- > 0 && pos < size) {
    size_t chunk = size - pos;
    int channels = sonicGetNumChannels(stream);
    if (chunk > 4096) chunk = 4096;
    if (mode == 0) {
      int n = (int)(chunk / (sizeof(short) * channels));
      short *buf = (short *)malloc(n > 0 ? n * sizeof(short) * channels : 1);
      if (!buf) break;
      memcpy(buf, data + pos, n * sizeof(short) * channels);
      sonicWriteShortToStream(stream, buf, n);
      free(buf);
      pos += (size_t)n * sizeof(short) * channels;
      if (n == 0) break;
    } else if (mode == 1) {
      int n = (int)(chunk / (sizeof(float) * channels));
      float *buf = (float *)malloc(n > 0 ? n * sizeof(float) * channels : 1);
      int i;
      if (!buf) break;
      for (i = 0; i < n * channels; i++) buf[i] = ((int)data[pos + i * 4] - 128) / 128.0f;
      sonicWriteFloatToStream(stream, buf, n);
      free(buf);
      pos += (size_t)n * sizeof(float) * channels;
      if (n == 0) break;
    } else {
      int n = (int)(chunk / channels);
      sonicWriteUnsignedCharToStream(stream, data + pos, n);
      pos += (size_t)n * channels;
      if (n == 0) break;
    }
    if (pos < size) {
      sonicSetSpeed(stream, 0.05f + data[pos] / 16.0f);
      sonicSetPitch(stream, 0.1f + data[(pos + 1) % size] / 32.0f);
    }
    while (sonicReadShortFromStream(stream, shortOut, 2048 / channels) > 0) {}
    while (sonicReadFloatFromStream(stream, floatOut, 2048 / channels) > 0) {}
    while (sonicReadUnsignedCharFromStream(stream, byteOut, 2048 / channels) > 0) {}
  }
  sonicFlushStream(stream);
  while (sonicReadShortFromStream(stream, shortOut, 2048 / sonicGetNumChannels(stream)) > 0) {}
  sonicDestroyStream(stream);
  return 0;
}
