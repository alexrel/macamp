#ifndef MACAMP_GOOM_H
#define MACAMP_GOOM_H

#include <stdbool.h>
#include <stdint.h>

#define MACAMP_GOOM_API __attribute__((visibility("default")))

/* The original engine is a singleton. Make all calls on the same render thread. */
MACAMP_GOOM_API bool macamp_goom_start(uint32_t width, uint32_t height, bool cinemascope);
MACAMP_GOOM_API bool macamp_goom_resize(uint32_t width, uint32_t height, bool cinemascope);
MACAMP_GOOM_API void macamp_goom_stop(void);

/* BGRA pixels owned by the engine until the next engine call. Ignore alpha. */
MACAMP_GOOM_API const uint32_t *macamp_goom_render(
    const float *stereoInterleaved, uint32_t frameCount, int32_t effect,
    float fps, const char *title, const char *message);
MACAMP_GOOM_API const char *macamp_goom_credits(void);

#endif
