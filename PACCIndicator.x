#import "PACC.h"

@interface CCAPageIndicator () <UIGestureRecognizerDelegate>
@property (nonatomic, assign) BOOL dragging;
@property (nonatomic, assign) NSUInteger dragStartPage;
@property (nonatomic, assign) NSUInteger interactiveStartPage;
@property (nonatomic, assign) CGFloat interactiveProgress;
@property (nonatomic, assign) CGFloat interactiveTranslation;
@property (nonatomic, assign) CFTimeInterval interactiveBeganTime;
@property (nonatomic, assign) CFTimeInterval lastSampleTime;
@property (nonatomic, assign) CGFloat viscousProgress;
@property (nonatomic, assign) CGFloat previousRawProgress;
@property (nonatomic, assign) CGFloat filteredVelocity;
@property (nonatomic, assign) CGFloat jelloScaleX;
@property (nonatomic, assign) CGFloat jelloScaleY;
@property (nonatomic, assign) CGFloat heldScale;
@property (nonatomic, assign) CGFloat heldAlphaFactor;
@property (nonatomic, weak) UIView *savedCollectionView;
@property (nonatomic, assign) CGRect restHostFrame;
@property (nonatomic, assign) NSUInteger animationToken;
@property (nonatomic, strong) UIPanGestureRecognizer *panRecognizer;
@property (nonatomic, assign) CATransform3D baseCollectionSublayerTransform;
@property (nonatomic, assign) BOOL suspendedForLandscape;
@end

static BOOL PACCIndicatorIsLandscape(void) {
    CGSize size = UIScreen.mainScreen.bounds.size;
    return size.width > size.height;
}

static NSArray<NSString *> *PACCIndicatorIcons(void) {
    static NSArray<NSString *> *icons;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        icons = @[@"heart.fill", @"music.note", @"pawprint.fill"];
    });
    return icons;
}

static UIImage *PACCIndicatorSymbolForPage(NSUInteger index, CGFloat pointSize) {
    NSArray<NSString *> *icons = PACCIndicatorIcons();
    NSString *name = @"circle.fill";      // a plain page: filled dot, as in ControlCenter26
    if (index == 0) name = icons[0];
    else if ((NSInteger)index == PACCMediaPageIndex()) name = icons[1];
    else if ((NSInteger)index == PACCPromoPageIndex()) name = icons[2];
    else {
        // a page of your own: antenna when it holds Connectivity, music note when it holds Music Player
        int kind = PACCPageContentKind(index);
        if (kind == 1) name = @"antenna.radiowaves.left.and.right";
        else if (kind == 2) name = @"music.note";
    }

    // ControlCenter26 draws the music page from its bundled "music" symbol (PrivateSymbols.bundle), with SF "music.note" as fallback
    if ([name isEqualToString:@"music.note"]) {
        UIImage *bundled = PACCBundledSymbol(@"music", UIColor.whiteColor, NO);
        if (bundled) {
            if (!bundled.symbolConfiguration) {
                UIImageSymbolConfiguration *mc = [UIImageSymbolConfiguration configurationWithPointSize:pointSize weight:UIImageSymbolWeightSemibold];
                bundled = [bundled imageByApplyingSymbolConfiguration:mc] ?: bundled;
            }
            return [bundled imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        }
    }
    UIImage *image = PACCBundledSymbol(name, UIColor.whiteColor, NO);
    if (!image) image = [UIImage systemImageNamed:name];
    if (!image && [name isEqualToString:@"network.connected.to.line.below.fill"]) image = [UIImage systemImageNamed:@"antenna.radiowaves.left.and.right"];
    if (!image) return nil;

    if (!image.symbolConfiguration) {
        UIImageSymbolConfiguration *cfg =
            [UIImageSymbolConfiguration configurationWithPointSize:pointSize
                                                            weight:UIImageSymbolWeightSemibold];
        image = [image imageByApplyingSymbolConfiguration:cfg] ?: image;
    }
    return [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

// Page slide without overshoot.
// the page swipe slides without overshoot (damping above critical); the jelly is added on top of it
static void PACCAddSmoothSlide(CALayer *layer, CATransform3D from, CATransform3D to, NSString *key) {
    CASpringAnimation *spring = [CASpringAnimation animationWithKeyPath:@"sublayerTransform.translation.y"];
    spring.fromValue = @(from.m42);
    spring.toValue   = @(to.m42);
    spring.mass = 1.0;
    spring.stiffness = 170.0;
    spring.damping = 28.0;
    spring.initialVelocity = 0.0;
    spring.duration = spring.settlingDuration;
    spring.fillMode = kCAFillModeBackwards;
    [layer addAnimation:spring forKey:key];
}

// the jelly: the page squashes and stretches a little as it lands
static void PACCAddJellyFrom(CALayer *layer, CGFloat startX, CGFloat startY) {
    CAKeyframeAnimation *jy = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale.y"];
    jy.values = @[@(startY), @0.945, @1.032, @0.985, @1.0];
    jy.keyTimes = @[@0.0, @0.28, @0.55, @0.8, @1.0];
    CAKeyframeAnimation *jx = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale.x"];
    jx.values = @[@(startX), @1.03, @0.985, @1.008, @1.0];
    jx.keyTimes = jy.keyTimes;
    CAAnimationGroup *jelly = [CAAnimationGroup animation];
    jelly.animations = @[jy, jx];
    jelly.duration = 0.75;
    jelly.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    [layer addAnimation:jelly forKey:@"PAnimJelly"];
}

static void PACCAddJelly(CALayer *layer, CGFloat endStretch) {
    PACCAddJellyFrom(layer, 1.0 - endStretch * 0.4, 1.0 + endStretch);
}

static void PACCAddBounceSlide(CALayer *layer, CATransform3D from, CATransform3D to, NSString *key) {
    CASpringAnimation *spring = [CASpringAnimation animationWithKeyPath:@"sublayerTransform.translation.y"];
    spring.fromValue = @(from.m42);
    spring.toValue   = @(to.m42);
    spring.mass = 1.0;
    spring.stiffness = 170.0;
    spring.damping = 28.0;          // no overshoot anywhere
    spring.initialVelocity = 0.0;
    spring.duration = spring.settlingDuration;
    spring.fillMode = kCAFillModeBackwards;
    [layer addAnimation:spring forKey:key];
}

@implementation CCAPageIndicator

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;
        self.userInteractionEnabled = YES;
        self.currentPage = 0;
        self.pageCount = PACCBasePageCount() + PACCUserPageCount();
        self.heldScale = 1.0;
        self.heldAlphaFactor = 1.0;
        self.jelloScaleX = 1.0;
        self.jelloScaleY = 1.0;
        self.baseCollectionSublayerTransform = CATransform3DIdentity;

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(scrubPan:)];
        pan.maximumNumberOfTouches = 1;
        pan.cancelsTouchesInView = YES;
        pan.delegate = self;
        [self addGestureRecognizer:pan];
        self.panRecognizer = pan;

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(deviceOrientationChanged:)
                                                     name:UIDeviceOrientationDidChangeNotification
                                                   object:nil];
    }
    return self;
}

- (void)deviceOrientationChanged:(NSNotification *)note {
    __weak CCAPageIndicator *weakSelf = self;
    for (NSNumber *delay in @[@0.05, @0.4, @0.9]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [weakSelf syncLandscapeState]; });
    }
}

- (void)syncLandscapeState {
    BOOL landscape = PACCIndicatorIsLandscape();
    if (landscape == self.suspendedForLandscape) return;
    self.suspendedForLandscape = landscape;

    if (landscape) {
        if (self.panRecognizer.enabled) {
            self.panRecognizer.enabled = NO;
            self.panRecognizer.enabled = YES;
        }
        if (self.currentPage != 0 && self.overlay) {
            if (gExperimentalPagingEnabled) [self experimentalSetCurrentPage:0 forOverlay:self.overlay];
            else                            [self stableSetCurrentPage:0 forOverlay:self.overlay];
        }
        self.userInteractionEnabled = NO;
        self.hidden = YES;
    } else {
        self.hidden = NO;
        self.userInteractionEnabled = YES;
        [self captureCollectionBase];
        [self layoutButtons];
    }
}

- (void)setFrame:(CGRect)frame {
    [super setFrame:frame];
    [self syncLandscapeState];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window) [self installSwipe];
    [self syncLandscapeState];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self syncLandscapeState];
}

- (BOOL)scrubbing {
    return self.scrubbingActive;
}

- (BOOL)respondsToSelector:(SEL)aSelector {
    if ([super respondsToSelector:aSelector]) return YES;
    return NO;
}
- (id)forwardingTargetForSelector:(SEL)aSelector { return nil; }
- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector {
    NSMethodSignature *sig = [super methodSignatureForSelector:aSelector];
    if (!sig) sig = [NSMethodSignature signatureWithObjCTypes:"v@:"];
    return sig;
}
- (void)forwardInvocation:(NSInvocation *)anInvocation { }

- (void)pulseCurrentButton {
    return;     // no bounce on the pager icon either
    if (self.currentPage >= self.subviews.count) return;
    UIView *button = self.subviews[self.currentPage];
    [button.layer removeAnimationForKey:@"PACCIndicatorPulse"];
    CAKeyframeAnimation *pulse = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
    pulse.values = @[@1.0, @1.18, @0.95, @1.0];
    pulse.keyTimes = @[@0.0, @0.35, @0.72, @1.0];
    pulse.duration = 0.26;
    pulse.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    [button.layer addAnimation:pulse forKey:@"PACCIndicatorPulse"];
}

// Apple's pans (the ones that pull Control Center down to close it) must wait for the page swipe: when ours takes
// the touch, theirs fails and nothing drags the panel or the status bar along. On the first page ours never begins
// for a downward drag, so closing works as before.
static NSHashTable<UIGestureRecognizer *> *gPACCBoundPans;

// The panel is pulled down by the overlay's own scroll view (it bounces at the top and Apple turns that into "close"),
// so its pan is the one to hold back too. Control26 gets the same effect by scrolling that view itself.
static NSMutableArray<UIGestureRecognizer *> *gPACCHeldPans;

static NSArray<UIView *> *PACCOverlayScrollers(UIViewController *overlay) {
    NSMutableArray<UIView *> *out = [NSMutableArray array];
    id sv = nil;
    @try { sv = [(id)overlay valueForKey:@"overlayScrollView"]; } @catch (__unused NSException *e) {}
    if ([sv isKindOfClass:UIScrollView.class]) [out addObject:sv];
    UIView *cv = ModuleCollection(overlay).view;
    if ([cv isKindOfClass:UIScrollView.class]) [out addObject:cv];
    for (UIView *v = cv.superview; v && v != overlay.view.superview; v = v.superview) {
        if ([v isKindOfClass:UIScrollView.class] && ![out containsObject:v]) [out addObject:v];
    }
    return out;
}

static void PACCBindOtherPans(UIViewController *overlay, UIGestureRecognizer *ours) {
    UIView *host = overlay.view;
    if (!gPACCBoundPans) gPACCBoundPans = [NSHashTable weakObjectsHashTable];
    NSMutableArray<UIView *> *views = [NSMutableArray array];
    for (UIView *v = host; v; v = v.superview) [views addObject:v];
    for (UIView *v in PACCOverlayScrollers(overlay)) if (![views containsObject:v]) [views addObject:v];
    for (UIView *v in views) {
        NSMutableArray<UIGestureRecognizer *> *grs = [v.gestureRecognizers mutableCopy] ?: [NSMutableArray array];
        if ([v isKindOfClass:UIScrollView.class] && ![grs containsObject:((UIScrollView *)v).panGestureRecognizer]) {
            [grs addObject:((UIScrollView *)v).panGestureRecognizer];
        }
        for (UIGestureRecognizer *gr in grs) {
            if (gr == ours || ![gr isKindOfClass:UIPanGestureRecognizer.class]) continue;
            if ([gPACCBoundPans containsObject:gr]) continue;
            [gPACCBoundPans addObject:gr];
            [gr requireGestureRecognizerToFail:ours];
            PACCCrashLog([NSString stringWithFormat:@"swipe: %@ pan on %@ now waits for the page swipe",
                          NSStringFromClass(gr.class), NSStringFromClass(v.class)]);
        }
    }
}

// if one of them already started pulling, cancel it and put the panel back
__attribute__((unused)) static void PACCHoldScrollPans(UIViewController *overlay, UIGestureRecognizer *ours) {
    gPACCHeldPans = [NSMutableArray array];
    for (UIView *v in PACCOverlayScrollers(overlay)) {
        UIScrollView *sv = (UIScrollView *)v;
        UIGestureRecognizer *p = sv.panGestureRecognizer;
        if (p == ours || !p.enabled) continue;
        p.enabled = NO;
        [gPACCHeldPans addObject:p];
    }
}

static void PACCReleaseScrollPans(void) {
    for (UIGestureRecognizer *p in gPACCHeldPans) p.enabled = YES;
    gPACCHeldPans = nil;
}

static const void *kPACCSwipeKey = &kPACCSwipeKey;
static const void *kPACCSwipeRecKey = &kPACCSwipeRecKey;

// Swipe up on the page area to go to the next page (and down to come back), with the same springy page slide and jelly as scrubbing the pager.
- (void)installSwipe {
    UIView *host = self.overlay.view;
    if (!host) return;
    // The panel's view ignores touches on its empty space (that is how tapping outside closes it), so a page with few
    // controls had nothing under the finger. The recognizer lives on the window instead and sees every touch.
    UIView *target = host;
    UIGestureRecognizer *old = objc_getAssociatedObject(self, kPACCSwipeKey);
    if (old) [old.view removeGestureRecognizer:old];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(swipePan:)];
    pan.maximumNumberOfTouches = 1;
    pan.cancelsTouchesInView = NO;
    pan.delegate = self;
    [target addGestureRecognizer:pan];
    objc_setAssociatedObject(self, kPACCSwipeKey, pan, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, kPACCSwipeRecKey, pan, OBJC_ASSOCIATION_ASSIGN);
}

- (void)swipePan:(UIPanGestureRecognizer *)g {
    UIView *host = self.overlay.view;
    UIViewController *collection = ModuleCollection(self.overlay);
    UIView *cv = collection.view;
    if (!host || !cv || self.pageCount <= 1) return;
    CGFloat span = PageSpan();
    if (span < 1.0) return;
    NSInteger maxPage = (NSInteger)self.pageCount - 1;
    CGFloat ty = [g translationInView:host].y;
    CGFloat vy = [g velocityInView:host].y;

    if (g.state == UIGestureRecognizerStateBegan) {
        self.dragStartPage = self.currentPage;
        self.dragging = YES;
        gPageAnimating = YES;
        gPagerScrubbing = YES;          // keeps the layout pass from snapping the page back to its rest spot
        gPACCRevealAll = YES;
        [cv.layer removeAnimationForKey:@"PAnimPageSlide"];
        [cv.layer removeAnimationForKey:@"PAnimJelly"];
        [PACC.shared syncModuleVisibilityForOverlay:self.overlay animated:NO];
    }
    if (!self.dragging) return;

    CGFloat rest = -(CGFloat)self.dragStartPage * span;
    CGFloat y = rest + ty;
    CGFloat top = 0.0, bottom = -(CGFloat)maxPage * span;
    if (y > top) y = top + (y - top) * 0.15;                    // rubber band at the ends
    else if (y < bottom) y = bottom + (y - bottom) * 0.15;

    if (g.state == UIGestureRecognizerStateBegan || g.state == UIGestureRecognizerStateChanged) {
        // keep the panel's own scroll view at rest, so Apple's pull-down-to-close never gets a drag to work with
        for (UIView *sv in PACCOverlayScrollers(self.overlay)) {
            if ([sv isKindOfClass:UIScrollView.class]) {
                UIScrollView *u = (UIScrollView *)sv;
                CGFloat rest0 = -u.adjustedContentInset.top;
                if (u.contentOffset.y != rest0 && u.contentOffset.y < 0.0) u.contentOffset = CGPointMake(u.contentOffset.x, rest0);
            }
        }
        CGFloat stretch = MIN(0.07, fabs(vy) / 9000.0);        // the page stretches a little while it is dragged fast
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        CATransform3D sub = cv.layer.sublayerTransform;
        sub.m41 = 0.0; sub.m42 = y; sub.m43 = 0.0;
        cv.layer.sublayerTransform = sub;
        cv.layer.transform = CATransform3DMakeScale(1.0 - stretch * 0.4, 1.0 + stretch, 1.0);
        [CATransaction commit];
        return;
    }

    // finger lifted: pick the page, then let it spring in with a jelly wobble
    NSInteger target = (NSInteger)self.dragStartPage;
    // a cancelled touch (the system took it over, a module button was under the finger) counts like a lifted finger
    if (g.state == UIGestureRecognizerStateEnded || g.state == UIGestureRecognizerStateCancelled) {
        if (ty < -span * 0.12 || vy < -350.0) target += 1;
        else if (ty > span * 0.12 || vy > 350.0) target -= 1;
    }
    // the system often cancels a slow swipe right after it started (translation already reset to 0): go by direction
    if (g.state == UIGestureRecognizerStateCancelled && target == (NSInteger)self.dragStartPage) {
        if (vy < -120.0) target += 1;
        else if (vy > 120.0) target -= 1;
    }
    target = MIN(maxPage, MAX(0, target));
    PACCCrashLog([NSString stringWithFormat:@"swipe end state %ld ty %.0f vy %.0f from %ld to %ld", (long)g.state,
                  ty, vy, (long)self.dragStartPage, (long)target]);

    CGFloat endStretch = MIN(0.045, fabs(vy) / 12000.0);
    CALayer *pres = (CALayer *)cv.layer.presentationLayer;
    CATransform3D fromSub = pres ? pres.sublayerTransform : cv.layer.sublayerTransform;
    CATransform3D toSub = cv.layer.sublayerTransform;
    toSub.m41 = 0.0; toSub.m42 = -(CGFloat)target * span; toSub.m43 = 0.0;

    self.dragging = NO;
    PACCReleaseScrollPans();
    gPACCRevealAll = NO;
    gPagerScrubbing = NO;
    self.currentPage = (NSUInteger)target;
    gCurrentPage = target;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    cv.layer.sublayerTransform = toSub;
    cv.layer.transform = CATransform3DIdentity;
    [CATransaction commit];

    PACCAddSmoothSlide(cv.layer, fromSub, toSub, @"PAnimPageSlide");

    PACCAddJelly(cv.layer, endStretch);

    [PACC.shared applyHeaderMaterialHidden:NO forOverlay:self.overlay];
    [PACC.shared adjustStatusBarForOverlay:self.overlay];
    [PACC.shared syncModuleVisibilityForOverlay:self.overlay animated:YES];
    [self layoutButtons];
    [self pulseCurrentButton];
    Haptic();

    NSUInteger token = ++self.animationToken;
    __weak CCAPageIndicator *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.9 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        CCAPageIndicator *strong = weakSelf;
        if (!strong || strong.animationToken != token) return;
        gPageAnimating = NO;
        [strong captureCollectionBase];
    });
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gr shouldReceiveTouch:(UITouch *)touch {
    if (gr == objc_getAssociatedObject(self, kPACCSwipeRecKey) && self.overlay.view) {
        UIView *host = self.overlay.view;
        PACCBindOtherPans(self.overlay, gr);
        // Only the middle band pages (like ControlCenter26): the top strip with the status bar and the bottom edge stay Apple's, so closing still works there.
        CGPoint p = [touch locationInView:self.overlay.view];
        if (p.y < 60.0 || p.y > CGRectGetHeight(self.overlay.view.bounds) - 110.0) return NO;
    }
    return YES;
}

// As in ControlCenter26: every other pan around the panel (Apple's scroll and close pans) waits until the page swipe has decided.
// Asking the delegate does this from the very first touch, which binding them afterwards could not.
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gr shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)other {
    if (gr != objc_getAssociatedObject(self, kPACCSwipeRecKey)) return NO;
    if (![other isKindOfClass:UIPanGestureRecognizer.class] || other == gr) return NO;
    UIView *host = self.overlay.view, *ov = other.view;
    if (!host || !ov) return NO;
    return [host isDescendantOfView:ov] || [ov isDescendantOfView:host];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)a shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)b {
    return NO;      // exclusive, as in ControlCenter26: Apple's pans wait for the page swipe
}

- (void)setOverlay:(UIViewController *)overlay {
    _overlay = overlay;
    [self installSwipe];
    [self captureCollectionBase];
    [self rebuildButtons];
    [self syncLandscapeState];
}

- (void)captureCollectionBase {
    UIViewController *collection = ModuleCollection(self.overlay);
    if (!collection.view) return;
    if (self.transitionActive) return;

    CATransform3D current = collection.view.layer.sublayerTransform;
    CGFloat span = PageSpan();
    current.m42 += (CGFloat)gCurrentPage * span;
    current.m41 = 0.0;
    current.m43 = 0.0;

    self.baseCollectionSublayerTransform = current;
}

- (void)setPageCount:(NSUInteger)pageCount {
    if (pageCount == 0) pageCount = 1;
    if (_pageCount == pageCount && self.subviews.count == pageCount) return;
    _pageCount = pageCount;
    [self rebuildButtons];
}

- (void)rebuildButtons {
    while (self.subviews.count > self.pageCount) [self.subviews.lastObject removeFromSuperview];
    while (self.subviews.count < self.pageCount) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.tintColor = UIColor.whiteColor;
        NSUInteger page = self.subviews.count;
        objc_setAssociatedObject(button, @selector(tapped:), @(page), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [button addTarget:self action:@selector(buttonTouchDown:) forControlEvents:UIControlEventTouchDown];
        [button addTarget:self action:@selector(buttonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:button];
    }
    [self layoutButtons];
}

- (void)layoutButtons {
    [self layoutIndicatorsWithScrubbing:NO touchY:0.0];
}

- (void)layoutIndicatorsWithScrubbing:(BOOL)scrubbing touchY:(CGFloat)touchY {
    if (self.pageCount == 0) return;
    CGFloat overlayH = self.overlay ? CGRectGetHeight(self.overlay.view.bounds) : CGRectGetHeight(UIScreen.mainScreen.bounds);

    CGFloat step = scrubbing ? 58.0 : 39.0;
    CGFloat hostH = step * (CGFloat)self.pageCount;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    if (scrubbing) {
        CGFloat rightEdge = CGRectGetMaxX(self.restHostFrame);
        if (rightEdge <= 0.0) rightEdge = CGRectGetMaxX(self.frame);
        CGFloat hostX = rightEdge - 58.0;
        CGFloat hostY = floor((overlayH - hostH) * 0.5);
        self.frame = CGRectMake(hostX, hostY, 58.0, hostH);
    }

    NSArray *buttons = self.subviews;
    NSUInteger count = buttons.count;
    NSUInteger index;
    for (index = 0; index < count; index++) {
        UIView *button = buttons[index];
        BOOL selected = ((NSInteger)index == (NSInteger)self.currentPage);

        if (scrubbing) {
            CGFloat centerY = ((CGFloat)index + 0.5) * step;
            CGFloat proximity = 1.0 - fabs(touchY - centerY) / 78.0;
            if (proximity < 0.0) proximity = 0.0;
            if (proximity > 1.0) proximity = 1.0;
            CGFloat scale = 1.18 + 1.68 * proximity + (selected ? 0.18 : 0.0);
            CGFloat rawSize = (index == 0 ? 16.0 : 12.0) * scale;
            CGFloat pointSize = rawSize < 38.0 ? rawSize : 38.0;
            CGFloat slideOut = 24.0 * proximity;
            CGFloat alpha = MIN(1.0, (selected ? 0.86 : 0.42) + 0.36 * proximity);   // same dim grey as at rest
            CGFloat tintWhite = 1.0;

            button.bounds = CGRectMake(0.0, 0.0, 58.0, step);
            button.center = CGPointMake(29.0 - slideOut, centerY);
            button.transform = CGAffineTransformIdentity;
            button.alpha = alpha;
            button.tintColor = [UIColor colorWithWhite:tintWhite alpha:1.0];

            UIButton *b = (UIButton *)button;
            UIImage *image = PACCIndicatorSymbolForPage(index, pointSize);
            if (image) [b setImage:image forState:UIControlStateNormal];
        } else {
            CGFloat y = (CGFloat)index * step;
            button.frame = CGRectMake(0.0, y, 42.0, step);
            button.transform = CGAffineTransformIdentity;

            UIButton *b = (UIButton *)button;
            CGFloat pointSize = (index == 0) ? 16.0 : 12.0;
            UIImage *image = PACCIndicatorSymbolForPage(index, pointSize);
            if (image) [b setImage:image forState:UIControlStateNormal];
            button.alpha = selected ? 1.0 : 0.42;       // selected white, the others a dim grey
            button.tintColor = UIColor.whiteColor;
        }
    }

    [CATransaction commit];
}

- (void)applyPageTransform {
    if (self.suspendedForLandscape) return;
    UIViewController *collection = ModuleCollection(self.overlay);
    if (!collection.view) return;

    CGFloat span = PageSpan();
    CGFloat pageOffset = -(CGFloat)self.currentPage * span + self.interactiveTranslation;

    CATransform3D target = CATransform3DTranslate(self.baseCollectionSublayerTransform, 0.0, pageOffset, 0.0);

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    collection.view.layer.sublayerTransform = target;
    if (self.scrubbingActive) {
        collection.view.layer.transform = CATransform3DMakeScale(self.jelloScaleX, self.jelloScaleY, 1.0);
        collection.view.alpha = self.heldAlphaFactor;
    } else {
        collection.view.layer.transform = CATransform3DIdentity;
        collection.view.alpha = 1.0;
    }
    [CATransaction commit];
}

- (void)beginInteractiveTransitionWithStartPage:(NSUInteger)startPage {
    if (self.suspendedForLandscape) return;
    if (!self.overlay) return;
    UIViewController *collection = ModuleCollection(self.overlay);
    if (!collection.view) return;

    self.restHostFrame = self.frame;

    self.transitionActive = YES;
    self.scrubbingActive = YES;
    self.dragging = NO;
    self.interactiveStartPage = MIN(startPage, self.pageCount - 1);
    self.currentPage = self.interactiveStartPage;
    gCurrentPage = (NSInteger)self.interactiveStartPage;
    self.interactiveProgress = (CGFloat)self.interactiveStartPage;
    self.interactiveTranslation = 0.0;
    self.interactiveBeganTime = CACurrentMediaTime();
    self.heldScale = 1.0;
    self.heldAlphaFactor = 1.0;
    self.viscousProgress = (CGFloat)self.interactiveStartPage;
    self.previousRawProgress = (CGFloat)self.interactiveStartPage;
    self.filteredVelocity = 0.0;
    self.jelloScaleX = 1.0;
    self.jelloScaleY = 1.0;
    self.lastSampleTime = CACurrentMediaTime();

    self.savedCollectionView = collection.view;

    CALayer *pres = (CALayer *)collection.view.layer.presentationLayer;
    if (pres) {
        collection.view.layer.sublayerTransform = pres.sublayerTransform;
        collection.view.layer.transform = pres.transform;
    }
    [collection.view.layer removeAllAnimations];
}

- (void)updateInteractiveTransitionWithProgress:(CGFloat)progress touchY:(CGFloat)touchY {
    if (!self.overlay || !self.transitionActive) return;

    UIViewController *collection = ModuleCollection(self.overlay);
    if (!collection.view) return;

    CGFloat maxProgress = (CGFloat)self.pageCount - 1.0;

    CGFloat physicsProgress = progress;
    if (progress < 0.0) physicsProgress = -log1p(-progress);
    else if (progress > maxProgress) physicsProgress = maxProgress + log1p(progress - maxProgress);

    NSUInteger previousCandidate = self.currentPage;

    CFTimeInterval now = CACurrentMediaTime();
    CGFloat dt = self.lastSampleTime > 0.0 ? (CGFloat)(now - self.lastSampleTime) : (1.0 / 60.0);
    dt = MIN(0.050, MAX(1.0 / 120.0, dt));

    CGFloat rawVelocity = (physicsProgress - self.previousRawProgress) / dt;
    rawVelocity = MIN(8.0, MAX(-8.0, rawVelocity));
    CGFloat velocityResponse = 1.0 - exp(-dt * 11.0);
    self.filteredVelocity += (rawVelocity - self.filteredVelocity) * velocityResponse;

    CGFloat dragResponse = 1.0 - exp(-dt * 9.0);
    self.viscousProgress += (physicsProgress - self.viscousProgress) * dragResponse;

    CGFloat visualProgress = self.viscousProgress;
    NSUInteger candidate = (NSUInteger)llround(MIN(maxProgress, MAX(0.0, visualProgress)));
    BOOL changedPage = (candidate != previousCandidate);
    if (changedPage) Haptic();
    CGFloat pageTension = physicsProgress - visualProgress;

    self.previousRawProgress = physicsProgress;
    self.lastSampleTime = now;
    self.interactiveProgress = MIN(maxProgress, MAX(0.0, progress));
    self.currentPage = candidate;
    gCurrentPage = (NSInteger)candidate;

    CGFloat overlayHeight = CGRectGetHeight(self.overlay.view.bounds);
    CGFloat scrubHostHeight = 58.0 * self.pageCount;
    CGFloat scrubHostMinY = floor((overlayHeight - scrubHostHeight) * 0.5);
    CGFloat fingerY = scrubHostMinY + touchY;

    CGFloat translationTarget = 0.0;
    BOOL endpointPull = NO;
    if (progress < 0.0) {
        CGFloat firstIconY = scrubHostMinY + 58.0 * 0.5;
        CGFloat upperLimitY = overlayHeight * 0.10;
        CGFloat pull = MIN(1.0, MAX(0.0, (firstIconY - fingerY) / MAX(1.0, firstIconY - upperLimitY)));
        CGFloat eased = 1.0 - pow(1.0 - pull, 1.35);
        translationTarget = -MIN(100.0, overlayHeight * 0.12) * eased;
        endpointPull = YES;
    } else if (progress > maxProgress) {
        CGFloat lastIconY = scrubHostMinY + ((CGFloat)self.pageCount - 0.5) * 58.0;
        CGFloat lowerLimitY = overlayHeight * 0.90;
        CGFloat pull = MIN(1.0, MAX(0.0, (fingerY - lastIconY) / MAX(1.0, lowerLimitY - lastIconY)));
        CGFloat eased = 1.0 - pow(1.0 - pull, 1.35);
        translationTarget = MIN(100.0, overlayHeight * 0.12) * eased;
        endpointPull = YES;
    } else {
        translationTarget = (visualProgress - (CGFloat)candidate) * 22.0;
    }

    if (endpointPull) {
        self.interactiveTranslation += (translationTarget - self.interactiveTranslation) * dragResponse;
    } else {
        self.interactiveTranslation = translationTarget;
    }

    CGFloat entrance = self.interactiveBeganTime > 0.0
        ? MIN(1.0, MAX(0.0, (CACurrentMediaTime() - self.interactiveBeganTime) / 0.26)) : 1.0;
    entrance = entrance * entrance * entrance * (entrance * (entrance * 6.0 - 15.0) + 10.0);
    self.heldScale = 1.0 - 0.30 * entrance;
    self.heldAlphaFactor = 1.0 - 0.30 * entrance;

    CGFloat jelloInput = self.filteredVelocity * 0.0030 + pageTension * 0.022;
    CGFloat jello = MIN(0.025, MAX(-0.025, jelloInput)) * entrance;
    self.jelloScaleX = (1.0 - jello * 0.42) * self.heldScale;
    self.jelloScaleY = (1.0 + jello) * self.heldScale;

    [self applyPageTransform];
    if (changedPage) {
        [PACC.shared syncModuleVisibilityForOverlay:self.overlay animated:YES];
        CCAMediaPlayerView *player = (CCAMediaPlayerView *)[collection.view viewWithTag:kMediaPlayerTag];
        if (player) {
            CGFloat targetAlpha = ((NSInteger)candidate == PACCMediaPageIndex()) ? 1.0 : 0.0;
            if (fabs(player.alpha - targetAlpha) > 0.01) {
                [UIView animateWithDuration:0.15 animations:^{ player.alpha = targetAlpha; }];
            }
        }

        CCAPromoPageView *promo = (CCAPromoPageView *)[collection.view viewWithTag:kPromoPageTag];
        if (promo && (NSInteger)candidate == PACCPromoPageIndex()) [promo refreshFact];
    }

    [self layoutIndicatorsWithScrubbing:YES touchY:touchY];
}

- (void)finishInteractiveTransitionWithTargetPage:(NSUInteger)targetPage {
    if (!self.overlay || !self.transitionActive) return;

    UIViewController *collection = ModuleCollection(self.overlay);
    if (!collection.view) return;

    NSUInteger target = MIN(targetPage, self.pageCount - 1);
    self.interactiveBeganTime = 0.0;
    self.scrubbingActive = NO;
    self.currentPage = target;
    gCurrentPage = (NSInteger)target;
    self.interactiveTranslation = 0.0;

    [PACC.shared syncModuleVisibilityForOverlay:self.overlay animated:YES];
    [PACC.shared applyHeaderMaterialHidden:((NSInteger)target == PACCMediaPageIndex()) forOverlay:self.overlay];
    [PACC.shared adjustStatusBarForOverlay:self.overlay];

    CCAMediaPlayerView *player = (CCAMediaPlayerView *)[collection.view viewWithTag:kMediaPlayerTag];
    if (player) {
        player.alpha = ((NSInteger)target == PACCMediaPageIndex()) ? 1.0 : 0.0;
        player.transform = CGAffineTransformIdentity;
    }

    CCAPromoPageView *promo = (CCAPromoPageView *)[collection.view viewWithTag:kPromoPageTag];
    if (promo && (NSInteger)target == PACCPromoPageIndex()) [promo refreshFact];

    CGFloat span = PageSpan();
    CATransform3D toSub = CATransform3DTranslate(self.baseCollectionSublayerTransform, 0.0, -(CGFloat)target * span, 0.0);

    CALayer *pres = (CALayer *)collection.view.layer.presentationLayer;
    CATransform3D fromSub = pres ? pres.sublayerTransform : collection.view.layer.sublayerTransform;
    CATransform3D fromTrans = pres ? pres.transform : collection.view.layer.transform;
    CGFloat fromAlpha = pres ? pres.opacity : collection.view.alpha;

    [collection.view.layer removeAnimationForKey:@"PAnimPageSlide"];
    [collection.view.layer removeAnimationForKey:@"PAnimScrubTransform"];
    [collection.view.layer removeAnimationForKey:@"PAnimScrubOpacity"];

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    collection.view.layer.sublayerTransform = toSub;
    collection.view.layer.transform = CATransform3DIdentity;
    collection.view.alpha = 1.0;
    [CATransaction commit];

    CAMediaTimingFunction *curve = [CAMediaTimingFunction functionWithControlPoints:0.18 :0.88 :0.20 :1.0];

    PACCAddBounceSlide(collection.view.layer, fromSub, toSub, @"PAnimPageSlide");

    // letting go of the pager: from the held size straight into the jelly (no shrink and no extra bounce)
    CGFloat heldX = fromTrans.m11, heldY = fromTrans.m22;
    if (fabs(heldX - 1.0) < 0.004 && fabs(heldY - 1.0) < 0.004) { heldX = 0.986; heldY = 1.035; }
    [collection.view.layer removeAnimationForKey:@"PAnimJelly"];
    PACCAddJellyFrom(collection.view.layer, heldX, heldY);

    CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
    fade.fromValue = @(fromAlpha);
    fade.toValue = @1.0;
    fade.duration = 0.30;
    fade.timingFunction = curve;
    [collection.view.layer addAnimation:fade forKey:@"PAnimScrubOpacity"];

    [PACC.shared layoutPageIndicatorForOverlay:self.overlay];

    NSUInteger token = ++self.animationToken;
    __weak CCAPageIndicator *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.32 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        CCAPageIndicator *strongSelf = weakSelf;
        if (!strongSelf) return;
        if (strongSelf.animationToken != token) return;

        strongSelf.transitionActive = NO;
        strongSelf.scrubbingActive = NO;
        strongSelf.dragging = NO;
        strongSelf.savedCollectionView = nil;
        strongSelf.heldScale = 1.0;
        strongSelf.heldAlphaFactor = 1.0;
        strongSelf.jelloScaleX = 1.0;
        strongSelf.jelloScaleY = 1.0;
        strongSelf.viscousProgress = (CGFloat)target;
        strongSelf.filteredVelocity = 0.0;
        strongSelf.lastSampleTime = 0.0;

        gCurrentPage = (NSInteger)target;
        [strongSelf applyPageTransform];
        [strongSelf captureCollectionBase];
        [PACC.shared syncModuleVisibilityForOverlay:strongSelf.overlay animated:NO];
        [PACC.shared layoutPageIndicatorForOverlay:strongSelf.overlay];

        [strongSelf pulseCurrentButton];
    });
}

- (void)scrubPan:(UIPanGestureRecognizer *)gesture {
    if (!gExperimentalPagingEnabled) return;
    if (!self.overlay || !gPagingEnabled || self.pageCount <= 1) return;
    UIViewController *collection = ModuleCollection(self.overlay);
    if (!collection.view) return;

    CGFloat overlayH = CGRectGetHeight(self.overlay.view.bounds);
    CGFloat scrubStep = 58.0;
    CGFloat scrubHostH = scrubStep * (CGFloat)self.pageCount;
    CGFloat scrubHostMinY = floor((overlayH - scrubHostH) * 0.5);

    CGPoint location = [gesture locationInView:self.superview];
    CGFloat touchY = location.y - scrubHostMinY;
    CGFloat progress = (touchY - scrubStep * 0.5) / scrubStep;
    CGFloat maxProgress = (CGFloat)self.pageCount - 1.0;
    progress = MIN(maxProgress + 0.9, MAX(-0.9, progress));

    if (gesture.state == UIGestureRecognizerStateBegan) {
        self.dragging = YES;
        self.dragStartPage = self.currentPage;
        if (!self.transitionActive) {
            [self beginInteractiveTransitionWithStartPage:self.currentPage];
        }
        [self updateInteractiveTransitionWithProgress:progress touchY:touchY];

    } else if (gesture.state == UIGestureRecognizerStateChanged) {
        if (self.transitionActive) {
            [self updateInteractiveTransitionWithProgress:progress touchY:touchY];
        }

    } else if (gesture.state == UIGestureRecognizerStateEnded ||
               gesture.state == UIGestureRecognizerStateCancelled ||
               gesture.state == UIGestureRecognizerStateFailed) {
        if (self.transitionActive && self.scrubbingActive) {
            NSUInteger target;
            if (gesture.state == UIGestureRecognizerStateEnded) {
                target = (NSUInteger)llround(MIN(maxProgress, MAX(0.0, progress)));
            } else {
                target = self.dragStartPage;
            }
            [self finishInteractiveTransitionWithTargetPage:target];
        }
    }
}

- (void)buttonTouchDown:(UIButton *)sender {
    if (!gExperimentalPagingEnabled) return;
    if (!self.overlay || !gPagingEnabled || self.pageCount <= 1) return;
    UIViewController *collection = ModuleCollection(self.overlay);
    if (!collection.view) return;

    NSNumber *page = objc_getAssociatedObject(sender, @selector(tapped:));
    if (!page) return;
    NSUInteger targetPage = page.unsignedIntegerValue;

    if (self.transitionActive) {
        self.animationToken++;
        self.transitionActive = NO;
        self.scrubbingActive = NO;
    }

    [self beginInteractiveTransitionWithStartPage:self.currentPage];

    CGFloat touchY = ((CGFloat)targetPage + 0.5) * 58.0;
    [self updateInteractiveTransitionWithProgress:(CGFloat)targetPage touchY:touchY];
}

- (void)buttonTapped:(UIButton *)sender {
    if (!self.overlay || !gPagingEnabled) return;
    if (self.dragging) return;

    NSNumber *page = objc_getAssociatedObject(sender, @selector(tapped:));
    if (!page) return;
    NSUInteger targetPage = page.unsignedIntegerValue;

    if (self.transitionActive) {
        Haptic();
        [self finishInteractiveTransitionWithTargetPage:targetPage];
        return;
    }

    if (targetPage == self.currentPage) return;
    Haptic();
    [self setCurrentPage:targetPage forOverlay:self.overlay];
}

- (void)setCurrentPage:(NSUInteger)page forOverlay:(UIViewController *)overlay {
    if (self.suspendedForLandscape) return;
    if (gExperimentalPagingEnabled) {
        [self experimentalSetCurrentPage:page forOverlay:overlay];
    } else {
        [self stableSetCurrentPage:page forOverlay:overlay];
    }
}

- (void)stableSetCurrentPage:(NSUInteger)page forOverlay:(UIViewController *)overlay {
    if (page >= self.pageCount) return;
    if (page == self.currentPage) return;

    self.currentPage = page;
    gCurrentPage = (NSInteger)page;

    [PACC.shared applyHeaderMaterialHidden:((NSInteger)page == PACCMediaPageIndex()) forOverlay:overlay];
    [PACC.shared adjustStatusBarForOverlay:overlay];

    UIViewController *collection = ModuleCollection(overlay);
    if (!collection.view) return;
    CGFloat span = PageSpan();

    CCAMediaPlayerView *player = (CCAMediaPlayerView *)[collection.view viewWithTag:kMediaPlayerTag];
    if (player) {
        if ((NSInteger)page == PACCMediaPageIndex()) [player fadeIn];
        else [player fadeOut];
    }

    CCAPromoPageView *promo = (CCAPromoPageView *)[collection.view viewWithTag:kPromoPageTag];
    if (promo && (NSInteger)page == PACCPromoPageIndex()) [promo refreshFact];

    [PACC.shared syncModuleVisibilityForOverlay:overlay animated:YES];

    CATransform3D target = collection.view.layer.sublayerTransform;
    target.m41 = 0.0;
    target.m42 = -(CGFloat)page * span;
    target.m43 = 0.0;

    [collection.view.layer removeAnimationForKey:@"PAnimJelly"];
    PACCAddJelly(collection.view.layer, 0.035);
    gPageAnimating = YES;
    [UIView animateWithDuration:0.8 delay:0.0 usingSpringWithDamping:1.0 initialSpringVelocity:0.0
                        options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
        collection.view.layer.sublayerTransform = target;
    } completion:^(BOOL finished) {
        gPageAnimating = NO;
    }];

    [self layoutButtons];

    [self pulseCurrentButton];
}

- (void)experimentalSetCurrentPage:(NSUInteger)page forOverlay:(UIViewController *)overlay {
    if (page >= self.pageCount) return;
    if (self.transitionActive || self.scrubbingActive) return;
    if (page == self.currentPage) return;

    self.currentPage = page;
    gCurrentPage = (NSInteger)page;

    [PACC.shared applyHeaderMaterialHidden:((NSInteger)page == PACCMediaPageIndex()) forOverlay:overlay];
    [PACC.shared adjustStatusBarForOverlay:overlay];

    UIViewController *collection = ModuleCollection(overlay);
    if (!collection.view) return;
    CGFloat span = PageSpan();

    CATransform3D toSub = CATransform3DTranslate(self.baseCollectionSublayerTransform, 0.0, -(CGFloat)page * span, 0.0);
    CALayer *pres = (CALayer *)collection.view.layer.presentationLayer;
    CATransform3D fromSub = pres ? pres.sublayerTransform : collection.view.layer.sublayerTransform;

    [collection.view.layer removeAnimationForKey:@"PAnimPageSlide"];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    collection.view.layer.sublayerTransform = toSub;
    [CATransaction commit];

    PACCAddBounceSlide(collection.view.layer, fromSub, toSub, @"PAnimPageSlide");
    [collection.view.layer removeAnimationForKey:@"PAnimJelly"];
    PACCAddJelly(collection.view.layer, 0.035);

    CCAMediaPlayerView *player = (CCAMediaPlayerView *)[collection.view viewWithTag:kMediaPlayerTag];
    if (player) {
        player.alpha = ((NSInteger)page == PACCMediaPageIndex()) ? 1.0 : 0.0;
        player.transform = CGAffineTransformIdentity;
    }

    CCAPromoPageView *promo = (CCAPromoPageView *)[collection.view viewWithTag:kPromoPageTag];
    if (promo && (NSInteger)page == PACCPromoPageIndex()) [promo refreshFact];

    [PACC.shared syncModuleVisibilityForOverlay:overlay animated:YES];
    [self layoutButtons];

    [self pulseCurrentButton];
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (self.suspendedForLandscape) return NO;
    if (gestureRecognizer == objc_getAssociatedObject(self, kPACCSwipeRecKey)) {
        UIView *host = self.overlay.view;
        UIPanGestureRecognizer *pan = (UIPanGestureRecognizer *)gestureRecognizer;
        CGPoint v = host ? [pan velocityInView:host] : CGPointZero;
        const char *why = NULL;
        if (!host || !gPagingEnabled || self.pageCount <= 1 || gEditModeActive || self.transitionActive) why = "state";
        else if (PACCIndicatorIsLandscape()) why = "landscape";
        else if (fabs(v.y) < fabs(v.x) * 1.4) why = "not vertical";
        else if (v.y < 0.0 && self.currentPage + 1 >= self.pageCount) why = "last page";
        else if (v.y >= 0.0 && self.currentPage == 0) why = "first page (close)";
        if (!why) {
            UIView *hit = [host hitTest:[pan locationInView:host] withEvent:nil];
            for (UIView *s = hit; s && s != host; s = s.superview) {
                if ([NSStringFromClass(s.class) containsString:@"Slider"]) { why = "slider"; break; }
            }
        }
        PACCCrashLog([NSString stringWithFormat:@"swipe begin page %ld/%lu vy %.0f: %s", (long)self.currentPage,
                      (unsigned long)self.pageCount, v.y, why ?: "yes"]);
        return why == NULL;
    }
    if (!gExperimentalPagingEnabled) return NO;
    if (gestureRecognizer == self.panRecognizer) {
        if (!gPagingEnabled || self.pageCount <= 1) return NO;
        UIPanGestureRecognizer *pan = (UIPanGestureRecognizer *)gestureRecognizer;
        CGPoint velocity = [pan velocityInView:self];
        return fabs(velocity.y) > fabs(velocity.x);
    }
    return YES;
}

@end