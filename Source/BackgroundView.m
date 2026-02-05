// (c) 2025-2026 Ricci Adams
// MIT License (or) 1-clause BSD License

#import "BackgroundView.h"


@implementation BackgroundView

- (void) drawRect:(NSRect)dirtyRect
{
    CGContextRef context = [[NSGraphicsContext currentContext] CGContext];

    CGContextSaveGState(context);

    if ([[self window] isMainWindow ]) {
        [[NSColor colorNamed:@"ActiveWindowColor"] set];
    } else {
        [[NSColor colorNamed:@"InactiveWindowColor"] set];
    }

    NSRectFill(dirtyRect);

    CGContextRestoreGState(context);
}

@end
