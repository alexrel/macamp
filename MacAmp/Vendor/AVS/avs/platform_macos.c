/* MacAmp: macOS uses the POSIX (Linux) platform layer with two differences. */
#include <time.h>
#define CLOCK_BOOTTIME CLOCK_MONOTONIC     /* no CLOCK_BOOTTIME on macOS */
#define pthread_setschedprio(thread, prio) (-1) /* not on macOS: priority stays */
#include "platform_linux.c"
