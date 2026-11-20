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
extern NSInteger gCurrentPage;
extern NSString *const kReloadNotification;
extern BOOL gEditModeEnabled;
extern BOOL gEditModeActive;
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
static inline void PACCLandCollect(UIView *v, int depth, CGPoint off, CGFloat *mn, CGFloat *mx, CGFloat *top) {
    for (UIView *s in v.subviews) {
        if (s.hidden || s.alpha < 0.01) continue;
        CGRect f = s.frame;
        f.origin.x += off.x;
        f.origin.y += off.y;
        if ([NSStringFromClass(s.class) containsString:@"ContentModuleContainerView"]) {
            if (CGRectGetWidth(f) < 2.0 || CGRectGetWidth(f) > 360.0) continue;
            *mn = MIN(*mn, CGRectGetMinX(f));
            *mx = MAX(*mx, CGRectGetMaxX(f));
            *top = MIN(*top, CGRectGetMinY(f));
        } else if (depth > 0) {
            PACCLandCollect(s, depth - 1, f.origin, mn, mx, top);
        }
    }
}
static inline CATransform3D PACCLandTransform(UIView *cv, CGFloat baseY) {
    CATransform3D t = CATransform3DIdentity;
    t.m42 = baseY;
    if (!PACCLandscapeNow() || !cv || !cv.window) return t;
    CGFloat mn = CGFLOAT_MAX, mx = -CGFLOAT_MAX, top = CGFLOAT_MAX;
    PACCLandCollect(cv, 1, CGPointZero, &mn, &mx, &top);
    if (mn > mx) return t;
    CGFloat W = cv.window.bounds.size.width;
    CGFloat cw = mx - mn;
    CGFloat avail = W - 2.0 * kPACLandMargin;
    CGFloat sc = (cw > avail && cw > 1.0) ? avail / cw : 1.0;
    CGRect b = cv.bounds;
    CGFloat cx = b.origin.x + b.size.width * 0.5;
    CGFloat cy = b.origin.y + b.size.height * 0.5;
    CGFloat ox = [cv convertPoint:CGPointZero toView:cv.window].x;
    CGFloat mc = (mn + mx) * 0.5;
    t.m11 = sc;
    t.m22 = sc;
    t.m41 = W * 0.5 - ox - cx - sc * (mc - cx);
    t.m42 = baseY + (1.0 - sc) * (top - cy);
    {
        static CGFloat lastLogS = -1.0, lastLogX = 0.0;
        if (fabs(lastLogS - sc) > 0.001 || fabs(lastLogX - t.m41) > 0.5) {
            lastLogS = sc; lastLogX = t.m41;
            PACCSizeLog([NSString stringWithFormat:@"landscape fit mn %.1f mx %.1f top %.1f W %.1f ox %.1f cx %.1f scale %.3f tx %.1f ty %.1f",
                         mn, mx, top, W, ox, cx, sc, t.m41, t.m42]);
        }
    }
    return t;
}
static inline BOOL PACCTransformClose(CATransform3D a, CATransform3D b) {
    return fabs(a.m11 - b.m11) < 0.002 && fabs(a.m22 - b.m22) < 0.002 &&
           fabs(a.m41 - b.m41) < 0.5 && fabs(a.m42 - b.m42) < 0.5;
}
static inline CATransform3D PACCDesiredTransform(CATransform3D cur, UIView *cv, CGFloat baseY) {
    if (PACCLandscapeNow()) return PACCLandTransform(cv, baseY);
    cur.m11 = 1.0;
    cur.m22 = 1.0;
    cur.m41 = 0.0;
    cur.m42 = baseY;
    cur.m43 = 0.0;
    return cur;
}
static inline CGRect PACCBigOutset(int kind, CGRect f) {
    CGFloat dx = (kind == 1) ? MAX(0.0, (f.size.width - kPACConnW) * 0.5) : 5.0;
    return CGRectInset(f, dx, -kPACConnExtra * 0.5);
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