#import "PACC.h"

BOOL gPagerScrubbing = NO;

%hook CALayer
- (CGFloat)cornerRadius {
    CGFloat radius = %orig;
    if ([self.superlayer.delegate
         isKindOfClass:NSClassFromString(@"CCUIButtonModuleView")]) {
        radius = calculatedRadius(self.visibleRect, radius);
    }
    return radius;
}
%end

%hook MTMaterialLayer
- (CGFloat)cornerRadius {
    CGFloat radius = %orig;
    NSArray<NSString *> *titles = @[@"modules", @"moduleFill.highlight.generatedRecipe"];
    if ([titles containsObject:self.recipeName]) {
        radius = calculatedRadius(self.visibleRect, radius);
    }
    return radius;
}
%end

%hook CCUIModuleCollectionView
- (void)didMoveToWindow {
    %orig;
    if (!gEnabled) return;
    if (self.window) {
        [PACC.shared installMediaPlayerOnCollectionView:(UIScrollView *)self];
        [PACC.shared installPromoPageOnCollectionView:(UIScrollView *)self];
    }
}

- (void)layoutSubviews {
    static void *kPACCInLayoutKey = &kPACCInLayoutKey;

    if (objc_getAssociatedObject(self, kPACCInLayoutKey)) {
        %orig;
        return;
    }

    objc_setAssociatedObject(self, kPACCInLayoutKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    %orig;
    if (!gEnabled) {
        objc_setAssociatedObject(self, kPACCInLayoutKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }

    UIScrollView *scroll = (UIScrollView *)(id)self;

    [PACC.shared layoutMediaPlayerForCollectionView:scroll];
    [PACC.shared layoutPromoPageForCollectionView:scroll];
    PACCClonesRelayout(scroll);

    if (fabs(scroll.contentOffset.x) > 0.25 || fabs(scroll.contentOffset.y) > 0.25) {
        [scroll setContentOffset:CGPointZero animated:NO];
    }

    BOOL notched = (CGRectGetHeight(UIScreen.mainScreen.bounds) >= 800.0);
    if (!notched && !gPagerScrubbing) {
        CGFloat span = PageSpan();
        if (span > 0.0) {
            CATransform3D t = self.layer.sublayerTransform;
            CGFloat expected = -(CGFloat)gCurrentPage * span;
            if (fabs(t.m42 - expected) > 0.5) {
                t.m41 = 0.0;
                t.m42 = expected;
                t.m43 = 0.0;
                self.layer.sublayerTransform = t;
            }
        }
    }

    objc_setAssociatedObject(self, kPACCInLayoutKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
%end

%hook CCUIModularControlCenterOverlayViewController
- (void)moduleCollectionViewController:(id)collection willOpenExpandedModule:(id)module {
    gCCAModuleExpanded = YES;
    UIViewController *overlay = (UIViewController *)(id)self;
    UIView *indicator = [overlay.view viewWithTag:kPageIndicatorTag];
    [UIView animateWithDuration:0.2 animations:^{
        indicator.alpha = 0.0;
    } completion:^(BOOL finished) {
        indicator.hidden = YES;
    }];
    %orig;
    (void)collection; (void)module;
}

- (void)moduleCollectionViewController:(id)collection didCloseExpandedModule:(id)module {
    %orig;
    gCCAModuleExpanded = NO;
    UIViewController *overlay = (UIViewController *)(id)self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [PACC.shared layoutPageIndicatorForOverlay:overlay];
        [PACC.shared installPageIndicatorOnOverlay:overlay];
        UIView *indicator = [overlay.view viewWithTag:kPageIndicatorTag];
        indicator.hidden = NO;
        indicator.alpha = 0.0;
        indicator.transform = CGAffineTransformIdentity;
        [UIView animateWithDuration:0.35 delay:0.05 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction animations:^{
            indicator.alpha = 1.0;
        } completion:nil];
    });
    (void)collection; (void)module;
}

- (void)setPresentationState:(NSInteger)state {
    %orig;
    UIViewController *overlay = (UIViewController *)(id)self;
    if (!overlay.view) return;

    static void *kLastPresentationStateKey = &kLastPresentationStateKey;
    NSNumber *lastState = objc_getAssociatedObject(overlay, kLastPresentationStateKey);
    BOOL stateChanged = !lastState || lastState.integerValue != state;
    objc_setAssociatedObject(overlay, kLastPresentationStateKey, @(state), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    BOOL notched = (CGRectGetHeight(UIScreen.mainScreen.bounds) >= 800.0);
    CCAMediaPlayerView *player = (CCAMediaPlayerView *)[overlay.view viewWithTag:kMediaPlayerTag];

    if (state == 1) {
        if (!notched) {
            UIViewController *collection = ModuleCollection(overlay);
            if (collection && collection.view) {
                CGFloat span = PageSpan();
                if (span > 0.0) {
                    CATransform3D t = collection.view.layer.sublayerTransform;
                    t.m41 = 0.0;
                    t.m42 = -(CGFloat)gCurrentPage * span;
                    t.m43 = 0.0;
                    collection.view.layer.sublayerTransform = t;
                }
            }
        }

        [PACC.shared updateQuickAccessButtonsForOverlay:overlay];
        [PACC.shared installPageIndicatorOnOverlay:overlay];
        [PACC.shared animateElementsInForOverlay:overlay];
        [PACC.shared adjustStatusBarForOverlay:overlay];
        [PACC.shared syncModuleVisibilityForOverlay:overlay];
        [PACC.shared applyHeaderMaterialHidden:(gCurrentPage == PACCMediaPageIndex()) forOverlay:overlay];

        if (player && stateChanged) {
            [player resetForPresentation];
            if (notched && gCurrentPage == PACCMediaPageIndex()) [player fadeIn];
        }
    } else if (state == 3) {
        [PACC.shared animateElementsOutForOverlay:overlay];

        if (player && stateChanged && gCurrentPage == PACCMediaPageIndex() && notched) {
            [player fadeOut];
        }

        NSInteger savedPage = gCurrentPage;
        gCurrentPage = 0;
        [PACC.shared adjustStatusBarForOverlay:overlay];
        gCurrentPage = savedPage;
    }
}

- (void)viewDidLayoutSubviews {
    static void *kPACCInOverlayLayoutKey = &kPACCInOverlayLayoutKey;
    if (objc_getAssociatedObject(self, kPACCInOverlayLayoutKey)) {
        %orig;
        return;
    }
    objc_setAssociatedObject(self, kPACCInOverlayLayoutKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    %orig;
    if (gEnabled) {
        UIViewController *overlay = (UIViewController *)(id)self;
        [PACC.shared layoutPageIndicatorForOverlay:overlay];
        [PACC.shared adjustStatusBarForOverlay:overlay];
    }

    objc_setAssociatedObject(self, kPACCInOverlayLayoutKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
%end

%hook MRUNowPlayingView
- (void)layoutSubviews {
    %orig;
    if (!gEnabled) return;
    PACCConfigureMedia((UIView *)(id)self);
}
%end

%hook MRUArtworkView
- (void)layoutSubviews {
    %orig;
    if (!gEnabled) return;
    UIView *view = (UIView *)(id)self;
    if (!PACCMediaMode(view)) return;
    CGFloat radius = view.layer.cornerRadius;
    for (UIView *child in view.subviews) {
        if (fabs(CGRectGetWidth(child.bounds) - CGRectGetWidth(view.bounds)) > 1.0 ||
            fabs(CGRectGetHeight(child.bounds) - CGRectGetHeight(view.bounds)) > 1.0) continue;
        child.layer.cornerRadius = radius;
        child.layer.cornerCurve = kCACornerCurveContinuous;
        child.layer.masksToBounds = YES;
    }
    UIView *backing = view.subviews.firstObject;
    NSArray *filters = PACCMediaMaterialFilters(view);
    if (backing && filters.count) { backing.backgroundColor = UIColor.whiteColor; backing.layer.filters = filters; }
}
%end

%hook MRUNowPlayingHeaderView
- (void)layoutSubviews {
    %orig;
    if (!gEnabled) return;
    UIView *view = (UIView *)(id)self;
    NSString *mode = PACCMediaMode(view);
    if (!mode) return;

    UIView *routing = PACCViewIvar(self, "_routingButton");
    UIView *label = PACCViewIvar(self, "_labelView");
    UIView *headerTransport = PACCViewIvar(self, "_transportButton");

    CGFloat width = CGRectGetWidth(view.bounds);
    CGFloat side = 40.0;

    UIView *nowPlaying = PACCAncestor(view, @"MRUNowPlayingView");
    UIView *artwork = PACCViewIvar(nowPlaying, "_artworkView");
    UIView *transport = PACCViewIvar(nowPlaying, "_transportControlsView");

    NSArray *filters = PACCMediaMaterialFilters(view);
    CGFloat labelHeight = 34.0;
    CGFloat labelY = (artwork && transport ? (CGRectGetMaxY(artwork.frame) + CGRectGetMinY(transport.frame) - labelHeight) * 0.5 : 64.0) + 6.5;

    CGRect routingFrame = CGRectMake(width - 54, 14, side, side);
    CGRect labelFrame = CGRectMake(14, labelY, width - 28, labelHeight);

    [UIView performWithoutAnimation:^{
        if (headerTransport) headerTransport.hidden = YES;

        if (routing) {
            routing.frame = routingFrame;
            routing.hidden = NO;
            routing.alpha = 1;
            routing.backgroundColor = UIColor.clearColor;
            routing.tintColor = UIColor.whiteColor;
            routing.layer.filters = nil;
            routing.layer.cornerRadius = side / 2;
            routing.layer.masksToBounds = YES;

            UIView *material = [routing viewWithTag:PACCTagMediaButtonMaterial];
            if (!material) {
                material = [UIView new];
                material.tag = PACCTagMediaButtonMaterial;
                material.userInteractionEnabled = NO;
                [routing insertSubview:material atIndex:0];
            }
            material.frame = routing.bounds;
            if (filters.count) {
                material.backgroundColor = UIColor.whiteColor;
                material.layer.filters = filters;
            } else {
                material.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.16];
                material.layer.filters = nil;
            }
            material.layer.cornerRadius = side / 2;
            material.layer.masksToBounds = YES;

            PACCResizeMediaRoutingGlyph(routing);
        }

        if (label) {
            label.frame = labelFrame;
            label.hidden = NO;
            label.alpha = 1;
        }
    }];
}
%end

%hook MRUNowPlayingLabelView
- (void)layoutSubviews {
    %orig;
    if (!gEnabled) return;

    UIView *view = (UIView *)self;
    if (!PACCMediaMode(view)) return;

    UIView *title       = PACCViewIvar(self, "_titleMarqueeView")       ?: PACCViewIvar(self, "_titleLabel");
    UIView *subtitle    = PACCViewIvar(self, "_subtitleMarqueeView")    ?: PACCViewIvar(self, "_subtitleLabel");
    UIView *placeholder = PACCViewIvar(self, "_placeholderMarqueeView");
    NSArray *filters    = PACCMediaMaterialFilters(view);

    view.layer.filters = nil;
    PACCViewIvar(self, "_routeLabel").hidden = YES;

    if ([self respondsToSelector:@selector(setTextAlignment:)]) {
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(self, @selector(setTextAlignment:), NSTextAlignmentLeft);
    }

    for (UIView *line in @[title ?: (id)NSNull.null,
                           subtitle ?: (id)NSNull.null,
                           placeholder ?: (id)NSNull.null]) {
        if ((id)line == NSNull.null) continue;
        if ([line respondsToSelector:@selector(setTextAlignment:)]) {
            ((void (*)(id, SEL, NSInteger))objc_msgSend)(line, @selector(setTextAlignment:), NSTextAlignmentLeft);
        }
        NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:line];
        while (queue.count) {
            UIView *child = queue.firstObject;
            [queue removeObjectAtIndex:0];
            if ([child isKindOfClass:UILabel.class] && filters.count) {
                ((UILabel *)child).textColor = UIColor.whiteColor;
                child.layer.filters = filters;
            }
            [queue addObjectsFromArray:child.subviews];
        }
    }

    if (placeholder && !placeholder.hidden) {
        CGFloat height = CGRectGetHeight(placeholder.bounds);
        placeholder.frame = CGRectMake(0.0,
                                       floor((CGRectGetHeight(view.bounds) - height) * 0.5),
                                       CGRectGetWidth(view.bounds),
                                       height);
    }

    if (!title || !subtitle) return;

    CGFloat width = CGRectGetWidth(view.bounds);
    CGFloat start = MAX(0, (CGRectGetHeight(view.bounds) - 31) / 2);

    title.frame    = CGRectMake(0, start,      width, 16);
    subtitle.frame = CGRectMake(0, start + 17, width, 14);

    for (UIView *line in @[title, subtitle]) {
        line.alpha = 1;
        NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithArray:line.subviews];
        while (queue.count) {
            UIView *child = queue.firstObject;
            [queue removeObjectAtIndex:0];
            if ([child isKindOfClass:UILabel.class]) {
                ((UILabel *)child).font = [UIFont systemFontOfSize:13
                                                          weight:(line == title
                                                                  ? UIFontWeightSemibold
                                                                  : UIFontWeightRegular)];
                ((UILabel *)child).textAlignment = NSTextAlignmentLeft;
            }
            [queue addObjectsFromArray:child.subviews];
        }
    }
}
%end

%hook MRUTransportButton
- (void)layoutSubviews {
    %orig;
    if (!gEnabled) return;
    PACCResizeMediaRoutingGlyph((UIView *)(id)self);
}
%end

%hook MRUNowPlayingTransportControlsView
- (void)layoutSubviews {
    %orig;
    if (!gEnabled) return;
    UIView *view = (UIView *)(id)self;
    NSString *mode = PACCMediaMode(view);
    if (!mode) return;

    UIView *left = PACCViewIvar(self, "_leftButton");
    UIView *center = PACCViewIvar(self, "_centerButton");
    UIView *right = PACCViewIvar(self, "_rightButton");

    if (!left || !center || !right) return;

    CGFloat width = CGRectGetWidth(view.bounds);
    CGFloat y = CGRectGetHeight(view.bounds) / 2;
    CGFloat spacing = width * 0.32;

    left.hidden = NO;
    center.center = CGPointMake(width / 2, y);
    left.center = CGPointMake(width / 2 - spacing, y);
    right.center = CGPointMake(width / 2 + spacing, y);

    PACCViewIvar(self, "_leadingButton").hidden = YES;
    PACCViewIvar(self, "_routingButton").hidden = YES;
}
%end

%hook UIViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (gEnabled && [NSStringFromClass(self.class) containsString:@"ControlCenterOverlayViewController"]) {
        [PACC.shared installOnOverlay:(UIViewController *)self];
    }
}
- (void)viewDidLayoutSubviews {
    static void *kPACCInVCLayoutKey = &kPACCInVCLayoutKey;
    if (objc_getAssociatedObject(self, kPACCInVCLayoutKey)) {
        %orig;
        return;
    }
    objc_setAssociatedObject(self, kPACCInVCLayoutKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    %orig;
    if (gEnabled && [NSStringFromClass(self.class) containsString:@"ControlCenterOverlayViewController"]) {
        [PACC.shared updateQuickAccessButtonsForOverlay:(UIViewController *)self];
        [PACC.shared layoutPageIndicatorForOverlay:(UIViewController *)self];
    }
    if ([NSStringFromClass(self.class) isEqualToString:@"CCUIConnectivityModuleViewController"]) {
        UIViewController *controller = (UIViewController *)(id)self;
        PACCConfigureConnectivity(controller);
        __weak UIViewController *weakController = controller;
        dispatch_async(dispatch_get_main_queue(), ^{ if (weakController) PACCConfigureConnectivity(weakController); });
    }

    objc_setAssociatedObject(self, kPACCInVCLayoutKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
%end

%hook CCUIContentModuleContainerView
- (void)layoutSubviews {
    %orig;
    if (gEnabled) PACCBigStripContainer((UIView *)self);
}
%end

%hook CCUIConnectivityModuleViewController
- (CGFloat)preferredExpandedContentHeight {
    return gEnabled ? 526.0 : %orig;
}
- (BOOL)providesOwnPlatter {
    if (gEnabled) {
        UIViewController *vc = (UIViewController *)self;
        CGSize size = vc.isViewLoaded ? vc.view.bounds.size : CGSizeZero;
        BOOL expanded = size.width >= 190.0 || size.height >= 190.0;
        if (!expanded) {
            @try {
                id parent = vc.parentViewController;
                if ([parent respondsToSelector:NSSelectorFromString(@"isExpanded")])
                    expanded = ((BOOL (*)(id, SEL))objc_msgSend)(parent, NSSelectorFromString(@"isExpanded"));
            } @catch (__unused NSException *e) {}
        }
        if (expanded) return YES;
    }
    return %orig;
}
%end

@interface PACCSpring : NSObject
@property (nonatomic, weak) UIView *view;
@property (nonatomic) CGFloat x, y, sx, sy, vx, vy, vsx, vsy;
@property (nonatomic) CGFloat tx, ty, tsx, tsy;
@property (nonatomic) CGFloat angle;
@property (nonatomic) CGFloat k, c;
@end

@implementation PACCSpring
- (instancetype)init {
    if ((self = [super init])) { _sx = _sy = _tsx = _tsy = 1; _k = 320; _c = 24; }
    return self;
}
- (BOOL)settled {
    return fabs(_x - _tx) < 0.02 && fabs(_y - _ty) < 0.02 && fabs(_sx - _tsx) < 0.0005 && fabs(_sy - _tsy) < 0.0005 &&
           fabs(_vx) < 0.05 && fabs(_vy) < 0.05 && fabs(_vsx) < 0.002 && fabs(_vsy) < 0.002;
}
- (void)step:(CGFloat)dt {
    int n = 4;
    CGFloat h = dt / n;
    for (int i = 0; i < n; i++) {
        _vx += (-_k * (_x - _tx) - _c * _vx) * h;     _x += _vx * h;
        _vy += (-_k * (_y - _ty) - _c * _vy) * h;     _y += _vy * h;
        _vsx += (-_k * (_sx - _tsx) - _c * _vsx) * h; _sx += _vsx * h;
        _vsy += (-_k * (_sy - _tsy) - _c * _vsy) * h; _sy += _vsy * h;
    }
}
- (CGAffineTransform)transform {
    CGAffineTransform t = CGAffineTransformMakeTranslation(_x, _y);
    t = CGAffineTransformRotate(t, _angle);
    t = CGAffineTransformScale(t, _sx, _sy);
    return CGAffineTransformRotate(t, -_angle);
}
@end

static const void *kPACCSpring = &kPACCSpring;
static NSHashTable *gPACCActiveSprings;
static CADisplayLink *gPACCSpringLink;

@interface PACCSpringTicker : NSObject
+ (instancetype)shared;
@end

@implementation PACCSpringTicker
+ (instancetype)shared {
    static PACCSpringTicker *t;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ t = [PACCSpringTicker new]; });
    return t;
}
- (void)step:(CADisplayLink *)link {
    CGFloat dt = link.targetTimestamp - link.timestamp;
    if (dt <= 0 || dt > 0.05) dt = 1.0 / 120.0;
    for (PACCSpring *s in [gPACCActiveSprings allObjects]) {
        UIView *v = s.view;
        if (!v) { [gPACCActiveSprings removeObject:s]; continue; }
        [s step:dt];
        if ([s settled]) {
            s.x = s.tx; s.y = s.ty; s.sx = s.tsx; s.sy = s.tsy; s.vx = s.vy = s.vsx = s.vsy = 0;
            [gPACCActiveSprings removeObject:s];
        }
        v.transform = [s transform];
    }
    if (!gPACCActiveSprings.count) { [gPACCSpringLink invalidate]; gPACCSpringLink = nil; }
}
@end

static PACCSpring *PACCSpringFor(UIView *v) {
    PACCSpring *s = objc_getAssociatedObject(v, kPACCSpring);
    if (!s) {
        s = [PACCSpring new];
        s.view = v;
        objc_setAssociatedObject(v, kPACCSpring, s, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return s;
}

static void PACCWakeSpring(PACCSpring *s) {
    if (!gPACCActiveSprings) gPACCActiveSprings = [NSHashTable hashTableWithOptions:NSPointerFunctionsStrongMemory];
    [gPACCActiveSprings addObject:s];
    if (!gPACCSpringLink) {
        gPACCSpringLink = [CADisplayLink displayLinkWithTarget:[PACCSpringTicker shared] selector:@selector(step:)];
        if (@available(iOS 15.0, *)) gPACCSpringLink.preferredFrameRateRange = CAFrameRateRangeMake(60, 120, 120);
        [gPACCSpringLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }
}

static BOOL PACCInControlCenter(UIView *v) {
    int d = 0;
    for (UIView *p = v; p && d < 40; p = p.superview, d++) {
        NSString *n = NSStringFromClass([p class]);
        if ([n hasPrefix:@"CCUI"] || [n containsString:@"ControlCenter"]) return YES;
    }
    return NO;
}

static UIView *PACCSliderShell(UIView *slider) {
    UIView *best = slider, *p = slider.superview;
    for (int d = 0; p && d < 6; d++, p = p.superview) {
        if (fabs(p.bounds.size.width - slider.bounds.size.width) <= 6 && fabs(p.bounds.size.height - slider.bounds.size.height) <= 6) best = p;
        else if (p.bounds.size.width > slider.bounds.size.width + 6 || p.bounds.size.height > slider.bounds.size.height + 6) break;
    }
    return best;
}

static void PACCApplyStretch(UIView *slider, CGFloat over, int dir) {
    UIView *v = PACCSliderShell(slider);
    CGFloat H = v.bounds.size.height;
    if (H < 1) return;
    PACCSpring *s = PACCSpringFor(v);
    CGFloat stretch = (!gSliderBounceEnabled || over <= 0) ? 0 : MIN((1.0 - 1.0 / (over * 0.5 / H + 1.0)) * H, H * 0.12);
    CGFloat r = stretch / H;
    s.k = 900; s.c = 60; s.angle = 0;
    s.tx = 0; s.ty = -dir * stretch / 2; s.tsx = 1.0 - r * 0.35; s.tsy = 1.0 + r;
    PACCWakeSpring(s);
}

static void PACCReleaseStretch(UIView *slider) {
    UIView *v = PACCSliderShell(slider);
    PACCSpring *s = objc_getAssociatedObject(v, kPACCSpring);
    if (!s) return;
    s.k = 95; s.c = 19.5;
    s.vx = s.vy = s.vsx = s.vsy = 0;
    s.tx = 0; s.ty = 0; s.tsx = 1; s.tsy = 1;
    PACCWakeSpring(s);
}

@interface PACCBouncer : NSObject <UIGestureRecognizerDelegate>
+ (instancetype)shared;
@end

@implementation PACCBouncer
+ (instancetype)shared {
    static PACCBouncer *b;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ b = [PACCBouncer new]; });
    return b;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)a shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)b {
    return YES;
}
- (void)pan:(UIPanGestureRecognizer *)g {
    UIView *v = g.view;
    if (!v || !v.superview || !gEnabled || !gSliderBounceEnabled) return;
    CGFloat H = v.bounds.size.height;
    if (H < 1) return;
    if (g.state == UIGestureRecognizerStateBegan || g.state == UIGestureRecognizerStateChanged) {
        CGFloat over = 0;
        int dir = 0;
        CGFloat top = v.center.y - H / 2, bottom = v.center.y + H / 2;
        CGFloat y = [g locationInView:v.superview].y;
        if (y < top) { over = top - y; dir = 1; }
        else if (y > bottom) { over = y - bottom; dir = -1; }
        PACCApplyStretch(v, over, dir);
    } else if (g.state >= UIGestureRecognizerStateEnded) {
        PACCReleaseStretch(v);
    }
}
@end

static const void *kPACCPanAdded = &kPACCPanAdded;

static void PACCAddBounce(UIView *slider) {
    if (objc_getAssociatedObject(slider, kPACCPanAdded)) return;
    objc_setAssociatedObject(slider, kPACCPanAdded, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:[PACCBouncer shared] action:@selector(pan:)];
    pan.delegate = [PACCBouncer shared];
    pan.cancelsTouchesInView = NO;
    pan.delaysTouchesBegan = NO;
    pan.delaysTouchesEnded = NO;
    [slider addGestureRecognizer:pan];
}

static const void *kPACCJelly = &kPACCJelly;
static const void *kPACCJellyStart = &kPACCJellyStart;
static const void *kPACCJellyLast = &kPACCJellyLast;

@interface PACCJelly : NSObject <UIGestureRecognizerDelegate>
+ (instancetype)shared;
@end

@implementation PACCJelly
+ (instancetype)shared {
    static PACCJelly *j;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ j = [PACCJelly new]; });
    return j;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)a shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)b {
    return YES;
}
- (void)press:(UILongPressGestureRecognizer *)g {
    UIView *v = g.view;
    if (!v || !v.superview) return;
    PACCSpring *s = PACCSpringFor(v);
    if (!gEnabled || !gSliderBounceEnabled || gEditModeActive) {
        s.tx = s.ty = 0; s.tsx = s.tsy = 1;
        PACCWakeSpring(s);
        return;
    }
    CGPoint p = [g locationInView:v.superview];
    if (g.state == UIGestureRecognizerStateBegan) {
        objc_setAssociatedObject(v, kPACCJellyStart, [NSValue valueWithCGPoint:p], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        s.k = 420; s.c = 24;
        s.tx = s.ty = 0; s.tsx = s.tsy = 1.08; s.angle = 0;
        PACCWakeSpring(s);
    } else if (g.state == UIGestureRecognizerStateChanged) {
        CGPoint st = [objc_getAssociatedObject(v, kPACCJellyStart) CGPointValue];
        CGFloat dx = p.x - st.x, dy = p.y - st.y, dist = hypot(dx, dy);
        CGFloat damp = 0.16 / (1.0 + dist / 110.0);
        CGFloat stretch = MIN(dist / 380.0, 0.09);
        s.k = 650; s.c = 42;
        s.tx = dx * damp; s.ty = dy * damp;
        if (dist > 2) s.angle = atan2(dy, dx);
        s.tsx = 1.08 + stretch; s.tsy = 1.08 - stretch * 0.6;
        PACCWakeSpring(s);
        objc_setAssociatedObject(v, kPACCJellyLast, @[[NSValue valueWithCGPoint:p], @(CACurrentMediaTime())], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else if (g.state >= UIGestureRecognizerStateEnded) {
        NSArray *last = objc_getAssociatedObject(v, kPACCJellyLast);
        if (last) {
            CGPoint lp = [last[0] CGPointValue];
            CGFloat dt = MAX(CACurrentMediaTime() - [last[1] doubleValue], 1.0 / 120.0);
            s.vx += MAX(-160, MIN(160, (p.x - lp.x) / dt * 0.12));
            s.vy += MAX(-160, MIN(160, (p.y - lp.y) / dt * 0.12));
        }
        objc_setAssociatedObject(v, kPACCJellyLast, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        s.k = 300; s.c = 10;
        s.tx = s.ty = 0; s.tsx = s.tsy = 1;
        s.vsx += 0.6; s.vsy -= 0.6;
        PACCWakeSpring(s);
    }
}
@end

static void PACCAddJelly(UIView *v) {
    if (objc_getAssociatedObject(v, kPACCJelly)) return;
    objc_setAssociatedObject(v, kPACCJelly, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:[PACCJelly shared] action:@selector(press:)];
    lp.minimumPressDuration = 0;
    lp.allowableMovement = CGFLOAT_MAX;
    lp.cancelsTouchesInView = NO;
    lp.delaysTouchesBegan = NO;
    lp.delaysTouchesEnded = NO;
    lp.delegate = [PACCJelly shared];
    [v addGestureRecognizer:lp];
}

%hook CCUIBaseSliderView
- (void)didMoveToWindow {
    %orig;
    UIView *sv = (UIView *)(id)self;
    if (sv.window && gEnabled && PACCInControlCenter(sv)) PACCAddBounce(sv);
}
%end

%hook CCUIRoundButton
- (void)didMoveToWindow {
    %orig;
    UIView *sv = (UIView *)(id)self;
    if (sv.window && gEnabled && PACCInControlCenter(sv)) PACCAddJelly(sv);
}
%end

%hook CCUIButtonModuleView
- (void)didMoveToWindow {
    %orig;
    UIView *sv = (UIView *)(id)self;
    if (sv.window && gEnabled && PACCInControlCenter(sv)) PACCAddJelly(sv);
}
%end

%hook CCUISliderModuleViewController
- (void)viewDidLayoutSubviews {
    %orig;
    if (!gEnabled) return;

    UIViewController *vc = (UIViewController *)self;
    NSString *className = NSStringFromClass(vc.class);
    UIColor *tintColor = nil;

    if ([className containsString:@"Brightness"]) {
        tintColor = [UIColor colorWithRed:1.0 green:0.85 blue:0.0 alpha:1.0];
    } else if ([className containsString:@"Volume"]) {
        tintColor = [UIColor colorWithRed:0.0 green:0.8 blue:1.0 alpha:1.0];
    }

    if (tintColor) {
        for (UIView *sub in vc.view.subviews) {
            if ([sub isKindOfClass:[UISlider class]]) {
                UISlider *slider = (UISlider *)sub;
                slider.tintColor = tintColor;
                slider.minimumTrackTintColor = tintColor;
            }
            if ([NSStringFromClass(sub.class) containsString:@"Slider"]) {
                sub.tintColor = tintColor;
                for (UIView *child in sub.subviews) {
                    child.tintColor = tintColor;
                }
            }
        }
    }
}
%end

static void PrefsChanged(__unused CFNotificationCenterRef center, __unused void *observer, __unused CFStringRef name, __unused const void *object, __unused CFDictionaryRef userInfo) {
    LoadPrefs();
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *overlay = OverlayIn(UIApplication.sharedApplication.keyWindow.rootViewController);
        if (overlay) [PACC.shared installOnOverlay:overlay];
    });
}

%ctor {
    @autoreleasepool {
        LoadPrefs();
        %init(_ungrouped);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, PrefsChanged,
                                        (__bridge CFStringRef)kReloadNotification, NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
    }
}