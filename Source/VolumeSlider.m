// (c) 2024-2026 Ricci Adams
// MIT License (or) 1-clause BSD License

#import "VolumeSlider.h"
#import "Utils.h"


@interface VolumeSliderCell : NSSliderCell
@property (nonatomic, readonly, getter=isTracking) BOOL tracking;
@end


@implementation VolumeSliderCell 


- (BOOL) startTrackingAt:(NSPoint)startPoint inView:(NSView *)controlView
{
    _tracking = YES;
    return [super startTrackingAt:startPoint inView:controlView];
}


- (void) stopTracking:(NSPoint)lastPoint at:(NSPoint)stopPoint inView:(NSView *)controlView mouseIsUp:(BOOL)flag
{
    _tracking = NO;
    return [super stopTracking:lastPoint at:stopPoint inView:controlView mouseIsUp:flag];
}


- (CGRect) knobRectFlipped:(BOOL)flipped
{
    float floatValue = [self floatValue];

    CGRect bounds   = [[self controlView] bounds];
    CGRect knobArea = CGRectInset(bounds, 3, 3);

    CGFloat knobWidth = knobArea.size.height;
    CGFloat valueX = round(knobArea.origin.x + ((knobArea.size.width - knobWidth) * floatValue));

    CGRect knobRect = knobArea;
    knobRect.origin.x = valueX;
    knobRect.size.width = knobWidth;

    return knobRect;
}


- (CGRect) barRectFlipped:(BOOL)flipped
{
    CGRect bounds = [[self controlView] bounds];

    return CGRectInset(bounds, 2, 2);
}


- (void) drawKnob:(NSRect)knobRect
{
    NSBezierPath *knobPath = [NSBezierPath bezierPathWithOvalInRect:knobRect];
    NSColor *trackingTint = _tracking ? [NSColor colorNamed:@"TrackingTint"] : nil;

    CGContextRef context = [[NSGraphicsContext currentContext] CGContext];

    __auto_type makeRoundedPath = ^(CGRect rect) {
        CGFloat radius = rect.size.height / 2.0;
        return [NSBezierPath bezierPathWithRoundedRect:rect xRadius:radius yRadius:radius];
    };

    __auto_type blendTracking = ^(NSColor *inColor) {
        if (!trackingTint) return inColor;
        
        CGFloat trackingAlpha = [trackingTint alphaComponent];
        NSColor *colorToBlend = [trackingTint colorWithAlphaComponent:1.0];
        
        return [inColor blendedColorWithFraction:trackingAlpha ofColor:colorToBlend];
    };

    __auto_type drawHighlightBorder = ^(CGRect rect, NSColor *topColor, NSColor *bottomColor) {
        NSBezierPath *outerPath = makeRoundedPath(rect);
        NSBezierPath *innerPath = makeRoundedPath(CGRectInset(rect, 0.5, 0.5));

        [outerPath appendBezierPath:[innerPath bezierPathByReversingPath]];
        
        NSGradient *gradient = [[NSGradient alloc] initWithColors:@[ topColor, bottomColor ]];
        [gradient drawInBezierPath:outerPath angle:90];
    };

    CGContextSaveGState(context);
    
    NSShadow *shadow = [[NSShadow alloc] init];
    [shadow setShadowBlurRadius:4];
    [shadow setShadowColor:[NSColor colorWithWhite:0 alpha:0.15]];
    [shadow set];

    CGContextBeginTransparencyLayer(context, NULL);
    
    [knobPath addClip];

    NSGradient *gradient = [[NSGradient alloc] initWithColors:@[
        blendTracking([NSColor colorNamed:@"ButtonTopColor"]),
        blendTracking([NSColor colorNamed:@"ButtonBottomColor"])
    ]];

    [gradient drawInRect:knobRect angle:90];

    CGContextEndTransparencyLayer(context);
    CGContextRestoreGState(context);

    // Draw knob highlight
    drawHighlightBorder(
        knobRect,
        [NSColor colorWithWhite:1 alpha:0.25],
        [NSColor colorWithWhite:1 alpha:0.00]
    );

    NSBezierPath *borderPath = [NSBezierPath bezierPathWithOvalInRect:CGRectInset(knobRect, -0.5, -0.5)];

    [[NSColor colorWithWhite:0 alpha:0.1] set];
    [borderPath setLineWidth:1];
    [borderPath stroke];
}


- (void) drawBarInside:(NSRect)inRect flipped:(BOOL)flipped
{
    CGContextRef context = [[NSGraphicsContext currentContext] CGContext];

    __auto_type makeRoundedPath = ^(CGRect rect) {
        CGFloat radius = rect.size.height / 2.0;
        return [NSBezierPath bezierPathWithRoundedRect:rect xRadius:radius yRadius:radius];
    };

    __auto_type clamp = ^(CGFloat inFloat) {
        if      (inFloat < 0.0) return 0.0;
        else if (inFloat > 1.0) return 1.0;
        else                    return inFloat;
    };

    CGContextSaveGState(context);

    float floatValue = [self floatValue];

    CGRect outerRect = inRect;
    CGRect innerRect = CGRectInset(inRect, 1, 1);
    CGRect knobRect  = [self knobRectFlipped:flipped];
    
    CGRect fillRect = outerRect;
    fillRect.size.width = CGRectGetMidX(knobRect) - fillRect.origin.x;

    // Draw well
    {
        NSBezierPath *outerPath = makeRoundedPath(outerRect);
        [outerPath addClip];

        NSGradient *wellGradient = [[NSGradient alloc] initWithColors:@[
            [NSColor colorNamed:@"WellTopColor"],
            [NSColor colorNamed:@"WellBottomColor"]
        ] ];

        [wellGradient drawInRect:outerRect angle:90];
        
        CGContextSaveGState(context);
        CGContextClipToRect(context, fillRect);

        NSGradient *gradient = [[NSGradient alloc] initWithColors:@[
            [NSColor colorNamed:@"SliderFillTopColor"],
            [NSColor colorNamed:@"SliderFillBottomColor"]
        ]];

        NSBezierPath *fillPath = makeRoundedPath(innerRect);
        [gradient drawInBezierPath:fillPath angle:90];

        CGContextRestoreGState(context);

        [[NSColor colorNamed:@"WellBorderColor"] set];
        [outerPath setLineWidth:2];
        [outerPath stroke];
    }

    // Draw speaker icon
    {
        NSColor *iconColor = [NSColor colorNamed:@"ButtonIconColor"];
        [iconColor set];

        NSImage *icon = [NSImage imageNamed:@"SpeakerIcon"];
        NSSize iconSize = [icon size];

        CGRect iconRect = inRect;
        iconRect.origin.x += 6;
        iconRect.origin.y += (inRect.size.height - iconSize.height) / 2.0;
        iconRect.size = iconSize;

        CGFloat globalAlpha = clamp((knobRect.origin.x - (innerRect.origin.x + 6)) / 10.0);

        CGContextSaveGState(context);
        NSRect maskRect = iconRect;
        CGImageRef maskImage = [icon CGImageForProposedRect:&iconRect context:[NSGraphicsContext currentContext] hints:nil];
        CGContextClipToMask(context, maskRect, maskImage);
        CGContextSetAlpha(context, globalAlpha);
        CGContextFillRect(context, maskRect);
        CGContextRestoreGState(context);

        CGFloat wave1Opacity = clamp( floatValue        * 2.0) * globalAlpha;
        CGFloat wave2Opacity = clamp((floatValue - 0.5) * 2.0) * globalAlpha;
       
        CGFloat widthInDegrees = 90;
        CGFloat widthInAngles = (widthInDegrees / 180.0) * M_PI;
        
        CGFloat startAngle = -widthInAngles / 2.0;
        CGFloat endAngle  =   widthInAngles / 2.0;
        CGContextSetLineWidth(context, 1.25);
        CGContextSetLineCap(context, kCGLineCapRound);

        CGPoint center = CGPointMake(
            CGRectGetMaxX(iconRect),
            CGRectGetMidY(iconRect)
        );

        CGContextSaveGState(context);

        CGContextBeginPath(context);
        CGContextAddArc(context, center.x, center.y, 3, startAngle, endAngle, NO);
        CGContextSetAlpha(context, wave1Opacity);
        CGContextStrokePath(context);

        CGContextBeginPath(context);
        CGContextAddArc(context, center.x, center.y, 6, startAngle, endAngle, NO);
        CGContextSetAlpha(context, wave2Opacity);
        CGContextStrokePath(context);
    
        CGContextRestoreGState(context);
    }

    CGContextRestoreGState(context);
}

@end


@implementation VolumeSlider

@end

