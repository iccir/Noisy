// (c) 2025-2026 Ricci Adams
// MIT License (or) 1-clause BSD License

#import "SegmentedControl.h"


@implementation SegmentedControl 

/*
    NSSegmentedControl's last segment can be off by 0-N pixels,
    where N is the number of segments. This makes it impossible
    to align the right edge of our segmented control to the right
    edge of the volume slider.
    
    To work around this: perform [super layout], find the rightmost
    NSSegmentItemView, and then adjust its frame manually.
*/
- (void) layout
{
    [super layout];

    NSView *lastSegmentedItemView = nil;
    CGFloat lastMaxX = 0;

    for (NSView *view in [self subviews]) {
        if ([NSStringFromClass([view class]) isEqualToString:@"NSSegmentItemView"]) {
            CGFloat maxX = CGRectGetMaxX([view frame]);
            if (maxX > lastMaxX) {
                lastSegmentedItemView = view;
                lastMaxX = maxX;
            }
        }
    }
 
    if (lastSegmentedItemView) {
        CGRect bounds = [self bounds];

        CGRect frame = [lastSegmentedItemView frame];
        frame.size.width += (bounds.size.width - lastMaxX);
        [lastSegmentedItemView setFrame:frame];
    }
}

@end

