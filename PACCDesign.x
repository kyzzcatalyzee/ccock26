#import "PACC.h"

static const NSInteger PACCDesignTagSliderGlyph = 18003;

%hook CCUIBaseSliderView

static NSString *PACCDesignModuleIdentifier(UIResponder *responder) {
    UIResponder *current = responder;
    while (current) {
        if ([current isKindOfClass:UIViewController.class]) {
            for (NSString *key in @[@"moduleIdentifier", @"_moduleIdentifier"]) {
                @try {
                    id value = [(id)current valueForKey:key];
                    if ([value isKindOfClass:NSString.class]) return [value lowercaseString];
                } @catch (__unused NSException *exception) {}
            }
        }
        current = [current nextResponder];
    }
    return nil;
}

// v0.8.70: the white fill of the Brightness/Volume sliders did not follow the module's rounded shape
// (square top edge, different corner radius). Take the radius of the nearest rounded ancestor (the glass
// background) and apply it to the slider and its full-width layers, clipped, so the white matches the background.
static void PACCDesignFixSliderRadius(UIView *slider) {
    CGSize S = slider.bounds.size;
    if (S.width < 20.0 || S.height < 20.0) return;
    CGFloat r = 0.0;
    UIView *anc = slider.superview;
    for (int d = 0; anc && d < 8; d++, anc = anc.superview) {
        if (anc.layer.cornerRadius > 1.0) { r = anc.layer.cornerRadius; break; }
    }
    if (r <= 1.0) return;
    r = MIN(r, MIN(S.width, S.height) * 0.5);
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:slider];
    NSUInteger visited = 0;
    while (queue.count && visited++ < 30) {
        UIView *v = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if (v.tag == PACCDesignTagSliderGlyph) continue;
        BOOL big = (v == slider) || (v.bounds.size.width >= S.width * 0.9 && v.bounds.size.height >= 8.0);
        if (!big) continue;
        if (fabs(v.layer.cornerRadius - r) > 0.5) v.layer.cornerRadius = r;
        v.layer.cornerCurve = kCACornerCurveContinuous;
        v.layer.masksToBounds = YES;
        [queue addObjectsFromArray:v.subviews];
    }
}

static void PACCDesignColorSliderGlyph(UIView *slider, float value, BOOL animate) {
    NSMutableString *identity = [NSMutableString string];
    UIView *ancestor = slider;
    while (ancestor) {
        if (ancestor.accessibilityLabel.length) [identity appendFormat:@" %@", ancestor.accessibilityLabel.lowercaseString];
        ancestor = ancestor.superview;
    }
    NSString *identifier = PACCDesignModuleIdentifier(slider.nextResponder);
    if ([identity containsString:@"flashlight"] || [identifier containsString:@"flashlight"]) return;

    BOOL brightness = [identity containsString:@"brightness"] || [identifier containsString:@"displaymodule"];
    BOOL volume     = [identity containsString:@"volume"]
                   || [identifier containsString:@"controlcenter.audio"]
                   || [identifier containsString:@"volumemodule"];
    if (!brightness && !volume) return;
    PACCDesignFixSliderRadius(slider);

    for (NSString *key in @[@"_activeGlyphView", @"_glyphImageView", @"_glyphPackageView", @"_compensatingGlyphView"]) {
        @try {
            UIView *nativeGlyph = [(id)slider valueForKey:key];
            if ([nativeGlyph isKindOfClass:UIView.class]) nativeGlyph.hidden = YES;
        } @catch (__unused NSException *exception) {}
    }

    UIColor *color = value >= 0.20f
        ? (brightness ? UIColor.systemYellowColor : [UIColor colorWithRed:0.25 green:0.74 blue:1.0 alpha:1.0])
        : UIColor.whiteColor;

    UIImageSymbolConfiguration *sizeCfg = [UIImageSymbolConfiguration configurationWithPointSize:24.0 weight:UIImageSymbolWeightRegular];
    UIImage *image;
    if (brightness) {
        image = [UIImage systemImageNamed:@"sun.max.fill" withConfiguration:sizeCfg];
    } else {
        NSString *name = value <= 0.001f ? @"speaker.slash.fill"
                        : value >= 0.66f  ? @"speaker.wave.3.fill"
                        : value >= 0.33f  ? @"speaker.wave.2.fill"
                        : @"speaker.wave.1.fill";
        image = [UIImage systemImageNamed:name withConfiguration:sizeCfg];
    }
    image = [image imageByApplyingSymbolConfiguration:[UIImageSymbolConfiguration configurationWithHierarchicalColor:color]];

    UIImageView *glyph = (UIImageView *)[slider viewWithTag:PACCDesignTagSliderGlyph];
    if (!glyph) {
        glyph = [[UIImageView alloc] initWithFrame:CGRectMake(0.0, 0.0, 44.0, 44.0)];
        glyph.tag = PACCDesignTagSliderGlyph;
        glyph.userInteractionEnabled = NO;
        glyph.contentMode = UIViewContentModeCenter;
        [slider addSubview:glyph];
    }

    if ([slider respondsToSelector:NSSelectorFromString(@"glyphCenter")]) {
        CGPoint center = ((CGPoint (*)(id, SEL))objc_msgSend)(slider, NSSelectorFromString(@"glyphCenter"));
        glyph.center = center;
    } else {
        glyph.center = CGPointMake(CGRectGetMidX(slider.bounds), CGRectGetMidY(slider.bounds));
    }

    void (^changes)(void) = ^{ glyph.image = image; glyph.tintColor = color; glyph.alpha = 1.0; };
    if (animate && glyph.image) {
        [UIView transitionWithView:glyph
                          duration:0.13
                           options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionBeginFromCurrentState
                        animations:changes
                        completion:nil];
    } else {
        changes();
    }
    [slider bringSubviewToFront:glyph];
}

- (void)setValue:(float)value {
    %orig;
    if (!gEnabled) return;
    PACCDesignColorSliderGlyph((UIView *)(id)self, value, YES);
}

- (void)layoutSubviews {
    %orig;
    if (!gEnabled) return;
    float value = ((float (*)(id, SEL))objc_msgSend)((id)self, @selector(value));
    PACCDesignColorSliderGlyph((UIView *)(id)self, value, NO);
}

- (void)_setActiveGlyphView:(id)view {
    %orig;
    if (!gEnabled) return;
    float value = ((float (*)(id, SEL))objc_msgSend)((id)self, @selector(value));
    PACCDesignColorSliderGlyph((UIView *)(id)self, value, NO);
}

%end