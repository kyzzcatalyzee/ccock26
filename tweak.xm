#import "PACC.h"

void PACCNoteExpandedModule(id module, BOOL open, UIViewController *ov);
void PACCLogCloseSamples(id module, UIViewController *ov);
void PACCLandBeginPass(UIView *cv);
void PACCLandEndPass(UIView *cv);
void PACCFreeResizeApplyFrame(void);
extern CFTimeInterval gPACCExpandQuietUntil;

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

%hook CCUIStatusBar
- (void)setFrame:(CGRect)frame {
    if (gEnabled && kPACPortScaleOn && !PACCLandscapeNow() && CGRectGetHeight(UIScreen.mainScreen.bounds) < 800.0) {
        frame.origin.y -= 43.0;
    }
    %orig(frame);
}
%end

%hook CCUIModuleCollectionView
- (void)setFrame:(CGRect)frame {
    if (gEnabled && kPACPortScaleOn && !PACCLandscapeNow() && CGRectGetHeight(UIScreen.mainScreen.bounds) < 800.0) {
        frame.origin.y -= 74.0;
    }
    %orig(frame);
}
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

    PACCLandBeginPass((UIView *)(id)self);
    %orig;
    PACCLandEndPass((UIView *)(id)self);
    PACCFreeResizeApplyFrame();
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
            CATransform3D wantT = PACCDesiredTransform(t, (UIView *)(id)self, PACCLandShiftNow(), -(CGFloat)gCurrentPage * span);
            if (!PACCTransformClose(t, wantT)) self.layer.sublayerTransform = wantT;
        }
    }

    objc_setAssociatedObject(self, kPACCInLayoutKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
%end

%hook CCUIModularControlCenterOverlayViewController
- (void)moduleCollectionViewController:(id)collection willOpenExpandedModule:(id)module {
    PACCNoteExpandedModule(module, YES, nil);
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
    gPACCExpandQuietUntil = CACurrentMediaTime() + 1.5;
    UIViewController *overlay = (UIViewController *)(id)self;
    PACCNoteExpandedModule(module, NO, overlay);
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
                    CATransform3D wantT2 = PACCDesiredTransform(t, collection.view, PACCLandShiftNow(), -(CGFloat)gCurrentPage * span);
                    if (!PACCTransformClose(t, wantT2)) collection.view.layer.sublayerTransform = wantT2;
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
        {
            static void *kPACCLandShiftKey = &kPACCLandShiftKey;
            CGSize ovs = overlay.view.bounds.size;
            BOOL land = ovs.width > ovs.height;
            UIView *qh = [overlay.view viewWithTag:kQuickAccessTag];
            for (UIView *qb in qh.subviews) {
                if (qb.tag == 181001 || qb.tag == 181002) qb.hidden = land;
            }
            (void)kPACCLandShiftKey;
            if (land) {
                static NSTimer *landTimer = nil;
                if (!landTimer) {
                    __weak UIViewController *wov = overlay;
                    landTimer = [NSTimer scheduledTimerWithTimeInterval:0.2 repeats:YES block:^(NSTimer *t) {
                        UIViewController *ov2 = wov;
                        if (!ov2 || !ov2.view.window || ov2.view.window.hidden || !PACCLandscapeNow()) {
                            [t invalidate];
                            landTimer = nil;
                            return;
                        }
                        [PACC.shared adjustStatusBarForOverlay:ov2];
                        [PACC.shared hideHairlinesForOverlay:ov2];
                        PACCLandscapeRefresh(ov2);
                    }];
                }
                [PACC.shared hideHairlinesForOverlay:overlay];
                PACCLandscapeRefresh(overlay);
            }
            UIViewController *lcol = ModuleCollection(overlay);
            UIView *lv = lcol.view;
            if (lv && !gPagerScrubbing) {
                CATransform3D lt = lv.layer.sublayerTransform;
                CATransform3D lwant = PACCDesiredTransform(lt, lv, PACCLandShiftNow(), -(CGFloat)gCurrentPage * PageSpan());
                if (!PACCTransformClose(lt, lwant)) lv.layer.sublayerTransform = lwant;
            }
        }
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
    CGFloat spacing = width * 0.29;
    CGAffineTransform big = CGAffineTransformMakeScale(1.28, 1.28);
    left.transform = big; center.transform = big; right.transform = big;

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

static void PACCScaleContainerContent(UIView *me) {
    @try {
                UIView *cv = me.superview;
        BOOL inGrid = cv && [NSStringFromClass(cv.class) isEqualToString:@"CCUIModuleCollectionView"];
        BOOL ex = NO;
        SEL s1 = NSSelectorFromString(@"isExpanded"), s2 = NSSelectorFromString(@"expanded");
        if ([me respondsToSelector:s1]) ex = ((BOOL (*)(id, SEL))objc_msgSend)(me, s1);
        else if ([me respondsToSelector:s2]) ex = ((BOOL (*)(id, SEL))objc_msgSend)(me, s2);
        CGSize bs = me.bounds.size;
        BOOL act = gEnabled && inGrid && !ex && gPACPortHave && cv.window && !PACCLandscapeNow() &&
                   PACCPortFrameActive(cv) && gPACPortSc > 0.3 && gPACPortSc < 0.999 && bs.width > 2.0 && bs.height > 2.0;
        static const void *kScaled = &kScaled;
        if (act) {
            CGFloat k = gPACPortSc;
            CGAffineTransform want = CGAffineTransformMakeScale(k, k);
            for (UIView *s in me.subviews) {
                if (s.tag == 190200 || s.tag == 182100) continue;
                s.transform = CGAffineTransformIdentity;
                s.bounds = CGRectMake(0, 0, bs.width / k, bs.height / k);
                s.center = CGPointMake(bs.width * 0.5, bs.height * 0.5);
                s.transform = want;
                objc_setAssociatedObject(s, kScaled, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        } else {
            for (UIView *s in me.subviews) {
                if (!objc_getAssociatedObject(s, kScaled)) continue;
                objc_setAssociatedObject(s, kScaled, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                s.transform = CGAffineTransformIdentity;
                s.frame = me.bounds;
            }
        }
    } @catch (__unused NSException *e) {}
}

%hook CCUIContentModuleContainerView
- (void)layoutSubviews {
    %orig;
    PACCScaleContainerContent((UIView *)(id)self);
    if (gEnabled) PACCBigStripContainer((UIView *)self);
}
%end

static void PACCTrackExpansion(UIViewController *vc) {
    __weak UIViewController *wv = vc;
    CFTimeInterval t0 = CACurrentMediaTime();
    NSString *mid = @"?";
    @try { id v = [vc valueForKey:@"moduleIdentifier"]; if ([v isKindOfClass:NSString.class]) mid = v; } @catch (__unused NSException *e) {}
    NSString *midCopy = [mid copy];
    __block NSString *lastLine = @"";
    for (int i = 1; i <= 90; i++) {
        double d = i * 0.05;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(d * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIViewController *m = wv;
            if (!m || !m.view) return;
            SEL es = NSSelectorFromString(@"isExpanded");
            BOOL ex = [m respondsToSelector:es] ? ((BOOL (*)(id, SEL))objc_msgSend)(m, es) : NO;
            CALayer *pl = (CALayer *)m.view.layer.presentationLayer;
            CGRect inWin = [m.view convertRect:m.view.bounds toView:nil];
            CGRect pw = pl ? [pl convertRect:pl.bounds toLayer:nil] : CGRectZero;
            NSString *line = [NSString stringWithFormat:@"%@ ex %d super %@ win %@ pwin %@ alpha %.2f",
                              midCopy, (int)ex, NSStringFromClass(m.view.superview.class),
                              NSStringFromCGRect(CGRectIntegral(inWin)), NSStringFromCGRect(CGRectIntegral(pw)), m.view.alpha];
            if (![line isEqualToString:lastLine]) {
                lastLine = line;
                PACCSizeLog([NSString stringWithFormat:@"track t+%.2f %@", CACurrentMediaTime() - t0, line]);
            }
        });
    }
}

%hook CCUIContentModuleContainerViewController
- (void)viewDidLayoutSubviews {
    %orig;
    if (gEnabled) {
        UIView *cvw = ((UIViewController *)(id)self).view;
        if (cvw && [NSStringFromClass(cvw.class) isEqualToString:@"CCUIContentModuleContainerView"]) PACCScaleContainerContent(cvw);
    }
    @try {
        static __weak UIViewController *sExpandedVC = nil;
        UIViewController *vc0 = (UIViewController *)self;
        SEL es0 = NSSelectorFromString(@"isExpanded");
        BOOL exp0 = [vc0 respondsToSelector:es0] ? ((BOOL (*)(id, SEL))objc_msgSend)(vc0, es0) : NO;
        if (exp0 && sExpandedVC != vc0) {
            sExpandedVC = vc0;
            PACCNoteExpandedModule(vc0, YES, nil);
            gCCAModuleExpanded = YES;
            PACCSizeLog(@"expanded module opened (container layout)");
            PACCTrackExpansion(vc0);
        } else if (!exp0 && sExpandedVC == vc0) {
            sExpandedVC = nil;
            gCCAModuleExpanded = NO;
            gPACCExpandQuietUntil = CACurrentMediaTime() + 1.5;
            UIViewController *ovc = OverlayIn(UIApplication.sharedApplication.keyWindow.rootViewController);
            PACCNoteExpandedModule(vc0, NO, ovc);
            PACCSizeLog(@"expanded module closed (container layout)");
        }
    } @catch (__unused NSException *e) {}
    @try {
        UIViewController *me = (UIViewController *)self;
        UIViewController *content = nil;
        SEL cs = NSSelectorFromString(@"contentViewController");
        if ([me respondsToSelector:cs]) content = ((id (*)(id, SEL))objc_msgSend)(me, cs);
        if (![NSStringFromClass(content.class) containsString:@"Connectivity"]) return;
        double pref = -1;
        SEL ps = NSSelectorFromString(@"preferredExpandedContentHeight");
        if ([content respondsToSelector:ps]) pref = ((double (*)(id, SEL))objc_msgSend)(content, ps);
        BOOL exp = NO;
        SEL es = NSSelectorFromString(@"isExpanded");
        if ([me respondsToSelector:es]) exp = ((BOOL (*)(id, SEL))objc_msgSend)(me, es);
        UIView *cv = content.view;
        UIView *wrap = cv.superview;
        const CGFloat kWant = 570.0;
        const CGFloat kWantW = 330.0;
        if (gEnabled && exp && wrap && wrap != me.view && CGAffineTransformIsIdentity(wrap.transform) &&
            me.view.bounds.size.width < me.view.bounds.size.height &&
            wrap.bounds.size.height > 300.0 && wrap.bounds.size.height < kWant - 0.5) {
            CGRect f = wrap.frame;
            CGFloat dh = kWant - f.size.height;
            f.origin.y -= dh * 0.5;
            f.size.height = kWant;
            {
                CGFloat nw = MIN(f.size.width, kWantW);
                f.origin.x += (f.size.width - nw) * 0.5;
                f.size.width = nw;
            }
            CGFloat maxH = me.view.bounds.size.height;
            if (f.origin.y < 10.0) f.origin.y = 10.0;
            if (CGRectGetMaxY(f) > maxH - 10.0) f.origin.y = maxH - 10.0 - f.size.height;
            wrap.frame = f;
            cv.frame = wrap.bounds;
        }
        if (gEnabled && exp && wrap && wrap != me.view && CGAffineTransformIsIdentity(wrap.transform) &&
            me.view.bounds.size.width > me.view.bounds.size.height) {
            CGFloat wantW = MIN(620.0, me.view.bounds.size.width - 60.0);
            if (wrap.frame.size.width < wantW - 0.5) {
                CGRect lf = wrap.frame;
                lf.origin.x -= (wantW - lf.size.width) * 0.5;
                lf.size.width = wantW;
                wrap.frame = lf;
                cv.frame = wrap.bounds;
            }
        }
        static NSString *lastNote;
        NSString *note = [NSString stringWithFormat:@"container %@ view %@ content %@ wrap %@ %@ pref %.1f expanded %d",
                          NSStringFromClass(me.class), NSStringFromCGRect(me.view.frame),
                          NSStringFromCGRect(cv.frame), NSStringFromClass(wrap.class), NSStringFromCGRect(wrap.frame), pref, (int)exp];
        if (![note isEqualToString:lastNote]) { lastNote = note; PACCSizeLog(note); }
    } @catch (__unused NSException *e) {}
}
%end

%hook CCUIConnectivityModuleViewController
- (CGFloat)preferredExpandedContentHeight {
    CGFloat orig = %orig;
    PACCSizeLog([NSString stringWithFormat:@"hook height called: orig %.1f enabled %d", orig, (int)gEnabled]);
    if (!gEnabled) return orig;
    static NSString *lastNote;
    NSString *note = [NSString stringWithFormat:@"expanded height: orig %.1f -> 570, screen %.1f", orig, [UIScreen mainScreen].bounds.size.height];
    if (![note isEqualToString:lastNote]) { lastNote = note; PACCSizeLog(note); }
    return 570.0;
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

%hook CCUIBaseSliderView
- (void)didMoveToWindow {
    %orig;
    UIView *sv = (UIView *)(id)self;
    if (sv.window && gEnabled && PACCInControlCenter(sv)) PACCAddBounce(sv);
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