// (c) 2025-2026 Ricci Adams
// MIT License (or) 1-clause BSD License

#import "PlayButton.h"

@import QuartzCore;


@implementation PlayButtonCell

- (void) drawBezelWithFrame:(NSRect)frame inView:(NSView *)controlView
{
    CGContextRef context = [[NSGraphicsContext currentContext] CGContext];

    CGContextSaveGState(context);
    
    CGFloat width = MIN(frame.size.width, frame.size.height);
    CGRect rect = CGRectMake(0, 0, width, width);
    
    NSBezierPath *path = [NSBezierPath bezierPathWithOvalInRect:rect];

    NSColor *topColor    = [NSColor colorNamed:@"ButtonTopColor"];
    NSColor *bottomColor = [NSColor colorNamed:@"ButtonBottomColor"];

    NSShadow *shadow1 = [[NSShadow alloc] init];

    [shadow1 setShadowColor:[NSColor colorWithWhite:0 alpha:0.25]];
    [shadow1 setShadowOffset:NSMakeSize(0, 0)];
    [shadow1 setShadowBlurRadius:1];
    [shadow1 set];

    [topColor set];
    
    [path fill];

    NSShadow *shadow2 = [[NSShadow alloc] init];

    [shadow2 setShadowColor:[NSColor colorWithWhite:0 alpha:0.15]];
    [shadow2 setShadowOffset:NSMakeSize(0, -1)];
    [shadow2 setShadowBlurRadius:1.5];
    [shadow2 set];

    CGContextBeginTransparencyLayer(context, NULL);

    NSGradient *gradient = [[NSGradient alloc] initWithColors:@[ topColor, bottomColor ]];
    [gradient drawInBezierPath:path angle:90];

    if ([self isHighlighted]) {
        [[NSColor colorNamed:@"TrackingTint"] set];
        [path fill];
    }
    
    // Draw 1-pixel highlight
    {
        NSBezierPath *outerPath = [NSBezierPath bezierPathWithOvalInRect:rect];
        NSBezierPath *innerPath = [NSBezierPath bezierPathWithOvalInRect:CGRectInset(rect, 0.5, 0.5)];

        [outerPath appendBezierPath:[innerPath bezierPathByReversingPath]];
        
        NSGradient *gradient = [[NSGradient alloc] initWithColors:@[
            [NSColor colorWithWhite:1 alpha:0.25],
            [NSColor colorWithWhite:1 alpha:0.00]
        ]];

        [gradient drawInBezierPath:outerPath angle:90];
    };
    
    CGContextEndTransparencyLayer(context);

    CGContextRestoreGState(context);
}


- (void) drawImage:(NSImage *)image withFrame:(NSRect)frame inView:(NSView *)controlView
{
    if (!image) return;

    CGContextRef context = [[NSGraphicsContext currentContext] CGContext];

    CGContextSaveGState(context);

    CGRect imageRect = [controlView bounds];

    CGContextTranslateCTM(context, 0, imageRect.size.height);
    CGContextScaleCTM(context, 1, -1);

    CGSize imageSize = [image size];
    imageRect.origin.x += (imageRect.size.width - imageSize.width) / 2;
    imageRect.origin.y += (imageRect.size.height - imageSize.height) / 2;
    imageRect.size = imageSize;

    NSRect maskRect = imageRect;


    CGImageRef maskImage = [image CGImageForProposedRect:&maskRect context:[NSGraphicsContext currentContext] hints:nil];
    CGContextClipToMask(context, maskRect, maskImage);

    NSBezierPath *path = [NSBezierPath bezierPathWithRect:imageRect];

    if ([controlView isKindOfClass:[PlayButton class]]) {
        [[(PlayButton *)controlView iconColor] set];
    }

    if ([self isEnabled]) {
        [path fill];

    } else {
        CGContextSaveGState(context);
        CGContextSetAlpha(context, 0.5);
        [path fill];
        CGContextRestoreGState(context);
    }

    if ([self isHighlighted]) {
        [[NSColor colorNamed:@"TrackingTint"] set];
        [path fill];
    }

    CGContextRestoreGState(context);
}


- (NSRect) drawTitle:(NSAttributedString *)title withFrame:(NSRect)frame inView:(NSView *)controlView
{
    return CGRectZero;
}


@end


@implementation PlayButton

- (void) setIconColor:(NSColor *)iconColor
{
    if (_iconColor != iconColor) {
        _iconColor = iconColor;
        [self setNeedsDisplay:YES];
    }
}

@end
