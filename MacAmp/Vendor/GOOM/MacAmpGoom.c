/* MacAmp's C interface to the LGPL GOOM engine. */
#include "MacAmpGoom.h"
#include "core/goom_core.h"
#include <math.h>
#include <stddef.h>

enum { waveformFrames = 512 };

static bool running;
const char *readme(void);

static bool validSize(uint32_t width, uint32_t height)
{
    return width >= 240 && width <= 800 && height >= 160 && height <= 600;
}

bool macamp_goom_start(uint32_t width, uint32_t height, bool cinemascope)
{
    if (running || !validSize(width, height))
        return false;

    goom_init(width, height, cinemascope);
    running = true;
    return true;
}

bool macamp_goom_resize(uint32_t width, uint32_t height, bool cinemascope)
{
    if (!running || !validSize(width, height))
        return false;

    goom_set_resolution(width, height, cinemascope);
    return true;
}

void macamp_goom_stop(void)
{
    if (running)
        goom_close();
    running = false;
}

static int16_t waveformSample(float sample)
{
    if (!isfinite(sample))
        return 0;
    if (sample >= 1)
        return 32512;
    if (sample <= -1)
        return -32768;
    return (int16_t)((int)(sample * 128) * 256);
}

const uint32_t *macamp_goom_render(const float *samples, uint32_t frameCount, int32_t effect,
                                   float fps, const char *title, const char *message)
{
    if (!running || (frameCount && !samples))
        return 0;

    int16_t waveform[2][waveformFrames] = {0};
    const uint32_t count = frameCount < waveformFrames ? frameCount : waveformFrames;
    for (uint32_t i = 0; i < count; ++i) {
        const uint32_t source = frameCount - count + i;
        const uint32_t target = waveformFrames - count + i;
        waveform[0][target] = waveformSample(samples[(size_t)source * 2]);
        waveform[1][target] = waveformSample(samples[(size_t)source * 2 + 1]);
    }
    return goom_update(waveform, effect >= -1 && effect <= 8 ? effect : 0,
                       isfinite(fps) ? fps : -1, title, message);
}

const char *macamp_goom_credits(void)
{
    return readme();
}
