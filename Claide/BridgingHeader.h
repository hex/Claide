// ABOUTME: Objective-C bridging header for Swift-to-C interop.
// ABOUTME: Imports system framework headers and private API declarations.

#import <CoreGraphics/CoreGraphics.h>
#import <libproc.h>

// Private CoreGraphics API for controlling font stroke weight.
// Style 16 produces thinner strokes, preventing text from looking too bold on dark backgrounds.
extern void CGContextSetFontSmoothingStyle(CGContextRef context, int style);
