#ifndef NF_TIME_H_INCLUDED
#define NF_TIME_H_INCLUDED
#include <stdint.h>

// TODO use time_t from time.h - but this is used by VeriFast
// so even #ifdef-ing the time.h inclusion out doesn't work

// For verification this is fine but for running on hardware
// the compiler complains so we actually need to include time.h

typedef int64_t time_t;
// #include <time.h>



//@ predicate last_time(time_t t);

/**
   A wrapper around the system time function. Returns the number of
   seconds since the Epoch (1970-01-01 00:00:00 +0000 (UTC)).
   @returns the number of seconds since Epoch.
*/
time_t current_time(void);
//@ requires last_time(?x);
//@ ensures result >= 0 &*& x <= result &*& last_time(result);

#endif//NF_TIME_H_INCLUDED
