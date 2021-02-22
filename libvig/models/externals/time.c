#include <time.h>

#include "../hardware.h"

int nanosleep(const struct timespec *req, struct timespec *rem) {
  // https://man7.org/linux/man-pages/man2/nanosleep.2.html
  // On successfully sleeping for the requested interval, nanosleep()
  // returns 0.
  time_t sec = req->tv_sec;
  long nsec = req->tv_nsec;

  uint64_t delta = sec * 1E9 + nsec;
  for (volatile uint64_t i = 0; i < delta; ++i) {
    // do nothing but loop
  }
  TIME += delta;
  return 0;
}
