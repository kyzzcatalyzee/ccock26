#import "PACC.h"

@implementation CCAQuickAccessHost
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

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.hidden || self.alpha <= 0.05 || !self.userInteractionEnabled) return nil;
    for (UIView *sub in self.subviews.reverseObjectEnumerator) {
        if (sub.hidden || sub.alpha <= 0.05 || !sub.userInteractionEnabled) continue;
        CGPoint p = [self convertPoint:point toView:sub];
        UIView *hit = [sub hitTest:p withEvent:event];
        if (hit) return hit;
    }
    return nil;
}
@end

static NSArray<NSString *> *PACCDogFacts(void) {
    static NSArray<NSString *> *facts;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        facts = @[
            @"dogs have about 1,700 taste buds while humans have around 9,000.",
            @"a dog's nose print is unique, just like a human fingerprint.",
            @"dogs can smell roughly 100,000 times better than humans can.",
            @"the average dog can learn around 165 words.",
            @"dogs dream just like humans do, mostly about their owners.",
            @"a dog's hearing is about four times sharper than a human's.",
            @"basenjis are the only breed of dog that cannot bark.",
            @"dogs sweat mainly through their paws.",
            @"a greyhound can run up to 45 miles per hour.",
            @"puppies are born deaf, blind and with no teeth.",
            @"dogs have three eyelids, and the third one keeps the eye moist.",
            @"dogs curl up to sleep to protect their vital organs.",
            @"the bond between dogs and humans goes back 15,000 years.",
            @"a wagging tail to the right usually means a dog is happy.",
            @"dogs can see in the dark far better than humans can.",
            @"the creator of this tweak is a golden retriever dog, no one will believe you.",
            @"did you know that"
        ];
    });
    return facts;
}

@interface CCAPromoPageView ()
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *factLabel;
@end

@implementation CCAPromoPageView

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

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;
        self.userInteractionEnabled = NO;
        self.clipsToBounds = YES;

        UILabel *title = [UILabel new];
        title.text = @"made by pawxed";
        title.textColor = UIColor.whiteColor;
        title.textAlignment = NSTextAlignmentCenter;
        title.numberOfLines = 1;
        title.adjustsFontSizeToFitWidth = YES;
        title.minimumScaleFactor = 0.6;
        [self addSubview:title];
        self.titleLabel = title;

        UILabel *fact = [UILabel new];
        fact.textColor = [UIColor colorWithWhite:1.0 alpha:0.62];
        fact.textAlignment = NSTextAlignmentCenter;
        fact.numberOfLines = 0;
        fact.lineBreakMode = NSLineBreakByWordWrapping;
        [self addSubview:fact];
        self.factLabel = fact;

        [self refreshFact];
    }
    return self;
}

- (void)refreshFact {
    NSArray<NSString *> *facts = PACCDogFacts();
    if (!facts.count) return;
    NSUInteger index = arc4random_uniform((uint32_t)facts.count);
    if (facts.count > 1 && [facts[index] isEqualToString:self.factLabel.text]) {
        index = (index + 1) % facts.count;
    }
    self.factLabel.text = facts[index];
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = CGRectGetWidth(self.bounds);
    CGFloat h = CGRectGetHeight(self.bounds);
    if (w < 1.0 || h < 1.0) return;

    CGFloat sidePad = 28.0;
    CGFloat contentW = w - sidePad * 2.0;

    self.titleLabel.font = [UIFont systemFontOfSize:26.0 weight:UIFontWeightBold];
    CGSize titleFit = [self.titleLabel sizeThatFits:CGSizeMake(contentW, 60.0)];
    titleFit.width  = MIN(contentW, ceil(titleFit.width));
    titleFit.height = ceil(titleFit.height);

    self.factLabel.font = [UIFont systemFontOfSize:14.5 weight:UIFontWeightRegular];
    CGFloat factW = contentW * 0.92;
    CGSize factFit = [self.factLabel sizeThatFits:CGSizeMake(factW, 260.0)];
    factFit.width  = MIN(factW, ceil(factFit.width));
    factFit.height = ceil(factFit.height);

    CGFloat gap = 10.0;
    CGFloat total = titleFit.height + gap + factFit.height;
    CGFloat y = floor((h - total) * 0.5);
    if (y < 4.0) y = 4.0;

    self.titleLabel.frame = CGRectMake(floor((w - titleFit.width) * 0.5), y,
                                       titleFit.width, titleFit.height);
    y += titleFit.height + gap;
    self.factLabel.frame = CGRectMake(floor((w - factFit.width) * 0.5), y,
                                      factFit.width, factFit.height);
}

@end

@implementation PACC

+ (instancetype)shared {
    static PACC *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [self new]; });
    return shared;
}

- (CGFloat)topInsetForOverlay:(UIViewController *)overlay {
    CGFloat safeTop = overlay.view.window.safeAreaInsets.top;
    if (safeTop < 1.0) safeTop = overlay.view.safeAreaInsets.top;
    return MAX(8.0, safeTop - 6.0);
}

- (UIButton *)makeRoundButtonWithSymbol:(NSString *)symbolName tag:(NSInteger)tag {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.tag = tag;
    button.tintColor = UIColor.whiteColor;
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightMedium];
    UIImage *image = [UIImage systemImageNamed:symbolName withConfiguration:config];
    [button setImage:image forState:UIControlStateNormal];
    button.imageView.contentMode = UIViewContentModeCenter;
    return button;
}

- (void)installOnOverlay:(UIViewController *)overlay {
    if (!gEnabled || !overlay.view) return;
    [self updateQuickAccessButtonsForOverlay:overlay];
    [self installPageIndicatorOnOverlay:overlay];
    [self syncModuleVisibilityForOverlay:overlay];
    [self applyHeaderMaterialHidden:(gCurrentPage == PACCMediaPageIndex()) forOverlay:overlay];
    [self adjustStatusBarForOverlay:overlay];

    UIViewController *collection = ModuleCollection(overlay);
    if ([collection.view isKindOfClass:UIScrollView.class]) {
        [self installPromoPageOnCollectionView:(UIScrollView *)collection.view];
    }
}

- (void)syncModuleVisibilityForOverlay:(UIViewController *)overlay {
    [self syncModuleVisibilityForOverlay:overlay animated:NO];
}

BOOL gPACCRevealAll = NO;

- (void)syncModuleVisibilityForOverlay:(UIViewController *)overlay animated:(BOOL)animated {
    PACCCrumb("syncModuleVisibility");
    PACCSyncClones(overlay, animated);
    BOOL notched = (CGRectGetHeight(UIScreen.mainScreen.bounds) >= 800.0);
    if (notched) return;

    UIViewController *collection = ModuleCollection(overlay);
    if (!collection.view) return;

    NSMutableDictionary<NSValue *, NSString *> *midByView = [NSMutableDictionary dictionary];
    NSDictionary *containers = nil;
    @try { containers = [(id)collection valueForKey:@"moduleContainerViewByIdentifier"]; }
    @catch (__unused NSException *e) {}
    [containers enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
        UIView *cand = [value isKindOfClass:UIView.class] ? value
                     : ([value respondsToSelector:@selector(view)] ? [value view] : nil);
        if (cand) midByView[[NSValue valueWithNonretainedObject:cand]] = key;
    }];

    NSMutableArray<UIView *> *targets = [NSMutableArray array];
    NSMutableArray<NSNumber *> *alphas = [NSMutableArray array];
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:collection.view];
    while (queue.count) {
        UIView *v = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([NSStringFromClass(v.class) isEqualToString:@"CCUIContentModuleContainerView"]) {
            NSString *mid = midByView[[NSValue valueWithNonretainedObject:v]];
            NSInteger page = mid.length ? PACCModulePageForIdentifier(mid) : 0;
            [targets addObject:v];
            [alphas addObject:@((page == gCurrentPage || gPACCRevealAll) ? 1.0 : 0.0)];
        }
        [queue addObjectsFromArray:v.subviews];
    }

    if (animated && targets.count) {
        [UIView animateWithDuration:0.35 delay:0.0
                            options:UIViewAnimationOptionCurveEaseInOut |
                                    UIViewAnimationOptionBeginFromCurrentState |
                                    UIViewAnimationOptionAllowUserInteraction
                         animations:^{
            for (NSUInteger i = 0; i < targets.count; i++) targets[i].alpha = alphas[i].doubleValue;
        } completion:nil];
    } else {
        for (NSUInteger i = 0; i < targets.count; i++) targets[i].alpha = alphas[i].doubleValue;
    }
}

- (void)restoreModuleVisibilityForOverlay:(UIViewController *)overlay {
    BOOL notched = (CGRectGetHeight(UIScreen.mainScreen.bounds) >= 800.0);
    if (notched) return;

    UIViewController *collection = ModuleCollection(overlay);
    if (!collection.view) return;

    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:collection.view];
    while (queue.count) {
        UIView *v = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([NSStringFromClass(v.class) isEqualToString:@"CCUIContentModuleContainerView"]) {
            v.alpha = 1.0;
        }
        [queue addObjectsFromArray:v.subviews];
    }
}

- (void)applyHeaderMaterialHidden:(BOOL)hidden forOverlay:(UIViewController *)overlay {
    BOOL notched = (CGRectGetHeight(UIScreen.mainScreen.bounds) >= 800.0);
    if (notched) return;
    if (!overlay.view) return;

    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:overlay.view];
    while (queue.count) {
        UIView *v = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([NSStringFromClass(v.class) isEqualToString:@"CCUIHeaderPocketView"]) {
            for (UIView *child in v.subviews) {
                NSString *cn = NSStringFromClass(child.class);
                if ([cn isEqualToString:@"MTMaterialView"] || [cn containsString:@"Separator"] || [cn containsString:@"Backdrop"]) {
                    child.hidden = YES;
                }
            }
        }
        [queue addObjectsFromArray:v.subviews];
    }
}

- (void)adjustStatusBarForOverlay:(UIViewController *)overlay {
    BOOL notched = (CGRectGetHeight(UIScreen.mainScreen.bounds) >= 800.0);
    if (notched) return;
    if (!overlay || !overlay.view) return;

    UIWindow *window = overlay.view.window;
    if (!window) return;
    if (window.hidden || window.alpha < 0.01) return;

    UIView *statusBar = nil;
    UIView *fallback = nil;
    NSMutableString *dump = [NSMutableString string];
    NSMutableArray<UIWindow *> *wins = [NSMutableArray arrayWithObject:window];
    for (UIWindow *aw in UIApplication.sharedApplication.windows) if (aw != window) [wins addObject:aw];
    for (UIWindow *sw in wins) {
        if (sw.hidden) continue;
        NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:sw];
        NSUInteger seen = 0;
        while (queue.count && seen++ < 600) {
            UIView *v = queue.firstObject;
            [queue removeObjectAtIndex:0];
            NSString *cn = NSStringFromClass(v.class);
            if ([cn isEqualToString:@"UIStatusBar_Modern"]) {
                statusBar = v;
                [dump appendFormat:@"[%@ %@ win %@] ", cn, NSStringFromCGRect(v.frame), NSStringFromClass(sw.class)];
                break;
            }
            if (!fallback && [cn containsString:@"StatusBar"] && ![cn containsString:@"Window"] &&
                ![cn containsString:@"Controller"] && ![cn containsString:@"Style"] && v != (UIView *)sw) {
                fallback = v;
                [dump appendFormat:@"(%@ %@ win %@) ", cn, NSStringFromCGRect(v.frame), NSStringFromClass(sw.class)];
            }
            [queue addObjectsFromArray:v.subviews];
        }
        if (statusBar) break;
    }
    if (!statusBar) statusBar = fallback;
    if (PACCLandscapeNow()) {
        static NSString *lastDump;
        NSString *note = [NSString stringWithFormat:@"landscape statusbar: %@ tf %@", dump.length ? dump : @"none",
                          statusBar ? NSStringFromCGAffineTransform(statusBar.transform) : @"-"];
        if (![note isEqualToString:lastDump]) { lastDump = note; PACCSizeLog(note); }
    }
    {
        static void *kFGBaseKey = &kFGBaseKey;
        static void *kFGLastKey = &kFGLastKey;
        BOOL fgLand = PACCLandscapeNow();
        for (UIWindow *fw in UIApplication.sharedApplication.windows) {
            if (fw.hidden) continue;
            NSMutableArray<UIView *> *fq = [NSMutableArray arrayWithObject:fw];
            NSUInteger fseen = 0;
            while (fq.count && fseen++ < 800) {
                UIView *fv = fq.firstObject;
                [fq removeObjectAtIndex:0];
                if ([NSStringFromClass(fv.class) isEqualToString:@"_UIStatusBarForegroundView"]) {
                    NSValue *fb = objc_getAssociatedObject(fv, kFGBaseKey);
                    NSValue *fl = objc_getAssociatedObject(fv, kFGLastKey);
                    if (!fb) {
                        if (fl && CGAffineTransformEqualToTransform(fv.transform, fl.CGAffineTransformValue)) continue;
                        fb = [NSValue valueWithCGAffineTransform:fv.transform];
                        objc_setAssociatedObject(fv, kFGBaseKey, fb, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    }
                    CGAffineTransform fbase = fb.CGAffineTransformValue;
                    CGAffineTransform ftarget = fgLand ? CGAffineTransformConcat(fbase, CGAffineTransformMakeTranslation(0, -30.0)) : fbase;
                    if (!CGAffineTransformEqualToTransform(fv.transform, ftarget)) {
                        objc_setAssociatedObject(fv, kFGLastKey, [NSValue valueWithCGAffineTransform:ftarget], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                        fv.transform = ftarget;
                    }
                    continue;
                }
                [fq addObjectsFromArray:fv.subviews];
            }
        }
    }
    if (!statusBar) return;

    BOOL land = PACCLandscapeNow();
    static void *kStatusBarBasePortraitKey = &kStatusBarBasePortraitKey;
    static void *kStatusBarBaseLandscapeKey = &kStatusBarBaseLandscapeKey;
    static void *kStatusBarLastTargetKey = &kStatusBarLastTargetKey;
    const void *baseKey = land ? kStatusBarBaseLandscapeKey : kStatusBarBasePortraitKey;
    NSValue *storedBase = objc_getAssociatedObject(statusBar, baseKey);
    if (!storedBase) {
        NSValue *lastTarget = objc_getAssociatedObject(statusBar, kStatusBarLastTargetKey);
        if (lastTarget && CGAffineTransformEqualToTransform(statusBar.transform, lastTarget.CGAffineTransformValue)) return;
        objc_setAssociatedObject(statusBar, baseKey,
                                 [NSValue valueWithCGAffineTransform:statusBar.transform],
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        storedBase = objc_getAssociatedObject(statusBar, baseKey);
    }
    CGAffineTransform base = storedBase.CGAffineTransformValue;

    CGFloat dy = land ? 0.0 : ((gCurrentPage == PACCMediaPageIndex()) ? -25.0 : 0.0);
    CGAffineTransform target = CGAffineTransformConcat(base, CGAffineTransformMakeTranslation(0, dy));

    if (CGAffineTransformEqualToTransform(statusBar.transform, target)) return;

    objc_setAssociatedObject(statusBar, kStatusBarLastTargetKey,
                             [NSValue valueWithCGAffineTransform:target],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    statusBar.layer.transform = CATransform3DMakeAffineTransform(target);
}

- (void)hideHairlinesForOverlay:(UIViewController *)overlay {
    if (!overlay.view || !PACCLandscapeNow()) return;
    CGFloat ow = overlay.view.bounds.size.width;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:overlay.view];
    NSUInteger seen = 0;
    NSMutableString *dump = [NSMutableString string];
    while (queue.count && seen++ < 700) {
        UIView *v = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if (v != overlay.view && v.bounds.size.height > 0.0 && v.bounds.size.height <= 1.6 &&
            v.bounds.size.width >= ow * 0.8 && v.alpha > 0.01 && !v.hidden) {
            [dump appendFormat:@"%@ %@ | ", NSStringFromClass(v.class), NSStringFromCGRect(v.frame)];
            v.alpha = 0.0;
        }
        [queue addObjectsFromArray:v.subviews];
    }
    if (dump.length) {
        static NSString *lastHair;
        if (![dump isEqualToString:lastHair]) { lastHair = [dump copy]; PACCSizeLog([@"landscape hairline hidden: " stringByAppendingString:dump]); }
    }
}

- (void)animateElementsInForOverlay:(UIViewController *)overlay {
    UIView *host = [overlay.view viewWithTag:kQuickAccessTag];
    UIView *indicator = [overlay.view viewWithTag:kPageIndicatorTag];

    if (host) {
        host.alpha = 0.0;
        host.transform = CGAffineTransformMakeScale(0.6, 0.6);
        [UIView animateWithDuration:0.45 delay:0.0 usingSpringWithDamping:0.7 initialSpringVelocity:0.5 options:UIViewAnimationOptionCurveEaseOut animations:^{
            host.alpha = 1.0;
            host.transform = CGAffineTransformIdentity;
        } completion:nil];
    }
    if (indicator) {
        indicator.hidden = NO;
        indicator.alpha = 0.0;
        indicator.transform = CGAffineTransformIdentity;
        [UIView animateWithDuration:0.35 delay:0.05 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction animations:^{
            indicator.alpha = 1.0;
        } completion:nil];
    }
}

- (void)animateElementsOutForOverlay:(UIViewController *)overlay {
    UIView *indicator = [overlay.view viewWithTag:kPageIndicatorTag];

    [UIView animateWithDuration:0.2 animations:^{
        if (indicator) {
            indicator.alpha = 0.0;
        }
    } completion:^(BOOL finished) {
        if (indicator) {
            indicator.hidden = YES;
            indicator.alpha = 1.0;
        }
    }];
}

- (void)updateQuickAccessButtonsForOverlay:(UIViewController *)overlay {
    UIView *host = [overlay.view viewWithTag:kQuickAccessTag];
    if (!host) {
        host = [[CCAQuickAccessHost alloc] initWithFrame:CGRectZero];
        host.tag = kQuickAccessTag;
        host.backgroundColor = UIColor.clearColor;
        host.userInteractionEnabled = YES;
        [overlay.view addSubview:host];
    }
    CGFloat top = [self topInsetForOverlay:overlay];
    host.frame = CGRectMake(0, top, CGRectGetWidth(overlay.view.bounds), 44);
    host.hidden = !gQuickAccessButtonsEnabled;

    UIButton *plus = [host viewWithTag:181001];
    if (!plus) {
        plus = [self makeRoundButtonWithSymbol:@"plus" tag:181001];
        [plus addTarget:self action:@selector(addPressed:) forControlEvents:UIControlEventTouchUpInside];
        [host addSubview:plus];
    }
    UIButton *power = [host viewWithTag:181002];
    if (!power) {
        power = [self makeRoundButtonWithSymbol:@"power" tag:181002];
        UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(powerPressed:)];
        hold.minimumPressDuration = 0.6;
        [power addGestureRecognizer:hold];
        [power addTarget:self action:@selector(powerTapped:) forControlEvents:UIControlEventTouchUpInside];
        [host addSubview:power];
    }
    CGFloat btnSize = 36;
    CGFloat margin = 22;
    plus.frame = CGRectMake(margin, (CGRectGetHeight(host.bounds) - btnSize) / 2, btnSize, btnSize);
    power.frame = CGRectMake(CGRectGetWidth(host.bounds) - margin - btnSize, (CGRectGetHeight(host.bounds) - btnSize) / 2, btnSize, btnSize);
    [overlay.view bringSubviewToFront:host];
}

- (void)addPressed:(UIButton *)sender {
    if (!gEnabled) return;
    Haptic();
    UIViewController *overlay = OverlayIn(UIApplication.sharedApplication.keyWindow.rootViewController);
    SEL sel = NSSelectorFromString(@"presentAddSheet");
    if (overlay && [overlay respondsToSelector:sel]) {
        ((void (*)(id, SEL))objc_msgSend)(overlay, sel);
    }
}

- (void)powerPressed:(UIGestureRecognizer *)gesture {
    if ([gesture isKindOfClass:UILongPressGestureRecognizer.class] && gesture.state != UIGestureRecognizerStateBegan) return;
    Haptic();
    [self showPowerOff];
}

- (void)powerTapped:(UIButton *)sender {
    Haptic();
    [self showPowerOff];
}

- (void)showPowerOff {
    UIViewController *presenter = OverlayIn(UIApplication.sharedApplication.keyWindow.rootViewController);
    while (presenter.presentedViewController) presenter = presenter.presentedViewController;

    Class factoryClass = NSClassFromString(@"SBUIPowerDownViewControllerFactory");
    SEL factorySel = NSSelectorFromString(@"newPowerDownViewController");
    if (factoryClass && [factoryClass respondsToSelector:factorySel] && presenter) {
        UIViewController *power = ((id (*)(id, SEL))objc_msgSend)(factoryClass, factorySel);
        if ([power isKindOfClass:UIViewController.class]) {
            power.modalPresentationStyle = UIModalPresentationFullScreen;
            [presenter presentViewController:power animated:YES completion:nil];
            return;
        }
    }

    NSArray<NSString *> *classNames = @[@"SBPowerDownController", @"SBUIPowerDownController"];
    NSArray<NSString *> *singletons = @[@"sharedInstance", @"sharedController", @"new"];
    NSArray<NSString *> *shows = @[@"orderFront", @"show", @"presentPowerDown", @"orderFrontWithCompletion:"];
    for (NSString *cn in classNames) {
        Class c = NSClassFromString(cn);
        if (!c) continue;
        id obj = nil;
        for (NSString *sn in singletons) {
            SEL ss = NSSelectorFromString(sn);
            if ([c respondsToSelector:ss]) { obj = ((id (*)(id, SEL))objc_msgSend)(c, ss); if (obj) break; }
        }
        if (!obj) obj = [[c alloc] init];
        if (!obj) continue;
        for (NSString *sh in shows) {
            SEL ss = NSSelectorFromString(sh);
            if (![obj respondsToSelector:ss]) continue;
            if ([sh hasSuffix:@":"]) ((void (*)(id, SEL, id))objc_msgSend)(obj, ss, nil);
            else ((void (*)(id, SEL))objc_msgSend)(obj, ss);
            return;
        }
    }

    Class vcClass = NSClassFromString(@"SBPowerDownViewController");
    if (vcClass && presenter) {
        UIViewController *pv = [[vcClass alloc] init];
        if ([pv isKindOfClass:UIViewController.class]) {
            pv.modalPresentationStyle = UIModalPresentationFullScreen;
            [presenter presentViewController:pv animated:YES completion:nil];
        }
    }
}

- (void)snapToFirstPageForOverlay:(UIViewController *)overlay {
    if (gCurrentPage == 0) return;
    gCurrentPage = 0;

    UIViewController *collection = ModuleCollection(overlay);
    if (!collection.view) return;

    CATransform3D t = PACCDesiredTransform(collection.view.layer.sublayerTransform, collection.view, PACCLandShiftNow(), 0.0);
    collection.view.layer.sublayerTransform = t;

    CCAMediaPlayerView *player = (CCAMediaPlayerView *)[collection.view viewWithTag:kMediaPlayerTag];
    if (player) player.alpha = 0.0;
}

- (void)installPageIndicatorOnOverlay:(UIViewController *)overlay {
    if (!gPagingEnabled) {
        [[overlay.view viewWithTag:kPageIndicatorTag] removeFromSuperview];
        return;
    }

    NSUInteger pageCount = PACCBasePageCount() + PACCUserPageCount();
    if ((NSInteger)gCurrentPage >= (NSInteger)pageCount) {
        [self snapToFirstPageForOverlay:overlay];
    }

    CCAPageIndicator *indicator = (CCAPageIndicator *)[overlay.view viewWithTag:kPageIndicatorTag];
    if (!indicator) {
        indicator = [[CCAPageIndicator alloc] initWithFrame:CGRectZero];
        indicator.tag = kPageIndicatorTag;
        [overlay.view addSubview:indicator];
    }
    indicator.pageCount = pageCount;
    indicator.overlay = overlay;
    indicator.hidden = gCCAModuleExpanded;
    indicator.transform = CGAffineTransformIdentity;
    [self layoutPageIndicatorForOverlay:overlay];
    [overlay.view bringSubviewToFront:indicator];
}

- (void)layoutPageIndicatorForOverlay:(UIViewController *)overlay {
    CCAPageIndicator *indicator = (CCAPageIndicator *)[overlay.view viewWithTag:kPageIndicatorTag];
    if (!indicator) return;
    if (indicator.scrubbing)
return;
    {
        NSUInteger wantCount = PACCBasePageCount() + PACCUserPageCount();
        if (indicator.pageCount != wantCount) {
            indicator.pageCount = wantCount;
            if ((NSInteger)gCurrentPage >= (NSInteger)wantCount) {
                indicator.currentPage = 0;
                [self snapToFirstPageForOverlay:overlay];
            }
        }
    }
    CGFloat step = 50.0;
    CGFloat width = 42.0;
    CGFloat height = step * MAX((NSUInteger)1, indicator.pageCount);
    CGFloat screenRight = CGRectGetWidth(overlay.view.bounds);

    static void *kPagerRightEdgeKey = &kPagerRightEdgeKey;
    NSNumber *cachedEdge = objc_getAssociatedObject(indicator, kPagerRightEdgeKey);

    CGRect modules = PACCVisibleModuleBounds(overlay);
    CGFloat moduleRight = CGRectIsNull(modules) ? 0.0 : CGRectGetMaxX(modules);

    if ((gCurrentPage == 0 || !cachedEdge) && moduleRight > 0.0) {
        objc_setAssociatedObject(indicator, kPagerRightEdgeKey, @(moduleRight),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        cachedEdge = @(moduleRight);
    }
    if (cachedEdge) moduleRight = cachedEdge.doubleValue;

    CGFloat centerX = moduleRight > 0.0 ? (moduleRight + screenRight) * 0.5 : screenRight - 21.0;
    indicator.frame = CGRectMake(centerX - width * 0.5,
                                 floor((CGRectGetHeight(overlay.view.bounds) - height) * 0.5),
                                 width, height);

    [indicator layoutButtons];
    [indicator captureCollectionBase];
}

- (void)installMediaPlayerOnCollectionView:(UIScrollView *)collectionView {
    if (!gEnabled || !gPagingEnabled || !gMediaPageEnabled) {
        [[collectionView viewWithTag:kMediaPlayerTag] removeFromSuperview];
        return;
    }
    CCAMediaPlayerView *player = (CCAMediaPlayerView *)[collectionView viewWithTag:kMediaPlayerTag];
    if (!player) {
        player = [[CCAMediaPlayerView alloc] initWithFrame:CGRectZero];
        player.tag = kMediaPlayerTag;
        player.alpha = 0.0;
        [collectionView addSubview:player];
    }
    [self layoutMediaPlayerForCollectionView:collectionView];
}

- (void)layoutMediaPlayerForCollectionView:(UIScrollView *)collectionView {
    CCAMediaPlayerView *player = (CCAMediaPlayerView *)[collectionView viewWithTag:kMediaPlayerTag];
    if (!player) return;

    CGRect screenBounds = [UIScreen mainScreen].bounds;
    CGFloat screenW = CGRectGetWidth(screenBounds);
    CGFloat screenH = CGRectGetHeight(screenBounds);
    CGFloat span = PageSpan();

    BOOL notched = (screenH >= 800.0);

    CGFloat minTop = notched ? 100.0 : 145.0;
    CGFloat bottomMargin = 20.0;
    CGFloat availableH = screenH - minTop - bottomMargin;

    CGFloat cardW = screenW * (notched ? 0.86 : 0.84);
    CGFloat aspect = 1.60;
    CGFloat cardH = cardW * aspect;
    if (cardH > availableH) {
        cardH = availableH;
        cardW = cardH / aspect;
    }

    CGFloat cardTopScreen = (screenH - cardH) * 0.5;
    if (cardTopScreen < minTop) cardTopScreen = minTop;

    CGFloat x = (screenW - cardW) * 0.5;

    CGFloat frameY;
    if (collectionView.window) {
        CGRect probe = CGRectMake(0, cardTopScreen, 0, 0);
        CGFloat localY = [collectionView convertRect:probe fromView:nil].origin.y;
        frameY = localY + span;
    } else {
        frameY = span + cardTopScreen;
    }

    CGRect targetBounds = CGRectMake(0, 0, cardW, cardH);
    CGPoint targetCenter = CGPointMake(x + cardW * 0.5, frameY + cardH * 0.5);
    if (screenW > screenH && collectionView.window) {
        CGFloat lw = floor(screenW * 0.86);
        CGFloat lh = floor(screenH * 0.78);
        CGRect want = CGRectMake(floor((screenW - lw) * 0.5), floor((screenH - lh) * 0.5) + 8.0, lw, lh);
        CGRect local = PACCLandUnmap(collectionView, want, PACCMediaPageIndex());
        targetBounds = CGRectMake(0, 0, local.size.width, local.size.height);
        targetCenter = CGPointMake(CGRectGetMidX(local), CGRectGetMidY(local));
    }

    if (!CGRectEqualToRect(player.bounds, targetBounds)) {
        player.bounds = targetBounds;
    }
    if (!CGPointEqualToPoint(player.center, targetCenter)) {
        player.center = targetCenter;
    }
}

- (void)installPromoPageOnCollectionView:(UIScrollView *)collectionView {
    if (!gEnabled || !gPagingEnabled || !gPromoPageEnabled) {
        [[collectionView viewWithTag:kPromoPageTag] removeFromSuperview];
        return;
    }
    CCAPromoPageView *promo = (CCAPromoPageView *)[collectionView viewWithTag:kPromoPageTag];
    if (!promo) {
        promo = [[CCAPromoPageView alloc] initWithFrame:CGRectZero];
        promo.tag = kPromoPageTag;
        [collectionView addSubview:promo];
    }
    [self layoutPromoPageForCollectionView:collectionView];
}

- (void)layoutPromoPageForCollectionView:(UIScrollView *)collectionView {
    CCAPromoPageView *promo = (CCAPromoPageView *)[collectionView viewWithTag:kPromoPageTag];
    if (!promo) return;

    if (!gEnabled || !gPagingEnabled || !gPromoPageEnabled) {
        [promo removeFromSuperview];
        return;
    }

    CGRect screenBounds = UIScreen.mainScreen.bounds;
    CGFloat screenW = CGRectGetWidth(screenBounds);
    CGFloat screenH = CGRectGetHeight(screenBounds);
    CGFloat span = PageSpan();

    CGFloat promoW = CGRectGetWidth(collectionView.bounds);
    if (promoW < 1.0) promoW = screenW;
    CGFloat promoH = MIN(240.0, MAX(160.0, screenH * 0.28));

    CGFloat frameY;
    if (collectionView.window) {
        CGRect probe = CGRectMake(0.0, (screenH - promoH) * 0.5, 0.0, 0.0);
        CGFloat localY = [collectionView convertRect:probe fromView:nil].origin.y;
        frameY = localY + span * (CGFloat)MAX(1, PACCPromoPageIndex());
    } else {
        frameY = span * (CGFloat)MAX(1, PACCPromoPageIndex()) + (screenH - promoH) * 0.5;
    }

    promo.bounds = CGRectMake(0.0, 0.0, promoW, promoH);
    promo.center = CGPointMake(floor(promoW * 0.5), floor(frameY + promoH * 0.5));
    if (screenW > screenH && collectionView.window) {
        CGFloat lw = floor(screenW * 0.735);
        CGFloat lh = MIN(190.0, floor(screenH * 0.46));
        CGRect want = CGRectMake(floor((screenW - lw) * 0.5), floor((screenH - lh) * 0.5), lw, lh);
        CGRect local = PACCLandUnmap(collectionView, want, MAX(1, PACCPromoPageIndex()));
        promo.bounds = CGRectMake(0.0, 0.0, local.size.width, local.size.height);
        promo.center = CGPointMake(CGRectGetMidX(local), CGRectGetMidY(local));
    }
}

@end