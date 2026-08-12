#include <stddef.h>

static size_t _sendv_failed_step = 0;
static size_t _recv_hello_step = 0;
static size_t _recv_10_step = 0;
static size_t _recv_mute_step = 0;
static size_t _recv_yield_step = 0;
static size_t _accept_step = 0;

size_t lori_test_get_sendv_failed_step(void) { return _sendv_failed_step; }
void lori_test_set_sendv_failed_step(size_t v) { _sendv_failed_step = v; }
void lori_test_inc_sendv_failed_step(void) { _sendv_failed_step++; }
size_t lori_test_get_recv_hello_step(void) { return _recv_hello_step; }
void lori_test_set_recv_hello_step(size_t v) { _recv_hello_step = v; }
void lori_test_inc_recv_hello_step(void) { _recv_hello_step++; }
size_t lori_test_get_recv_10_step(void) { return _recv_10_step; }
void lori_test_set_recv_10_step(size_t v) { _recv_10_step = v; }
void lori_test_inc_recv_10_step(void) { _recv_10_step++; }
size_t lori_test_get_recv_mute_step(void) { return _recv_mute_step; }
void lori_test_set_recv_mute_step(size_t v) { _recv_mute_step = v; }
void lori_test_inc_recv_mute_step(void) { _recv_mute_step++; }
size_t lori_test_get_recv_yield_step(void) { return _recv_yield_step; }
void lori_test_set_recv_yield_step(size_t v) { _recv_yield_step = v; }
void lori_test_inc_recv_yield_step(void) { _recv_yield_step++; }
size_t lori_test_get_accept_step(void) { return _accept_step; }
void lori_test_set_accept_step(size_t v) { _accept_step = v; }
void lori_test_inc_accept_step(void) { _accept_step++; }
