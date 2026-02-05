// (c) 2025-2026 Ricci Adams
// MIT License (or) 1-clause BSD License

#import "Switch.h"

#if 0
// Switch is currently unused

@import QuartzCore;

@interface Switch ()
@property (nonatomic) CGFloat knobX;
@end



@implementation Switch {
    CGRect  _outerRect;
    CGRect  _innerRect;
    CGRect  _knobRect;
    CGFloat _minKnobX;
    CGFloat _maxKnobX;

    BOOL    _didDrag;
    BOOL    _didSendActionForDrag;
    BOOL    _mouseDown;
    CGPoint _mouseDownPoint;
    
    NSTimer *_animationTimer;
    CGFloat  _animationValue;
}


#pragma mark - Superclass Overrides

- (instancetype) initWithFrame:(NSRect)frameRect
{
    if ((self = [super initWithFrame:frameRect])) {
        [self _computeMetrics];
    }

    return self;
}


- (void) drawRect:(NSRect)dirtyRect
{
    NSColor *onTopColor    = [NSColor colorNamed:@"SwitchOnTopColor"];
    NSColor *onBottomColor = [NSColor colorNamed:@"SwitchOnBottomColor"];

    if (![[self window] isMainWindow]) {
        onTopColor    = [onTopColor    colorUsingColorSpace:[NSColorSpace genericGamma22GrayColorSpace]];
        onBottomColor = [onBottomColor colorUsingColorSpace:[NSColorSpace genericGamma22GrayColorSpace]];
    }

    NSColor *trackingTint = _mouseDown ? [NSColor colorNamed:@"TrackingTint"] : nil;

    CGContextRef context = [[NSGraphicsContext currentContext] CGContext];
    
    double value = _animationTimer ? _animationValue : (_on ? 1.0 : 0.0);
    
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

    CGRect knobRect = _knobRect;
    knobRect.origin.x = _minKnobX + ((_maxKnobX - _minKnobX) * value);

    CGContextSaveGState(context);

    // Draw well
    {
        NSBezierPath *outerPath = makeRoundedPath(_outerRect);
        [outerPath addClip];
        
        NSColor *topColor    = [NSColor colorNamed:@"WellTopColor"];
        NSColor *bottomColor = [NSColor colorNamed:@"WellBottomColor"];

        topColor    = [topColor    blendedColorWithFraction:value ofColor:onTopColor];
        bottomColor = [bottomColor blendedColorWithFraction:value ofColor:onBottomColor];

        NSGradient *wellGradient = [[NSGradient alloc] initWithColors:@[ topColor, bottomColor ]];

        [wellGradient drawInRect:[self bounds] angle:90];

        [outerPath setLineWidth:2];
        [[NSColor colorWithWhite:0.0 alpha:0.1] set];
        [outerPath stroke];
    }

    // Draw knob
    {
        NSBezierPath *knobPath = [NSBezierPath bezierPathWithOvalInRect:knobRect];

        CGContextSaveGState(context);
        
        NSShadow *shadow = [[NSShadow alloc] init];
        [shadow setShadowBlurRadius:4];
        [shadow setShadowColor:[NSColor colorWithWhite:0 alpha:0.15]];
        [shadow set];

        CGContextBeginTransparencyLayer(context, NULL);
        
        [knobPath addClip];

        NSColor *topColor    = [NSColor colorNamed:@"ButtonTopColor"];
        NSColor *bottomColor = [NSColor colorNamed:@"ButtonBottomColor"];

        NSGradient *gradient = [[NSGradient alloc] initWithColors:@[
            blendTracking(topColor),
            blendTracking(bottomColor)
        ]];

        [gradient drawInRect:knobRect angle:90];
       
        CGContextEndTransparencyLayer(context);
        CGContextRestoreGState(context);

        // Draw border
        NSBezierPath *borderPath = [NSBezierPath bezierPathWithOvalInRect:CGRectInset(knobRect, -0.5, -0.5)];
        [[NSColor colorWithWhite:0 alpha:0.1] set];
        [borderPath setLineWidth:1];
        [borderPath stroke];
    }

    // Draw icon
    {
        NSImage *image = [self image];
        NSRect imageRect = knobRect;
       
        CGSize imageSize = [image size];
        imageRect.origin.x += (imageRect.size.width - imageSize.width) / 2;
        imageRect.origin.y += (imageRect.size.height - imageSize.height) / 2;
        imageRect.size = imageSize;
    
        NSRect maskRect = imageRect;
        CGImageRef maskImage = [image CGImageForProposedRect:&maskRect context:[NSGraphicsContext currentContext] hints:nil];
        CGContextClipToMask(context, maskRect, maskImage);

        NSColor *iconColor = blendTracking([NSColor colorNamed:@"ButtonIconColor"]);

        if (![[self window] isMainWindow]) {
            iconColor = [iconColor colorUsingColorSpace:[NSColorSpace genericGamma22GrayColorSpace]];
        }

        NSGradient *iconGradient = [[NSGradient alloc] initWithColors:@[
            [iconColor blendedColorWithFraction:value ofColor:onTopColor],
            [iconColor blendedColorWithFraction:value ofColor:onBottomColor]
        ] ];

        [iconGradient drawInRect:imageRect angle:90];
    }

    CGContextRestoreGState(context);
}


- (BOOL) isFlipped
{
    return YES;
}


- (void) mouseDown:(NSEvent *)event
{
    if ([event clickCount] > 1)  return;

    _didDrag = NO;
    _didSendActionForDrag = NO;
    _mouseDown = YES;
    _mouseDownPoint = [self convertPoint:[event locationInWindow] fromView:nil];

    [self setNeedsDisplay:YES];
}


- (void) mouseUp:(NSEvent *)event
{
    if ([event clickCount] > 1) return;

    CGPoint mouseUpPoint = [self convertPoint:[event locationInWindow] fromView:nil];
    BOOL shouldToggle = NO;

    if (!_didSendActionForDrag) {
        double distance = sqrt(
            pow(mouseUpPoint.x - _mouseDownPoint.x, 2) +
            pow(mouseUpPoint.y - _mouseDownPoint.y, 2)
        );
        
        if (distance < 3) {
            shouldToggle = YES;
        }
        
    } else if (!_didDrag) {
        shouldToggle = YES;
    }

    if (shouldToggle) {
        [self setOn:![self isOn] animated:YES];
        [self sendAction:[self action] to:[self target]];
    }

    _didDrag = NO;
    _mouseDown = NO;

    [self setNeedsDisplay:YES];
}


- (void) mouseDragged:(NSEvent *)event
{
    CGPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
    CGFloat midX  = CGRectGetMidX([self bounds]);

    _didDrag = YES;

    // Prevent case where we are swiping towards the knob
    if (!_didSendActionForDrag) {
        if ((point.x > _mouseDownPoint.x) &&  _on) return;
        if ((point.x < _mouseDownPoint.x) && !_on) return;
    }

    BOOL shouldBeOn = NO;
    if (point.x < midX) {
        shouldBeOn = NO;
    } else {
        shouldBeOn = YES;
    }

    if (_on != shouldBeOn) {
        _didSendActionForDrag = YES;
        [self setOn:shouldBeOn animated:YES];
        [self sendAction:[self action] to:[self target]];
    }
}


#pragma mark - Private Methods

- (void) _computeMetrics
{
    _outerRect = CGRectInset([self bounds], 0, 2);
    _innerRect = CGRectInset(_outerRect, 1, 1);

    CGFloat knobWidth = MIN(_innerRect.size.width, _innerRect.size.height);

    _minKnobX = _innerRect.origin.x;
    _maxKnobX = CGRectGetMaxX(_innerRect) - knobWidth;
    _knobRect = CGRectMake(_minKnobX, _innerRect.origin.y, knobWidth, knobWidth);
}


- (void) _clearAnimation
{
    [_animationTimer invalidate];
    _animationTimer = nil;
}


- (void) _updateAnimationProgress:(double)progress
{
    _animationValue = progress;
    [self setNeedsDisplay:YES];
}


- (void) _startAnimation
{
    CFTimeInterval duration = 0.25;
    CFTimeInterval startTime = CFAbsoluteTimeGetCurrent();

    CGFloat startValue = _animationTimer ? _animationValue : (_on ? 0.0 : 1.0);
    CGFloat endValue   = _on ? 1.0 : 0.0;

    __weak id weakSelf = self;

    [self _clearAnimation];

    _animationTimer = [NSTimer scheduledTimerWithTimeInterval:(1/60.0) repeats:YES block:^(NSTimer *timer) {
        CFTimeInterval elapsed = CFAbsoluteTimeGetCurrent() - startTime;
            
        double progress = elapsed / duration;
        if (progress > 1.0) {
            progress = 1.0;
            [weakSelf _clearAnimation];
        }

        progress = sin(M_PI_2 * progress);
        progress = progress * progress;

        [weakSelf _updateAnimationProgress:(startValue + ((endValue - startValue) * progress))];
    }];
}


#pragma mark - Accessors

- (void) setOn:(BOOL)on animated:(BOOL)animated
{
    if (_on != on) {
        _on = on;

        [self setNeedsDisplay:YES];

        if (animated) {
            [self _startAnimation];
        } else {
            [self _clearAnimation];
        }
    }
}


- (void) setFrame:(NSRect)frame
{
    if (!NSEqualRects(frame, [super frame])) {
        [super setFrame:frame];
        [self _computeMetrics];
    }
}


- (void) setOn:(BOOL)on
{
    [self setOn:on animated:NO];
}


- (void) setImage:(NSImage *)image
{
    if (_image != image) {
        _image = image;
        [self setNeedsDisplay:YES];
    }
}


@end

#endif
