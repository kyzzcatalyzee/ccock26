#import "PACC.h"
#import <sys/utsname.h>
#import <objc/runtime.h>

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

#define kPACCCloseLandDrop 170.0

// Home-button iPhones: Control Center opens from the bottom edge and closes downwards.
// Decided from the hardware model, not the screen height (the fullscreen resolution hack
// makes a home-button phone look like a notched one).
static BOOL PACCHomeButtonDevice(void) {
    static BOOL cached = NO, value = NO;
    if (cached) return value;
    struct utsname u; uname(&u);
    NSString *m = [NSString stringWithUTF8String:u.machine];
    int major = 0, minor = 0;
    if ([m hasPrefix:@"iPhone"] && sscanf(m.UTF8String, "iPhone%d,%d", &major, &minor) == 2) {
        if (major < 10) value = YES;
        else if (major == 10) value = (minor == 1 || minor == 2 || minor == 4 || minor == 5);
        else if (major == 12) value = (minor == 8);
        else if (major == 14) value = (minor == 6);
    }
    cached = YES;
    return value;
}
static void PACCApplyExpandShiftEx(BOOL animated);
static NSUInteger gPACCDismissToken = 0;
static NSInteger gPACCPState = -1;
static CGFloat gPACCDismissDir = 0.0;

// Which way is the overlay content moving right now? > 0 = down, < 0 = up. Compares a module
// container's on-screen (presentation) position with its model position, so it follows the real
// gesture (also with tweaks that bring Control Center in from the top).
static CGFloat PACCSampleCloseDirection(UIViewController *ov) {
    UIViewController *col = ov ? ModuleCollection(ov) : nil;
    Class cc = NSClassFromString(@"CCUIContentModuleContainerView");
    if (!col.view || !cc) return 0.0;
    for (UIView *v in col.view.subviews) {
        if (![v isKindOfClass:cc] || v.hidden || !v.window) continue;
        CALayer *pl = v.layer.presentationLayer;
        if (!pl) continue;
        CGRect pr = [pl convertRect:pl.bounds toLayer:nil];
        CGRect mr = [v convertRect:v.bounds toView:nil];
        return CGRectGetMidY(pr) - CGRectGetMidY(mr);
    }
    return 0.0;
}

static BOOL PACCPanActive(UIViewController *ov) {
    for (UIView *v = ov.view; v; v = v.superview) {
        for (UIGestureRecognizer *gr in v.gestureRecognizers) {
            if (![gr isKindOfClass:UIPanGestureRecognizer.class] && ![gr isKindOfClass:UILongPressGestureRecognizer.class]) continue;
            if (gr.state == UIGestureRecognizerStateBegan || gr.state == UIGestureRecognizerStateChanged) return YES;
        }
    }
    return NO;
}

static void PACCDumpOverlayMethods(void) {
    static BOOL done = NO;
    if (done) return;
    done = YES;
    unsigned int n = 0;
    Class *all = objc_copyClassList(&n);
    for (unsigned int i = 0; i < n; i++) {
        const char *cn = class_getName(all[i]);
        if (strncmp(cn, "CCUIContentModule", 17) != 0 && strncmp(cn, "CCUIModuleCollection", 20) != 0 && strncmp(cn, "CCUIExpand", 10) != 0 && strncmp(cn, "CCUIMenuModule", 14) != 0) continue;
        NSMutableString *line = [NSMutableString stringWithFormat:@"methods %s (super %s):", cn, class_getSuperclass(all[i]) ? class_getName(class_getSuperclass(all[i])) : "-"];
        unsigned int mc = 0;
        Method *ms = class_copyMethodList(all[i], &mc);
        for (unsigned int j = 0; j < mc; j++) [line appendFormat:@" %s", sel_getName(method_getName(ms[j]))];
        free(ms);
        PACCSizeLog(line);
    }
    free(all);
}

static NSInteger gPACCLastStable = 0;
static BOOL gPACCClosingNow = NO;
#define kPACCLandExtra 420.0

static CGAffineTransform (*PACCOrigSlideTransform)(id, SEL, id, CGFloat) = NULL;
static NSUInteger gPACCTfLogCount = 0;

// Real hook: CCUIOverlaySlideUpPresentationProvider (the bottom-up Control Center) computes the
// container transform from the transition state. While the CC is closing we add extra downward
// translation proportional to (1 - presentationProgress), so the stock animation itself lands lower.
static CGAffineTransform PACCSlideTransformHook(id self, SEL _cmd, id state, CGFloat h) {
    CGAffineTransform t = PACCOrigSlideTransform(self, _cmd, state, h);
    if (!gEnabled || !gPACCClosingNow || PACCLandscapeNow()) return t;
    double p = 1.0;
    SEL ps = NSSelectorFromString(@"presentationProgress");
    if (state && [state respondsToSelector:ps]) p = ((double (*)(id, SEL))objc_msgSend)(state, ps);
    if (p >= 0.999) return t;
    if (p < 0.0) p = 0.0;
    CGFloat extra = (CGFloat)((1.0 - p) * kPACCLandExtra);
    if (gPACCTfLogCount < 40) {
        gPACCTfLogCount++;
        PACCSizeLog([NSString stringWithFormat:@"slideTransform p %.2f ty %.1f + %.1f", p, t.ty, extra]);
    }
    t.ty += extra;
    return t;
}

static void PACCInstallProviderHook(void) {
    static BOOL done = NO;
    if (done) return;
    done = YES;
    Class c = NSClassFromString(@"CCUIOverlaySlideUpPresentationProvider");
    SEL sel = NSSelectorFromString(@"_transformForTransitionState:rubberBandingHeight:");
    Method m = c ? class_getInstanceMethod(c, sel) : NULL;
    if (!m) { PACCSizeLog(@"provider hook: method not found"); return; }
    char *rt = method_copyReturnType(m);
    BOOL okRet = rt && strncmp(rt, "{CGAffineTransform", 18) == 0;
    NSString *rts = rt ? [NSString stringWithUTF8String:rt] : @"?";
    free(rt);
    char *a3 = method_copyArgumentType(m, 3);
    BOOL okArg = method_getNumberOfArguments(m) == 4 && a3 && (a3[0] == 'd' || a3[0] == 'f');
    NSString *a3s = a3 ? [NSString stringWithUTF8String:a3] : @"?";
    free(a3);
    PACCSizeLog([NSString stringWithFormat:@"provider hook: ret %@ arg3 %@ enc %s ok %d", rts, a3s, method_getTypeEncoding(m), (int)(okRet && okArg)]);
    if (!(okRet && okArg)) return;
    PACCOrigSlideTransform = (CGAffineTransform (*)(id, SEL, id, CGFloat))method_getImplementation(m);
    method_setImplementation(m, (IMP)PACCSlideTransformHook);
}

// Diagnostics for the hold-to-expand / close animation position: log what the stock frame
// providers return (only installed if the return type is really a CGRect and there are no args).
#define PACC_RECT_LOG_HOOK(NAME, CLS, SELNAME) \
static CGRect (*PACCOrig_##NAME)(id, SEL) = NULL; \
static NSUInteger gPACCCnt_##NAME = 0; \
static CGRect PACCHook_##NAME(id self, SEL _cmd) { \
    CGRect r = PACCOrig_##NAME(self, _cmd); \
    if (gPACCCnt_##NAME < 24) { gPACCCnt_##NAME++; \
        PACCSizeLog([NSString stringWithFormat:@"rect " SELNAME " %@ cls %@", NSStringFromCGRect(r), NSStringFromClass([self class])]); } \
    return r; \
}
PACC_RECT_LOG_HOOK(cfe, 0, "_containerFrameForExpandedState")
PACC_RECT_LOG_HOOK(pfe, 0, "_presentationFrameForExpandedState")
static CGRect (*PACCOrig_contfe)(id, SEL) = NULL;
static NSUInteger gPACCCnt_contfe = 0;
static CGFloat gPACCExpW = 414.0;
static CGRect PACCHook_contfe(id self, SEL _cmd) {
    CGRect r = PACCOrig_contfe(self, _cmd);
    if (r.size.width > 200.0) gPACCExpW = r.size.width;
    if (gPACCCnt_contfe < 24) { gPACCCnt_contfe++; PACCSizeLog([NSString stringWithFormat:@"rect _contentFrameForExpandedState %@ cls %@", NSStringFromCGRect(r), NSStringFromClass([self class])]); }
    return r;
}

// The stock expand/collapse animation starts from / lands on the module's RAW rest frame, but on
// home-button phones the module grid is shown scaled (0.91) and shifted by cv.layer.sublayerTransform,
// so the animation ended ~15pt/33pt away from the visible tile. Map the raw rect through that transform.
static CGRect PACCVisualRect(CGRect R) {
    if (!gEnabled || CGRectIsEmpty(R) || CGRectIsNull(R)) return R;
    UIViewController *ov = OverlayIn(UIApplication.sharedApplication.keyWindow.rootViewController);
    UIView *cv = ov ? ModuleCollection(ov).view : nil;
    if (!cv) return R;
    CGAffineTransform at = CATransform3DGetAffineTransform(cv.layer.sublayerTransform);
    if (CGAffineTransformIsIdentity(at)) return R;
    CGRect Rc = [cv convertRect:R fromView:nil];
    CGFloat cx = CGRectGetMidX(cv.bounds), cy = CGRectGetMidY(cv.bounds);
    CGFloat xs[2] = { CGRectGetMinX(Rc), CGRectGetMaxX(Rc) }, ys[2] = { CGRectGetMinY(Rc), CGRectGetMaxY(Rc) };
    CGFloat minX = CGFLOAT_MAX, minY = CGFLOAT_MAX, maxX = -CGFLOAT_MAX, maxY = -CGFLOAT_MAX;
    for (int i = 0; i < 2; i++) for (int j = 0; j < 2; j++) {
        CGFloat dx = xs[i] - cx, dy = ys[j] - cy;
        CGFloat px = cx + at.a * dx + at.c * dy + at.tx;
        CGFloat py = cy + at.b * dx + at.d * dy + at.ty;
        minX = MIN(minX, px); maxX = MAX(maxX, px); minY = MIN(minY, py); maxY = MAX(maxY, py);
    }
    return [cv convertRect:CGRectMake(minX, minY, maxX - minX, maxY - minY) toView:nil];
}

static CGRect (*PACCOrig_cfr)(id, SEL) = NULL;
static CGRect (*PACCOrig_cro)(id, SEL) = NULL;
static NSUInteger gPACCCnt_restfix = 0;
// ---------------------------------------------------------------------------------------------
// Hold-to-expand / close landing on the visible (scaled) tile WITHOUT touching the rects stock reads.
// (Returning a corrected _contentFrameForRestState made FCUIActivityListContentView of Focus grow
// +15pt and its round button sink 3.5pt on every cycle - log v0.8.57/58.) Stock animates the content
// wrapper between the raw rest rect and the expanded rect (full screen). Instead we leave stock alone
// and, every frame, give that wrapper a layer transform that maps raw -> visual rect, blended by the
// animation progress p = (expandedW - w) / (expandedW - restW): p = 1 at rest, 0 when expanded.
// ---------------------------------------------------------------------------------------------
static const void *kPACCRawRestKey = &kPACCRawRestKey;
static const void *kPACCFixedKey = &kPACCFixedKey;
static CFTimeInterval gPACCFixUntil = 0.0;
static NSHashTable<UIViewController *> *gPACCSeenVCs;
static NSInteger gPACCFixLog = 80;

static UIView *PACCFindWrapper(UIView *root) {
    static Class wc;
    if (!wc) wc = NSClassFromString(@"CCUIContentModuleContentContainerView");
    if (!wc) return nil;
    NSMutableArray<UIView *> *q = [NSMutableArray arrayWithObject:root];
    NSUInteger n = 0;
    while (q.count && n < 40) {
        UIView *v = q.firstObject; [q removeObjectAtIndex:0]; n++;
        if ([v isKindOfClass:wc]) return v;
        [q addObjectsFromArray:v.subviews];
    }
    return nil;
}

static BOOL PACCInTransitionView(UIView *v) {
    for (UIView *a = v; a; a = a.superview) if ([NSStringFromClass(a.class) containsString:@"TransitionView"]) return YES;
    return NO;
}

@interface PACCRestFixer : NSObject
@property (nonatomic, strong) CADisplayLink *link;
- (void)tick:(CADisplayLink *)l;
@end
static PACCRestFixer *sPACCFixer;

@implementation PACCRestFixer
- (void)tick:(CADisplayLink *)l {
    BOOL active = NO;
    if (gEnabled && !PACCLandscapeNow()) {
        // The expanded module is no longer in the overlay's child tree during the transition, so
        // iterate the module VCs seen by the rest-frame hook instead of walking the overlay.
        for (UIViewController *m in [gPACCSeenVCs allObjects]) {
            UIView *view = m.view;
            if (!view || !view.window) continue;
            NSValue *rawV = objc_getAssociatedObject(m, kPACCRawRestKey);
            UIView *wr = rawV ? PACCFindWrapper(view) : nil;
            if (!wr) continue;
            BOOL ours = objc_getAssociatedObject(wr, kPACCFixedKey) != nil;
            if (!PACCInTransitionView(view)) {
                if (ours) {
                    [CATransaction begin]; [CATransaction setDisableActions:YES];
                    wr.layer.transform = CATransform3DIdentity;
                    [CATransaction commit];
                    objc_setAssociatedObject(wr, kPACCFixedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                }
                continue;
            }
            active = YES;
            CGRect R = rawV.CGRectValue;
            CGRect V = PACCVisualRect(R);
            if (CGRectIsEmpty(R) || CGRectIsEmpty(V) || R.size.width < 1.0) continue;
            CALayer *pl = wr.layer.presentationLayer ?: wr.layer;
            CGFloat w = pl.bounds.size.width;
            CGFloat span = gPACCExpW - R.size.width;
            if (span < 1.0) continue;
            CGFloat p = MAX(0.0, MIN(1.0, (gPACCExpW - w) / span));
            CGFloat s = V.size.width / R.size.width;
            CGFloat A = 1.0 + (s - 1.0) * p;
            CGPoint Rc = CGPointMake(CGRectGetMidX(R), CGRectGetMidY(R));
            CGPoint Vc = CGPointMake(CGRectGetMidX(V), CGRectGetMidY(V));
            CGFloat tx = (Vc.x - s * Rc.x) * p, ty = (Vc.y - s * Rc.y) * p;
            CGPoint C = pl.position;
            CGFloat dx = (A - 1.0) * C.x + tx, dy = (A - 1.0) * C.y + ty;
            CATransform3D T = CATransform3DScale(CATransform3DMakeTranslation(dx, dy, 0.0), A, A, 1.0);
            [CATransaction begin]; [CATransaction setDisableActions:YES];
            wr.layer.transform = T;
            [CATransaction commit];
            objc_setAssociatedObject(wr, kPACCFixedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            if (gPACCFixLog > 0) {
                gPACCFixLog--;
                PACCSizeLog([NSString stringWithFormat:@"landfix w %.1f pos %@ p %.2f A %.3f d %.1f,%.1f raw %@ vis %@", w, NSStringFromCGPoint(C), p, A, dx, dy, NSStringFromCGRect(R), NSStringFromCGRect(V)]);
            }
        }
    }
    if (!active && CACurrentMediaTime() > gPACCFixUntil) l.paused = YES;
}
@end

static void PACCKickRestFixer(void) {
    gPACCFixUntil = CACurrentMediaTime() + 2.5;
    if (!sPACCFixer) {
        sPACCFixer = [PACCRestFixer new];
        sPACCFixer.link = [CADisplayLink displayLinkWithTarget:sPACCFixer selector:@selector(tick:)];
        [sPACCFixer.link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }
    sPACCFixer.link.paused = NO;
}

static NSUInteger gPACCRestCycle = 0;
// _contentFrameForRestState / contentRestOverrideFrame are only OBSERVED now (raw rect stored per module).
static CGRect PACCHook_cfr(id self, SEL _cmd) {
    CGRect r = PACCOrig_cfr(self, _cmd);
    if ([(id)self isKindOfClass:UIViewController.class] && !CGRectIsEmpty(r)) {
        if (!gPACCSeenVCs) gPACCSeenVCs = [NSHashTable weakObjectsHashTable];
        [gPACCSeenVCs addObject:(UIViewController *)self];
    }
    if ([(id)self isKindOfClass:UIViewController.class] && !CGRectIsEmpty(r))
        objc_setAssociatedObject(self, kPACCRawRestKey, [NSValue valueWithCGRect:r], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    PACCKickRestFixer();
    if (gPACCCnt_restfix < 40) {
        gPACCCnt_restfix++;
        PACCSizeLog([NSString stringWithFormat:@"restfix #%lu rest %@ (observed)", (unsigned long)gPACCRestCycle++, NSStringFromCGRect(r)]);
    }
    return r;
}
static CGRect PACCHook_cro(id self, SEL _cmd) {
    CGRect r = PACCOrig_cro(self, _cmd);
    PACCKickRestFixer();
    return r;
}

static void PACCInstallRectLog(const char *cls, const char *sel, IMP hook, IMP *orig) {
    Class c = objc_getClass(cls);
    Method m = c ? class_getInstanceMethod(c, sel_registerName(sel)) : NULL;
    if (!m) { PACCSizeLog([NSString stringWithFormat:@"rectlog %s: not found", sel]); return; }
    char *rt = method_copyReturnType(m);
    BOOL ok = rt && strncmp(rt, "{CGRect", 7) == 0 && method_getNumberOfArguments(m) == 2;
    free(rt);
    if (!ok) { PACCSizeLog([NSString stringWithFormat:@"rectlog %s: type mismatch %s", sel, method_getTypeEncoding(m)]); return; }
    *orig = method_getImplementation(m);
    method_setImplementation(m, hook);
}

static void PACCInstallRectLogs(void) {
    static BOOL done = NO;
    if (done) return;
    done = YES;
    PACCInstallRectLog("CCUIContentModuleContainerViewController", "_containerFrameForExpandedState", (IMP)PACCHook_cfe, (IMP *)&PACCOrig_cfe);
    PACCInstallRectLog("CCUIContentModuleContainerViewController", "_presentationFrameForExpandedState", (IMP)PACCHook_pfe, (IMP *)&PACCOrig_pfe);
    PACCInstallRectLog("CCUIContentModuleContainerViewController", "_contentFrameForExpandedState", (IMP)PACCHook_contfe, (IMP *)&PACCOrig_contfe);
    PACCInstallRectLog("CCUIContentModuleContainerViewController", "_contentFrameForRestState", (IMP)PACCHook_cfr, (IMP *)&PACCOrig_cfr);
    PACCInstallRectLog("CCUIContentModuleContainerTransition", "contentRestOverrideFrame", (IMP)PACCHook_cro, (IMP *)&PACCOrig_cro);
}

static CGFloat gPACCCloseExtra = 0.0;
static CGFloat gPACCCloseBase = 0.0;
static CFTimeInterval gPACCCloseRelease = 0.0;
static CFTimeInterval gPACCCloseStart = 0.0;
static CADisplayLink *gPACCCloseLink = nil;
static __weak UIViewController *gPACCCloseOverlay = nil;
#define kPACCCloseLandGain 7.0
#define kPACCCloseLandMax 900.0

static void PACCStopCloseTicker(void) {
    [gPACCCloseLink invalidate];
    gPACCCloseLink = nil;
}

@interface PACCCloseTicker : NSObject
+ (void)tick:(CADisplayLink *)l;
@end
@implementation PACCCloseTicker
// Amplifies the stock close motion so it lands lower: after the finger is released the grid
// is pushed down by (gain-1) x the stock displacement, latched so it never springs back.
+ (void)tick:(CADisplayLink *)l {
    UIViewController *o = gPACCCloseOverlay;
    CFTimeInterval now = CACurrentMediaTime();
    if (!o || gPACCPState != 3 || now - gPACCCloseStart > 3.0) {
        PACCSizeLog([NSString stringWithFormat:@"closetick stop state %ld t %.2f extra %.1f dir %.1f", (long)gPACCPState, now - gPACCCloseStart, gPACCCloseExtra, gPACCDismissDir]);
        PACCStopCloseTicker();
        return;
    }
    CGFloat d = PACCSampleCloseDirection(o);
    if (fabs(d) > 3.0) gPACCDismissDir = d;
    BOOL pan = PACCPanActive(o);
    static CFTimeInterval lastLog = 0;
    if (now - lastLog > 0.08) {
        lastLog = now;
        PACCSizeLog([NSString stringWithFormat:@"closetick t %.2f d %.1f dir %.1f pan %d extra %.1f", now - gPACCCloseStart, d, gPACCDismissDir, (int)pan, gPACCCloseExtra]);
    }
    if (pan) { gPACCCloseRelease = 0.0; return; }
    if (gPACCCloseRelease == 0.0) gPACCCloseRelease = now;
    BOOL down = (gPACCDismissDir > 0.0);
    if (!down) return;
    CGFloat ramp = MIN(1.0, (now - gPACCCloseRelease) / 0.15);
    CGFloat want = MIN(kPACCCloseLandMax, (kPACCCloseLandGain - 1.0) * MAX(d, 0.0)) * ramp;
    if (want > gPACCCloseExtra) {
        gPACCCloseExtra = want;
        gPACCExpandShift = gPACCCloseBase + gPACCCloseExtra;
        PACCApplyExpandShiftEx(NO);
    }
}
@end

__attribute__((unused)) static void PACCStartCloseTicker(UIViewController *ov) {
    PACCStopCloseTicker();
    gPACCCloseOverlay = ov;
    gPACCCloseBase = gPACCExpandShift;
    gPACCCloseExtra = 0.0;
    gPACCCloseRelease = 0.0;
    gPACCCloseStart = CACurrentMediaTime();
    gPACCCloseLink = [CADisplayLink displayLinkWithTarget:PACCCloseTicker.class selector:@selector(tick:)];
    [gPACCCloseLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}

// Fade the overlay leftovers only once the close is really happening: the
// presentation state is still 3 and no finger is dragging any more. A pull that
// is cancelled (state back to 1) bumps the token and nothing fades.
static void PACCPollDismiss(UIViewController *ov, NSUInteger token, double elapsed) {
    __weak UIViewController *wov = ov;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIViewController *o = wov;
        if (!o || token != gPACCDismissToken || gPACCPState != 3) return;
        double el = elapsed + 0.05;
        { CGFloat d = PACCSampleCloseDirection(o); if (fabs(d) > 3.0) gPACCDismissDir = d; }
        if (el >= 0.3 && !PACCPanActive(o)) {
            gPACCDismissing = YES;
            PACCSizeLog([NSString stringWithFormat:@"close landing: direction %.1f extra %.1f after %.2fs", gPACCDismissDir, gPACCCloseExtra, el]);
            return;
        }
        if (el < 2.5) PACCPollDismiss(o, token, el);
    });
}

%hook CCUIModularControlCenterOverlayViewController
- (void)moduleCollectionViewController:(id)collection willOpenExpandedModule:(id)module {
    PACCNoteExpandedModule(module, YES, nil);
    gCCAModuleExpanded = YES;
    UIViewController *overlay = (UIViewController *)(id)self;
    if (gPACCExpandTop < 0.0 && !PACCLandscapeNow()) gPACCExpandTop = PACCGridTopY(overlay) - gPACCExpandShift;
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
    if (stateChanged) PACCSizeLog([NSString stringWithFormat:@"pstate %ld -> %ld alpha %.2f", (long)(lastState ? lastState.integerValue : -1), (long)state, overlay.view.alpha]);
    BOOL closing = (state == 3 && gPACCLastStable == 1 && !(lastState && lastState.integerValue == 3));
    gPACCClosingNow = ((state == 2 || state == 3) && gPACCLastStable == 1);
    if (state == 0 || state == 1) { gPACCLastStable = state; gPACCClosingNow = NO; gPACCTfLogCount = 0; }
    gPACCPState = state;
    PACCDumpOverlayMethods();
    PACCInstallProviderHook();
    PACCInstallRectLogs();

    BOOL notched = (CGRectGetHeight(UIScreen.mainScreen.bounds) >= 800.0);
    CCAMediaPlayerView *player = (CCAMediaPlayerView *)[overlay.view viewWithTag:kMediaPlayerTag];

    if (state == 1) {
        gPACCDismissToken++;
        PACCStopCloseTicker();
        if (fabs(gPACCExpandShift) > 0.01 && !gCCAModuleExpanded) { gPACCExpandShift = 0.0; PACCApplyExpandShiftEx(NO); }
        if (gPACCDismissing) { gPACCDismissing = NO; PACCResetClonesAfterDismiss(overlay); }
        if (overlay.view.alpha < 0.999) {
            [overlay.view.layer removeAnimationForKey:@"opacity"];
            [UIView performWithoutAnimation:^{ overlay.view.alpha = 1.0; }];
        }
        if (stateChanged && gCurrentPage != 0 && !gEditModeActive && gPagingEnabled && !PACCLandscapeNow()) {
            UIView *rind = [overlay.view viewWithTag:kPageIndicatorTag];
            UIViewController *rcol = ModuleCollection(overlay);
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            if (rcol.view) {
                [rcol.view.layer removeAllAnimations];
                [PACC.shared snapToFirstPageForOverlay:overlay];
            } else {
                gCurrentPage = 0;
            }
            if ([rind isKindOfClass:CCAPageIndicator.class]) {
                ((CCAPageIndicator *)rind).currentPage = 0;
                [(CCAPageIndicator *)rind layoutButtons];
            }
            gPageAnimating = NO;
            [PACC.shared applyHeaderMaterialHidden:NO forOverlay:overlay];
            [PACC.shared adjustStatusBarForOverlay:overlay];
            [PACC.shared syncModuleVisibilityForOverlay:overlay animated:NO];
            [CATransaction commit];
            PACCSizeLog(@"reset to main page on present (teleport)");
        }
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
        PACCSizeLog([NSString stringWithFormat:@"state3 closing %d last %ld", (int)closing, (long)(lastState ? lastState.integerValue : -1)]);
        if (closing) { gPACCDismissDir = 0.0; PACCPollDismiss(overlay, ++gPACCDismissToken, 0.0); }
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
        if (gPagingEnabled && !gCCAModuleExpanded && !PACCLandscapeNow()) {
            UIView *pind = [overlay.view viewWithTag:kPageIndicatorTag];
            if (!pind) {
                [PACC.shared installPageIndicatorOnOverlay:overlay];
                pind = [overlay.view viewWithTag:kPageIndicatorTag];
            }
            if (pind && (pind.hidden || pind.alpha < 0.99) && pind.layer.animationKeys.count == 0) {
                pind.hidden = NO;
                pind.alpha = 1.0;
                pind.transform = CGAffineTransformIdentity;
            }
        }
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

%hook CCUIContentModuleContainerView
- (void)layoutSubviews {
    %orig;
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

static void PACCApplyExpandShiftEx(BOOL animated) {
    UIViewController *ovc = OverlayIn(UIApplication.sharedApplication.keyWindow.rootViewController);
    UIViewController *col = ovc ? ModuleCollection(ovc) : nil;
    if (!col.view) return;
    CATransform3D t = col.view.layer.sublayerTransform;
    CATransform3D w = PACCDesiredTransform(t, col.view, PACCLandShiftNow(), -(CGFloat)gCurrentPage * PageSpan());
    if (PACCTransformClose(t, w)) return;
    if (!animated) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        col.view.layer.sublayerTransform = w;
        [CATransaction commit];
        return;
    }
    [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseIn | UIViewAnimationOptionAllowUserInteraction animations:^{
        col.view.layer.sublayerTransform = w;
    } completion:nil];
}
static void PACCApplyExpandShift(void) { PACCApplyExpandShiftEx(YES); }

// On tall (notched / fullscreen) resolutions the stock layout parks the expanded
// card off-position (Music hit the bottom edge). Align its top with the first row.
static void PACCCenterExpanded(UIViewController *vc, int attempt) {
    if (!gEnabled || !vc || !vc.view.window) return;
    if (CGRectGetHeight(UIScreen.mainScreen.bounds) < 800.0 || PACCLandscapeNow()) return;
    SEL es = NSSelectorFromString(@"isExpanded");
    BOOL ex = [vc respondsToSelector:es] ? ((BOOL (*)(id, SEL))objc_msgSend)(vc, es) : NO;
    if (ex) {
        UIViewController *content = nil;
        SEL cs = NSSelectorFromString(@"contentViewController");
        if ([vc respondsToSelector:cs]) content = ((id (*)(id, SEL))objc_msgSend)(vc, cs);
        UIView *wrap = content.view.superview;
        if (wrap && wrap.window) {
            CGRect r = [wrap convertRect:wrap.bounds toView:nil];
            if (r.size.height > 300.0) {
                if (gPACCExpandTop < 0.0) {
                    UIViewController *ov0 = OverlayIn(UIApplication.sharedApplication.keyWindow.rootViewController);
                    gPACCExpandTop = PACCGridTopY(ov0) - gPACCExpandShift;
                }
                CGFloat top0 = gPACCExpandTop;
                if (top0 < 20.0 || top0 > CGRectGetHeight(wrap.window.bounds) * 0.5) return;
                CGFloat dy = top0 - CGRectGetMinY(r);
                if (fabs(dy) > 1.0) {
                    gPACCExpandShift += dy;
                    PACCSizeLog([NSString stringWithFormat:@"center expanded dy %.1f total %.1f rect %@", dy, gPACCExpandShift, NSStringFromCGRect(r)]);
                    PACCApplyExpandShift();
                }
            }
        }
    }
    if (attempt < 4) {
        __weak UIViewController *wv = vc;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            PACCCenterExpanded(wv, attempt + 1);
        });
    }
}

%hook CCUIContentModuleContainerViewController
- (void)viewDidLayoutSubviews {
    %orig;
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
            PACCCenterExpanded(vc0, 0);
        } else if (!exp0 && sExpandedVC == vc0) {
            sExpandedVC = nil;
            gCCAModuleExpanded = NO;
            gPACCExpandQuietUntil = CACurrentMediaTime() + 1.5;
            UIViewController *ovc = OverlayIn(UIApplication.sharedApplication.keyWindow.rootViewController);
            PACCNoteExpandedModule(vc0, NO, ovc);
            PACCSizeLog(@"expanded module closed (container layout)");
            gPACCExpandTop = -1.0;
            if (fabs(gPACCExpandShift) > 0.01) { gPACCExpandShift = 0.0; PACCApplyExpandShift(); }
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
        const CGFloat kWant = 600.0;
        const CGFloat kWantW = 342.0;
        if (gEnabled && exp && wrap && wrap != me.view && CGAffineTransformIsIdentity(wrap.transform) &&
            me.view.bounds.size.width < me.view.bounds.size.height &&
            wrap.bounds.size.height > 300.0 &&
            (wrap.bounds.size.height < kWant - 0.5 || wrap.bounds.size.width > kWantW + 0.5)) {
            CGRect f = wrap.frame;
            if (f.size.height < kWant - 0.5) {
                CGFloat dh = kWant - f.size.height;
                f.origin.y -= dh * 0.5;
                f.size.height = kWant;
            }
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
    NSString *note = [NSString stringWithFormat:@"expanded height: orig %.1f -> 600, screen %.1f", orig, [UIScreen mainScreen].bounds.size.height];
    if (![note isEqualToString:lastNote]) { lastNote = note; PACCSizeLog(note); }
    return 600.0;
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