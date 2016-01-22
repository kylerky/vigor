#include <assert.h>
#include <klee/klee.h>
#include "lib/containers/double-chain.h"

// TODO: double check that this model is enough for the NAT scenario

int out_of_space = 0;
int new_index = 0;
int allocated = 0;
int range = 0;

int oldest_index = 0;
int oldest_index_freed = 0;

int dchain_allocate_stub(int index_range) {
    new_index = klee_int("new_index");
    oldest_index = klee_int("oldest_index");
    klee_assume(0 <= new_index);
    klee_assume(new_index < index_range);
    klee_assume(0 <= oldest_index);
    klee_assume(oldest_index < index_range);
    range = index_range;
    allocated = 0;
    oldest_index_freed = klee_int("oldest_index_freed");
    out_of_space = klee_int("out_of_space");
    return 1;
}
int dchain_allocate(int index_range)
{return dchain_allocate_stub(index_range);}

int dchain_allocate_new_index_stub(int *index) {
    //TODO: add the out-of-space case
    if (out_of_space) return 0;
    klee_assert(!allocated);
    *index = new_index;
    allocated = 1;
    return 1;
}
int dchain_allocate_new_index(int *index)
{return dchain_allocate_new_index_stub(index);}

int dchain_free_index_stub(int index) {
    klee_assert(index == oldest_index);
    if (oldest_index_freed)
        return 0;
    oldest_index_freed = 1;
    return 1;
}
int dchain_free_index(int index)
{return dchain_free_index_stub(index);}

int dchain_get_oldest_index_stub(int *index) {
    if (oldest_index_freed)
        return 0;
    *index = oldest_index;
    return 1;
}
int dchain_get_oldest_index(int *index)
{return dchain_get_oldest_index_stub(index);}

int dchain_rejuvenate_index_stub(int index) {
    // Check if it is legible for rejuivenation?
    return 1;
}
int dchain_rejuvenate_index(int index)
{return dchain_rejuvenate_index_stub(index);}

void dchain_stub_allocate_some_stub(void) {
    out_of_space = 0;
}
void dchain_stub_allocate_some(void)
{dchain_stub_allocate_some_stub();}