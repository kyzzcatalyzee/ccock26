#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <math.h>
#import <MediaPlayer/MediaPlayer.h>
#import <AVFoundation/AVFoundation.h>

#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wunused-variable"
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

#ifdef __cplusplus
extern "C" {
#endif

extern const NSInteger PACCTagConnectivityCluster;
extern const NSInteger PACCTagMediaButtonMaterial;
extern const NSInteger kPageIndicatorTag;
extern const NSInteger kQuickAccessTag;
extern const NSInteger kMediaPlayerTag;
extern const NSInteger kPromoPageTag;

extern const void *PACCKeyCompactRadius;
extern const void *PACCKeyMediaMode;
extern const void *PACCKeyMiniGlyphBaseSize;

extern BOOL gEnabled;
extern BOOL gQuickAccessButtonsEnabled;
extern BOOL gSliderBounceEnabled;
extern BOOL gCC18Glyphs;
extern BOOL gCC18Animated;
extern BOOL gPageCascade;
extern BOOL gPagingEnabled;
extern BOOL gHapticsEnabled;
extern BOOL gExperimentalPagingEnabled;
extern BOOL gPageAnimating;
extern BOOL gPagerScrubbing;
extern BOOL gCCAModuleExpanded;
extern CFTimeInterval gPACCExpandQuietUntil;
extern CGFloat gPACLandSc, gPACLandMc, gPACLandTop;
extern BOOL gPACLandHave;
extern CGFloat gPACLandOy0;
#define kPACLandFrameScale 1
void PACCLandBeginPass(UIView *cv);
void PACCLandEndPass(UIView *cv);
extern NSInteger gCurrentPage;
extern NSString *const kReloadNotification;
extern BOOL gEditModeEnabled;
extern BOOL gEditModeActive;
extern CGFloat gPACCPortScale;
extern BOOL gCircularModulesEnabled;
extern BOOL gPromoPageEnabled;
extern BOOL gPACCRevealAll;
extern BOOL gMediaPageEnabled;
void PACCLoadEditPrefs(void);
NSUInteger PACCUserPageCount(void);
NSInteger PACCModulePageForIdentifier(NSString *mid);

CGFloat calculatedRadius(CGRect visibleRect, CGFloat radius);
void LoadPrefs(void);
void Haptic(void);
CGFloat PageSpan(void);

UIViewController *OverlayIn(UIViewController *root);
BOOL IsModuleController(UIViewController *controller);
BOOL IsConnectivityController(UIViewController *controller);
NSArray<UIViewController *> *ModuleControllers(UIViewController *root);
UIViewController *ModuleCollection(UIViewController *overlay);
UIViewController *ConnectivityChild(UIViewController *controller, NSString *className);
UIView *PACCViewIvar(id object, const char *name);

UIView *PACCModuleAncestor(UIView *view);
CGFloat PACCModuleCornerRadius(CGSize size);
CGFloat PACCRadiusForModule(UIView *module);
UIView *PACCAncestor(UIView *view, NSString *className);
NSString *PACCMediaMode(UIView *view);
NSArray *PACCMediaMaterialFilters(UIView *view);
void PACCResizeMediaRoutingGlyph(UIView *button);
void PACCConfigureMedia(UIView *view);
UIViewController *PACCConnectivityChild(UIViewController *controller, NSString *className);
UIView *PACCModuleMaterial(void);
UIImage *PACCGlyphPNG(NSString *name);
NSArray *PACCConnectivityVibrantFilters(UIView *root);
void PACCScaleMiniGlyphs(UIView *root, CGFloat scale);
UIImage *PACCBundledSymbol(NSString *name, UIColor *color, BOOL hierarchical);
void PACCConfigureConnectivity(UIViewController *controller);
CGRect PACCVisibleModuleBounds(UIViewController *overlay);

NSInteger PACCMediaPageIndex(void);
NSInteger PACCPromoPageIndex(void);
NSUInteger PACCBasePageCount(void);
void PACCSetGridMetrics(CGFloat cell, CGFloat gap);
CGFloat PACCGridCell(void);
CGFloat PACCGridGap(void);
int PACCBigKind(NSString *mid);
BOOL PACCBigSizeAllowed(NSString *mid, NSUInteger w, NSUInteger h);
void PACCBigSetToggleMid(UIView *v, NSString *mid);
UIControl *PACCBigFindRound(UIView *apple, NSString *key);
void PACCBigSnapSize(NSString *mid, NSInteger wantW, NSInteger wantH, NSUInteger *outW, NSUInteger *outH);
void PACCBigConfigureExpanded(UIViewController *controller, BOOL expanded);
void PACCBigStripContainer(UIView *container);
UIView *PACCBigNewClone(int kind);
void PACCBigConfigureClone(UIView *v, int kind, NSUInteger w, NSUInteger h, UIView *apple);
int PACCPageContentKind(NSUInteger page);
void PACCCrumb(const char *label);
void PACCClonesRelayout(UIView *collectionView);
void PACCCrashLog(NSString *line);
void PACCSizeLog(NSString *line);
void PACCLandscapeRefresh(UIViewController *ov);
void PACCSyncClones(UIViewController *overlay, BOOL animated);
void PACCNoteExpandedModule(id module, BOOL open, UIViewController *ov);
void PACCLogCloseSamples(id module, UIViewController *ov);
void PACCBigStyle(UIViewController *m, NSString *mid, NSUInteger w, NSUInteger h, BOOL expanded);
BOOL PACCLIQIsActive(void);
BOOL PACCLIQGlassOn(void);
BOOL PACCLIQApplyGlass(UIView *host, CGFloat radius);
void PACCLIQSetFixedBlur(UIView *host, CGFloat blur);
void PACBigFixLGRadius(UIView *g, CGFloat r);
void PACBigRefreshLG(UIView *root);
#define kPACConnExtra 45.0
#define kPACConnW 330.0
#define kPACLandShift (-28.0)
static inline BOOL PACCLandscapeNow(void) {
    CGSize sz = UIScreen.mainScreen.bounds.size;
    return sz.width > sz.height;
}

static inline void PACCLandFit(UIView *cv, CGFloat *outS, CGFloat *outTx) {
    static CGFloat lastS = 1.0, lastTx = 0.0;
    *outS = 1.0; *outTx = 0.0;
    if (!PACCLandscapeNow() || !cv) return;
    CGFloat mn = CGFLOAT_MAX, mx = -CGFLOAT_MAX;
    BOOL wide = NO;
    for (UIView *sv in cv.subviews) {
        if (sv.hidden || sv.alpha < 0.01) continue;
        if (![NSStringFromClass(sv.class) containsString:@"ContentModuleContainerView"]) continue;
        CGRect f = sv.frame;
        if (CGRectGetWidth(f) < 2.0) continue;
        if (CGRectGetWidth(f) > 360.0) { wide = YES; continue; }
        mn = MIN(mn, CGRectGetMinX(f));
        mx = MAX(mx, CGRectGetMaxX(f));
    }
    if (wide || mn > mx) { *outS = lastS; *outTx = lastTx; return; }
    CGFloat vw = cv.bounds.size.width;
    CGFloat gw = mx - mn;
    if (vw < 100.0 || gw < 100.0) return;
    CGFloat sc = MIN(1.0, (vw - 60.0) / gw);
    CGFloat gc = (mn + mx) * 0.5;
    CGFloat tx = -sc * (gc - vw * 0.5);
    lastS = sc; lastTx = tx;
    *outS = sc; *outTx = tx;
}
#define kPACLandMargin 44.0
static inline CGFloat PACCLandShiftNow(void) {
    return PACCLandscapeNow() ? kPACLandShift : 0.0;
}
static inline void PACCLandCollect(UIView *v, int depth, CGPoint off, CGFloat limitY, CGFloat *mn, CGFloat *mx, CGFloat *top) {
    for (UIView *s in v.subviews) {
        CGRect f = s.frame;
        f.origin.x += off.x;
        f.origin.y += off.y;
        if ([NSStringFromClass(s.class) containsString:@"ContentModuleContainerView"]) {
            if (CGRectGetWidth(f) < 2.0 || CGRectGetWidth(f) > 360.0) continue;
            if (CGRectGetMinY(f) >= limitY) continue;
            *mn = MIN(*mn, CGRectGetMinX(f));
            *mx = MAX(*mx, CGRectGetMaxX(f));
            *top = MIN(*top, CGRectGetMinY(f));
        } else if (depth > 0) {
            PACCLandCollect(s, depth - 1, f.origin, limitY, mn, mx, top);
        }
    }
}
static inline BOOL PACCLandMeasure(UIView *cv, CGFloat *outSc, CGFloat *outMc, CGFloat *outTop) {
    if (kPACLandFrameScale) {
        *outSc = gPACLandSc; *outMc = gPACLandMc; *outTop = gPACLandTop;
        return gPACLandHave;
    }
    static CGFloat cSc = 1.0, cMc = 0.0, cTop = 0.0;
    static BOOL have = NO;
    if (have && (gCCAModuleExpanded || CACurrentMediaTime() < gPACCExpandQuietUntil)) {
        *outSc = cSc; *outMc = cMc; *outTop = cTop;
        return YES;
    }
    CGFloat mn = CGFLOAT_MAX, mx = -CGFLOAT_MAX, top = CGFLOAT_MAX;
    PACCLandCollect(cv, 1, CGPointZero, PageSpan() * 0.9, &mn, &mx, &top);
    CGFloat W = cv.window ? cv.window.bounds.size.width : UIScreen.mainScreen.bounds.size.width;
    if (mn <= mx) {
        CGFloat cw = mx - mn;
        CGFloat avail = W - 2.0 * kPACLandMargin;
        cSc = (cw > avail && cw > 1.0) ? avail / cw : 1.0;
        cMc = (mn + mx) * 0.5;
        cTop = top;
        have = YES;
    }
    *outSc = cSc;
    *outMc = cMc;
    *outTop = cTop;
    return have;
}
static inline CGPoint PACCLandOrigin(UIView *cv) {
    CGRect b = cv.bounds;
    CGFloat cx = b.origin.x + b.size.width * 0.5;
    CGFloat cy = b.origin.y + b.size.height * 0.5;
    CGPoint p = CGPointMake(cv.center.x - cx, cv.center.y - cy);
    if (cv.superview && cv.window) return [cv.superview convertPoint:p toView:cv.window];
    return p;
}
static inline CATransform3D PACCLandTransform(UIView *cv, CGFloat shift, CGFloat offset) {
    CATransform3D t = CATransform3DIdentity;
    t.m42 = shift + offset;
    if (!PACCLandscapeNow() || !cv || !cv.window) return t;
    if (kPACLandFrameScale) {
        t.m42 = offset;
        return t;
    }
    CGFloat sc = 1.0, mc = 0.0, top = 0.0;
    if (!PACCLandMeasure(cv, &sc, &mc, &top)) return t;
    CGFloat W = cv.window.bounds.size.width;
    CGRect b = cv.bounds;
    CGFloat cx = b.origin.x + b.size.width * 0.5;
    CGFloat cy = b.origin.y + b.size.height * 0.5;
    CGPoint o = PACCLandOrigin(cv);
    t.m11 = sc;
    t.m22 = sc;
    t.m41 = W * 0.5 - o.x - cx - sc * (mc - cx);
    t.m42 = shift + (1.0 - sc) * (top - cy) + sc * offset;
    {
        static CGFloat lastLogS = -1.0, lastLogX = 0.0, lastLogY = 0.0;
        if (fabs(lastLogS - sc) > 0.001 || fabs(lastLogX - t.m41) > 0.5 || fabs(lastLogY - o.y) > 0.5) {
            lastLogS = sc; lastLogX = t.m41; lastLogY = o.y;
            PACCSizeLog([NSString stringWithFormat:@"landscape fit mc %.1f top %.1f W %.1f ox %.1f oy %.1f cx %.1f cy %.1f scale %.3f tx %.1f",
                         mc, top, W, o.x, o.y, cx, cy, sc, t.m41]);
        }
    }
    return t;
}
#define kPACPortScaleOn 1
static CGFloat gPACCPortTarget = -1.0;
static CGFloat gPACCPortFix = 0.0;
static inline BOOL PACCPortMeasure(UIView *cv, CGFloat *outSc, CGFloat *outMc, CGFloat *outTop, CGFloat *outRaise) {
    static CGFloat cSc = 1.0, cMc = 0.0, cTop = 0.0, cRaise = 0.0;
    static BOOL have = NO;
    if (!cv || !cv.window) {
        if (!have) return NO;
    } else {
        if (MIN(cv.window.bounds.size.width, cv.window.bounds.size.height) >= 422.0) return NO;
        CGFloat mn = CGFLOAT_MAX, mx = -CGFLOAT_MAX, top = CGFLOAT_MAX;
        PACCLandCollect(cv, 1, CGPointZero, PageSpan() * 0.9, &mn, &mx, &top);
        if (mn <= mx) {
            {
                static CGFloat bestTop = CGFLOAT_MAX;
                if (top >= 0.0 && top < 150.0 && top < bestTop) bestTop = top;
                if (bestTop != CGFLOAT_MAX) top = bestTop;
            }
            CGFloat H = cv.window.bounds.size.height;
            CGPoint o = PACCLandOrigin(cv);
            CGFloat topWin = o.y + top;
            CGFloat targetTop = (topWin > 48.0) ? MAX(48.0, topWin - 20.0) : topWin;
            CGFloat rowsH = 8.0 * PACCGridCell() + 7.0 * PACCGridGap();
            CGFloat sc = MIN(0.97, (H - 12.0 - targetTop) / rowsH);
            if (MIN(cv.window.bounds.size.width, H) < 422.0) { sc = 0.91; targetTop = 88.0; }
            cSc = MAX(0.6, MIN(1.0, sc));
            {
                static CGFloat lastLogTop = -999.0, lastLogSc = -1.0;
                if (fabs(lastLogTop - topWin) > 0.5 || fabs(lastLogSc - cSc) > 0.001) {
                    lastLogTop = topWin; lastLogSc = cSc;
                    PACCSizeLog([NSString stringWithFormat:@"portrait fit H %.1f oy %.1f top %.1f topWin %.1f target %.1f rowsH %.1f cvH %.1f scale %.3f",
                                 H, o.y, top, topWin, targetTop, rowsH, cv.bounds.size.height, cSc]);
                }
            }
            cMc = (mn + mx) * 0.5;
            cTop = top;
            cRaise = targetTop - topWin;
            gPACCPortTarget = targetTop;
            have = YES;
        }
    }
    *outSc = cSc; *outMc = cMc; *outTop = cTop; *outRaise = cRaise;
    return have;
}
static inline CATransform3D PACCPortTransform(CATransform3D cur, UIView *cv, CGFloat shift, CGFloat offset) {
    cur.m11 = 1.0;
    cur.m22 = 1.0;
    cur.m41 = 0.0;
    cur.m42 = shift + offset;
    cur.m43 = 0.0;
    gPACCPortScale = 1.0;
    if (!cv || !cv.window || !kPACPortScaleOn) return cur;
    CGFloat sc = 1.0, mc = 0.0, top = 0.0, raise = 0.0;
    if (!PACCPortMeasure(cv, &sc, &mc, &top, &raise)) return cur;
    gPACCPortScale = sc;
    CGRect b = cv.bounds;
    CGFloat cx = b.origin.x + b.size.width * 0.5;
    CGFloat cy = b.origin.y + b.size.height * 0.5;
    if (fabs(offset) < 0.5 && gPACCPortTarget > 0.0) {
        CGFloat actualTop = CGFLOAT_MAX;
        for (UIView *sv in cv.subviews) {
            if (sv.hidden || sv.alpha < 0.01) continue;
            CGRect fr = sv.frame;
            if (fr.size.width < 20.0 || fr.size.width > 360.0 || fr.origin.y > PageSpan() * 0.9 || fr.origin.y < -2.0) continue;
            CGRect wr = [cv convertRect:fr toView:nil];
            if (wr.origin.y < actualTop) actualTop = wr.origin.y;
        }
        if (actualTop != CGFLOAT_MAX && actualTop > -400.0 && actualTop < 600.0) {
            CGFloat err = gPACCPortTarget - actualTop;
            static CFTimeInterval lastFixT = 0.0;
            CFTimeInterval nowT = CACurrentMediaTime();
            if (fabs(err) > 0.75 && nowT - lastFixT > 0.03) {
                lastFixT = nowT;
                gPACCPortFix = MAX(-300.0, MIN(300.0, gPACCPortFix + err));
                PACCSizeLog([NSString stringWithFormat:@"portrait fix actualTop %.1f target %.1f fix %.1f", actualTop, gPACCPortTarget, gPACCPortFix]);
            }
        }
    }
    cur.m11 = sc;
    cur.m22 = sc;
    cur.m41 = (1.0 - sc) * (mc - cx);
    cur.m42 = shift + (1.0 - sc) * (top - cy) + raise + sc * offset + gPACCPortFix;
    return cur;
}
#define PACSS() (PACCLandscapeNow() ? 1.0 : gPACCPortScale)
static inline CGRect PACCSubRect(UIView *cv, CATransform3D sub, CGRect r) {
    CGRect b = cv.bounds;
    CGFloat cx = b.origin.x + b.size.width * 0.5;
    CGFloat cy = b.origin.y + b.size.height * 0.5;
    return CGRectMake(cx + sub.m11 * (r.origin.x - cx) + sub.m41, cy + sub.m22 * (r.origin.y - cy) + sub.m42,
                      r.size.width * sub.m11, r.size.height * sub.m22);
}
static inline CATransform3D PACCPageTranslate(CATransform3D base, CGFloat off) {
    return CATransform3DTranslate(base, 0.0, off, 0.0);
}
static inline CATransform3D PACCDesiredTransform(CATransform3D cur, UIView *cv, CGFloat shift, CGFloat offset) {
    if (PACCLandscapeNow()) return PACCLandTransform(cv, shift, offset);
    return PACCPortTransform(cur, cv, shift, offset);
}
static inline BOOL PACCTransformClose(CATransform3D a, CATransform3D b) {
    return fabs(a.m11 - b.m11) < 0.002 && fabs(a.m22 - b.m22) < 0.002 &&
           fabs(a.m41 - b.m41) < 0.5 && fabs(a.m42 - b.m42) < 0.5;
}
static inline CGRect PACCLandUnmap(UIView *cv, CGRect screenRect, NSInteger page) {
    if (kPACLandFrameScale) {
        if (!cv || !cv.window) return screenRect;
        CATransform3D ft = PACCLandTransform(cv, kPACLandShift, -(CGFloat)page * PageSpan());
        CGPoint fo = PACCLandOrigin(cv);
        return CGRectMake(screenRect.origin.x - fo.x - ft.m41, screenRect.origin.y - fo.y - ft.m42, screenRect.size.width, screenRect.size.height);
    }
    CGFloat sc = 1.0, mc = 0.0, top = 0.0;
    if (!cv || !cv.window || !PACCLandMeasure(cv, &sc, &mc, &top) || sc < 0.1) return screenRect;
    CATransform3D t = PACCLandTransform(cv, kPACLandShift, -(CGFloat)page * PageSpan());
    CGRect b = cv.bounds;
    CGFloat cx = b.origin.x + b.size.width * 0.5;
    CGFloat cy = b.origin.y + b.size.height * 0.5;
    CGPoint o = PACCLandOrigin(cv);
    CGFloat x = cx + (screenRect.origin.x - o.x - cx - t.m41) / sc;
    CGFloat y = cy + (screenRect.origin.y - o.y - cy - t.m42) / sc;
    return CGRectMake(x, y, screenRect.size.width / sc, screenRect.size.height / sc);
}
static inline CGRect PACCBigOutsetS(int kind, CGRect f, CGFloat ss) {
    CGFloat dx = (kind == 1) ? MAX(0.0, (f.size.width - kPACConnW * ss) * 0.5) : 5.0 * ss;
    CGFloat gap = PACCGridGap() * ss;
    CGFloat step = (PACCGridCell() + PACCGridGap()) * ss;
    CGRect r = f;
    if (r.size.height > 7.5 * step - gap) r.size.height = 7.0 * step - gap - kPACConnExtra * ss;
    return CGRectInset(r, dx, -kPACConnExtra * ss * 0.5);
}
static inline CGRect PACCBigOutset(int kind, CGRect f) {
    return PACCBigOutsetS(kind, f, 1.0);
}
void PACCLIQSpecularFade(UIView *host, BOOL hidden, CFTimeInterval dur, CFTimeInterval delay);
BOOL PACBigLGGlass(UIView *host, CGFloat radius);
BOOL PACCLIQStyleDarkEdge(CAGradientLayer *g);
BOOL PACCLIQStyleRim(CAGradientLayer *g);

#ifdef __cplusplus
}
#endif

@interface MTMaterialLayer : CALayer
@property (nonatomic, copy, readwrite) NSString *recipeName;
@property (atomic, assign, readonly) CGRect visibleRect;
@end

@interface CALayer ()
@property (atomic, assign, readwrite) id unsafeUnretainedDelegate;
@end

@interface MRUNowPlayingView : UIView @end
@interface MRUArtworkView : UIView @end
@interface MRUNowPlayingHeaderView : UIView @end
@interface MRUNowPlayingLabelView : UIView @end
@interface MRUNowPlayingTransportControlsView : UIView @end
@interface MRUTransportButton : UIButton @end

@interface CCUIModuleCollectionView : UIScrollView @end

@interface PAnim : NSObject
+ (void)popViews:(NSArray<UIView *> *)views;
@end

@interface CCAPageIndicator : UIView
@property (nonatomic, weak) UIViewController *overlay;
@property (nonatomic) NSUInteger currentPage;
@property (nonatomic) NSUInteger pageCount;
@property (nonatomic, assign) BOOL transitionActive;
@property (nonatomic, assign) BOOL scrubbingActive;
@property (nonatomic, assign, readonly) BOOL scrubbing;
- (void)setCurrentPage:(NSUInteger)page forOverlay:(UIViewController *)overlay;
- (void)layoutButtons;
- (void)captureCollectionBase;
@end

@interface CCAQuickAccessHost : UIView
@end

@interface CCAMediaPlayerView : UIView
- (void)setupUI;
- (void)refresh;
- (void)resetForPresentation;
- (void)fadeIn;
- (void)fadeOut;
- (void)slideOut;
- (void)slideOffScreen;
@end

@interface CCAPromoPageView : UIView
- (void)refreshFact;
@end

@interface PACC : NSObject
+ (instancetype)shared;
- (void)installOnOverlay:(UIViewController *)overlay;
- (void)syncModuleVisibilityForOverlay:(UIViewController *)overlay;
- (void)syncModuleVisibilityForOverlay:(UIViewController *)overlay animated:(BOOL)animated;
- (void)restoreModuleVisibilityForOverlay:(UIViewController *)overlay;
- (void)applyHeaderMaterialHidden:(BOOL)hidden forOverlay:(UIViewController *)overlay;
- (void)adjustStatusBarForOverlay:(UIViewController *)overlay;
- (void)hideHairlinesForOverlay:(UIViewController *)overlay;
- (void)animateElementsInForOverlay:(UIViewController *)overlay;
- (void)animateElementsOutForOverlay:(UIViewController *)overlay;
- (void)layoutPageIndicatorForOverlay:(UIViewController *)overlay;
- (void)updateQuickAccessButtonsForOverlay:(UIViewController *)overlay;
- (void)installPageIndicatorOnOverlay:(UIViewController *)overlay;
- (void)installMediaPlayerOnCollectionView:(UIScrollView *)collectionView;
- (void)layoutMediaPlayerForCollectionView:(UIScrollView *)collectionView;
- (void)installPromoPageOnCollectionView:(UIScrollView *)collectionView;
- (void)layoutPromoPageForCollectionView:(UIScrollView *)collectionView;
- (CGFloat)topInsetForOverlay:(UIViewController *)overlay;
- (UIButton *)makeRoundButtonWithSymbol:(NSString *)symbolName tag:(NSInteger)tag;
@end