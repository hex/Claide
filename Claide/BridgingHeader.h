// ABOUTME: Objective-C bridging header for Swift-to-C interop.
// ABOUTME: Imports C headers from the Rust claide-terminal static library.

#import "../rust/claide-terminal/include/claide_terminal.h"

#import <CoreGraphics/CoreGraphics.h>

// Private CoreGraphics API for controlling font stroke weight.
// Style 16 produces thinner strokes, preventing text from looking too bold on dark backgrounds.
extern void CGContextSetFontSmoothingStyle(CGContextRef context, int style);
