// ABOUTME: C header for the claide-terminal static library.
// ABOUTME: Declares FFI functions callable from Swift via bridging header.

#ifndef CLAIDE_TERMINAL_H
#define CLAIDE_TERMINAL_H

#include <stdint.h>

/// Returns the library version as a packed integer (major * 10000 + minor * 100 + patch).
uint32_t claide_terminal_version(void);

#endif // CLAIDE_TERMINAL_H
