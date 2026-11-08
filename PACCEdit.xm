#import "PACC.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <math.h>

#ifdef __cplusplus
extern "C" {
#endif
BOOL PACCLIQIsActive(void);
id PACCLIQBuildGlassFilter(void);
#ifdef __cplusplus
}
#endif

typedef struct CCUILayoutSize  { NSUInteger width;  NSUInteger height; } CCUILayoutSize;
typedef struct CCUILayoutPoint { NSUInteger x;      NSUInteger y;      } CCUILayoutPoint;
typedef struct CCUILayoutRect  { CCUILayoutPoint origin; CCUILayoutSize size; } CCUILayoutRect;
typedef struct { NSUInteger c, r, w, h; } PACRect;

static NSUInteger kPACCols = 4;
static NSUInteger kPACRows = 8;
static NSUInteger kPACStride = 8;   // rows per page in the stored origin (visible rows + spacer rows)
static NSUInteger gPACEditEpoch = 0;
static CFTimeInterval gEditModeEnteredAt = 0;
static NSInteger gPACLastPresentationState = 1;
static CGFloat    kPACCell = 67.0;
static CGFloat    kPACgap  = 12.0;
static CGFloat    kPACStep = 79.0;

BOOL gEditModeEnabled = YES;
BOOL gEditModeActive  = NO;

static NSMutableDictionary<NSString *, NSArray<NSNumber *> *> *gEditOrigins;
static NSMutableDictionary<NSString *, NSArray<NSNumber *> *> *gEditSizes;
static NSMutableDictionary<NSString *, NSArray<NSNumber *> *> *gEditBaseSizes;

static NSString *gPACPendingResizeID = nil;
static CCUILayoutSize gPACPendingResizeSize = {0, 0};
static NSTimeInterval gPACPendingResizeLastTouch = 0;

static Class kClsCCUIButtonModuleView;
static Class kClsCCUICAPackageView;
static Class kClsCABackdropLayer;

static const NSInteger kPACBorderTag       = 182000;
static const NSInteger kPACRemoveTag       = 182001;
static const NSInteger kPACResizeTag       = 182002;
static const NSInteger kPACHintTag         = 182003;
static const NSInteger kPACProxyTag        = 182004;
static const NSInteger kPACResetTag        = 182005;
static const NSInteger kPACShieldTag       = 182006;
static const NSInteger kPACProxyShadowTag  = 182007;
static const NSInteger kPACAddTag          = 182008;
static const NSInteger kPACPickerTag       = 182009;
static const NSInteger kPACToastTag        = 182010;
static const NSInteger kPACPageAddTag      = 182011;
static const NSInteger kPACLayersTag       = 182012;

static const void *kPACBorderKey   = &kPACBorderKey;
static const void *kPACRemoveKey   = &kPACRemoveKey;
static const void *kPACResizeKey   = &kPACResizeKey;
static const void *kPACPresKey     = &kPACPresKey;
static const void *kPACMidKey      = &kPACMidKey;
static const void *kPACStartSzKey  = &kPACStartSzKey;
static const void *kPACGestKey     = &kPACGestKey;
static const void *kPACDragSrcKey  = &kPACDragSrcKey;
static const void *kPACDragProxyKey= &kPACDragProxyKey;
static const void *kPACDragGrabKey = &kPACDragGrabKey;
static const void *kPACOwnGestureKey = &kPACOwnGestureKey;
static const void *kPACDisabledGesturesKey = &kPACDisabledGesturesKey;
static const void *kPACResizedSetKey = &kPACResizedSetKey;
static const void *kPACLastCellKey     = &kPACLastCellKey;
static const void *kPACOrigLayoutKey   = &kPACOrigLayoutKey;
static const void *kPACLastRadiusKey   = &kPACLastRadiusKey;
static const void *kPACLastPresKey     = &kPACLastPresKey;
static const void *kPACOrigRadiiKey    = &kPACOrigRadiiKey;
static const void *kPACLandscapeCleanKey = &kPACLandscapeCleanKey;
static const void *kPACIconPinKey = &kPACIconPinKey;
static const CGFloat kPACBorderWidth = 4.0;
static const CGFloat kPACBorderInset = 3.5;
static CFTimeInterval gPACRotationQuietUntil = 0;

static NSString *PACMid(UIViewController *vc);
static CGRect PACVisibleFrame(UIViewController *m, UIViewController *overlay);
static UIViewController *PACModuleAtPoint(CGPoint pt, UIViewController *overlay);
static CGPoint PACGridBase(UIViewController *overlay);
static NSUInteger PACVisibleRowCap(UIViewController *ov);
static NSArray<NSNumber *> *PACKnownBaseSize(NSString *mid);
static void PACEnsureBaseSize(UIViewController *m, UIViewController *ov);
static void PACEffectiveSize(NSString *mid, NSUInteger *w, NSUInteger *h);
static void PACPresentationSize(NSString *mid, NSUInteger *w, NSUInteger *h);
static BOOL PACModuleSupportsResizing(NSString *mid);
static CCUILayoutSize PACResizeCandidate(NSString *mid, NSUInteger startW, NSUInteger startH, CGPoint translation);
static BOOL PACSizeAllowed(NSUInteger w, NSUInteger h);
static BOOL PACSizeAllowedFor(NSString *mid, NSUInteger w, NSUInteger h);
static BOOL PACDragSizeAllowedForModule(NSString *mid, NSUInteger w, NSUInteger h);
static NSString *PACPrettyNameForModule(UIViewController *m);
static BOOL PACRectsOverlap(PACRect a, PACRect b);
static BOOL PACFindFreeCellFor(NSDictionary<NSString *, NSValue *> *occupied,
                                NSUInteger preferCol, NSUInteger preferRow,
                                NSUInteger w, NSUInteger h,
                                NSUInteger maxRow,
                                NSUInteger *outCol, NSUInteger *outRow);
static id PACSettingsProvider(void);
static NSArray<NSString *> *PACProviderOrderedIdentifiers(void);
static UIView *PACModuleButtonView(UIView *moduleView);
static NSArray<UIView *> *PACCompactGlyphHosts(UIView *view);
static void PACLayoutModuleIcon(UIViewController *m);
static void PACRestoreModuleIcon(UIViewController *m);
static CGFloat PACRadiusForSize(NSUInteger w, NSUInteger h);
static void PACApplyRadiusToModule(UIViewController *m);
static void PACRefreshPresentation(UIViewController *m, UIViewController *ov);
static BOOL PACWasResizedFromOneByOne(NSString *mid);
static void PACApplyChrome(UIViewController *m, UIViewController *ov);
static void PACStripChrome(UIViewController *m);
static void PACRestoreModuleRadius(UIViewController *m);
static void PACInstallGestures(UIViewController *ov);
static BOOL PACEditAllowed(void);
static BOOL PACIsLandscape(void);
static void PACTearDownModule(UIViewController *m);
static void PACTearDownAllModules(UIViewController *ov);
static void PACScheduleRotationRefresh(void);

static void PACInitCachedClasses(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        kClsCCUIButtonModuleView = NSClassFromString(@"CCUIButtonModuleView");
        kClsCCUICAPackageView    = NSClassFromString(@"CCUICAPackageView");
        kClsCABackdropLayer      = NSClassFromString(@"CABackdropLayer");
    });
}

static NSUInteger gPACUserPages = 0;
static BOOL gPACUserPagesLoaded = NO;
static const NSUInteger kPACMaxPages = 6;

static NSUInteger PACBasePageCount(void) { return gPromoPageEnabled ? 3 : 2; }

static void PACEnsureUserPages(void) {
    if (gPACUserPagesLoaded) return;
    gPACUserPagesLoaded = YES;
    CFPropertyListRef v = CFPreferencesCopyAppValue(CFSTR("EditUserPages"), CFSTR("pawxed.ccock18.preferences"));
    if (v && CFGetTypeID(v) == CFNumberGetTypeID()) gPACUserPages = [(__bridge NSNumber *)v unsignedIntegerValue];
    if (v) CFRelease(v);
    NSUInteger room = kPACMaxPages > PACBasePageCount() ? kPACMaxPages - PACBasePageCount() : 0;
    if (gPACUserPages > room) gPACUserPages = room;
}

static void PACSaveUserPages(void) {
    CFPreferencesSetAppValue(CFSTR("EditUserPages"), (__bridge CFPropertyListRef)@(gPACUserPages), CFSTR("pawxed.ccock18.preferences"));
    CFPreferencesAppSynchronize(CFSTR("pawxed.ccock18.preferences"));
}

// first index of the pages the user added (they come after the built-in pages)
static BOOL PACIsUserPage(NSUInteger page) {
    PACEnsureUserPages();
    return page >= PACBasePageCount() && page < PACBasePageCount() + gPACUserPages;
}

static void PACEnsureStore(void) {
    static BOOL metricsLoaded = NO;
    if (!metricsLoaded) {
        metricsLoaded = YES;
        CFPropertyListRef c = CFPreferencesCopyAppValue(CFSTR("GridCell"), CFSTR("pawxed.ccock18.preferences"));
        CFPropertyListRef g = CFPreferencesCopyAppValue(CFSTR("GridGap"),  CFSTR("pawxed.ccock18.preferences"));
        if (c && g && CFGetTypeID(c) == CFNumberGetTypeID() && CFGetTypeID(g) == CFNumberGetTypeID()) {
            PACCSetGridMetrics([(__bridge NSNumber *)c doubleValue], [(__bridge NSNumber *)g doubleValue]);
        }
        if (c) CFRelease(c);
        if (g) CFRelease(g);
    }
    if (!gEditOrigins) {
        CFPropertyListRef v = CFPreferencesCopyAppValue(CFSTR("EditGridOrigins"), CFSTR("pawxed.ccock18.preferences"));
        gEditOrigins = [(__bridge NSDictionary *)v mutableCopy] ?: [NSMutableDictionary dictionary];
        if (v) CFRelease(v);
    }
    if (!gEditSizes) {
        CFPropertyListRef v = CFPreferencesCopyAppValue(CFSTR("EditGridSizes"), CFSTR("pawxed.ccock18.preferences"));
        gEditSizes = [(__bridge NSDictionary *)v mutableCopy] ?: [NSMutableDictionary dictionary];
        if (v) CFRelease(v);
    }
    if (!gEditBaseSizes) {
        CFPropertyListRef v = CFPreferencesCopyAppValue(CFSTR("EditBaseSizes"), CFSTR("pawxed.ccock18.preferences"));
        gEditBaseSizes = [(__bridge NSDictionary *)v mutableCopy] ?: [NSMutableDictionary dictionary];
        if (v) CFRelease(v);
    }
}

static void PACSaveStore(void) {
    PACEnsureStore();
    CFPreferencesSetAppValue(CFSTR("EditGridOrigins"), (__bridge CFPropertyListRef)[gEditOrigins copy], CFSTR("pawxed.ccock18.preferences"));
    CFPreferencesSetAppValue(CFSTR("EditGridSizes"),   (__bridge CFPropertyListRef)[gEditSizes copy],   CFSTR("pawxed.ccock18.preferences"));
    CFPreferencesSetAppValue(CFSTR("EditBaseSizes"),   (__bridge CFPropertyListRef)[gEditBaseSizes copy], CFSTR("pawxed.ccock18.preferences"));
    CFPreferencesAppSynchronize(CFSTR("pawxed.ccock18.preferences"));
}

static BOOL PACIsNotchedDevice(void) {
    UIWindow *w = UIApplication.sharedApplication.keyWindow;
    if (w && w.safeAreaInsets.bottom >= 1.0) return YES;
    return NO;
}

static BOOL PACIsLandscape(void) {
    UIWindow *win = UIApplication.sharedApplication.keyWindow;
    if (win) {
        CGSize sz = win.bounds.size;
        if (sz.width > 1.0 && sz.height > 1.0) return sz.width > sz.height;
    }
    CGSize sz = UIScreen.mainScreen.bounds.size;
    return sz.width > sz.height;
}

static BOOL PACIsNonNotchedDevice(void) {
    CGSize size = UIScreen.mainScreen.bounds.size;
    if (MAX(size.width, size.height) >= 800.0) return NO;
    UIWindow *window = UIApplication.sharedApplication.keyWindow;
    if (window && window.safeAreaInsets.bottom >= 1.0) return NO;
    return YES;
}

static void PACRefreshGridConstants(void) {
    BOOL landscape = PACIsLandscape();
    kPACCols = landscape ? 8 : 4;
    kPACRows = landscape ? 4 : 8;
    {
        CGFloat spanRows = landscape ? 0.0 : PageSpan() / (PACCGridCell() + PACCGridGap());
        kPACStride = MAX(kPACRows, (NSUInteger)llround(spanRows));
    }
    kPACCell = PACCGridCell();
    kPACgap  = PACCGridGap();
    kPACStep = kPACCell + kPACgap;
}

static BOOL PACEditAllowed(void) {
    if (!gEnabled || !gEditModeEnabled) return NO;
    if (PACIsLandscape()) return NO;
    return YES;
}

static NSString *PACGridKey(NSString *mid) {
    if (!mid.length) return mid;
    return PACIsLandscape() ? [@"L|" stringByAppendingString:mid]
                            : [@"P|" stringByAppendingString:mid];
}

static NSArray<NSNumber *> *PACGetOrigin(NSString *mid) {
    if (!mid.length) return nil;
    PACEnsureStore();
    NSString *key = PACGridKey(mid);
    NSArray<NSNumber *> *v = gEditOrigins[key];
    if (v) return v;
    if (!PACIsLandscape()) return gEditOrigins[mid];
    return nil;
}

static void PACSetOrigin(NSString *mid, NSArray<NSNumber *> *value) {
    if (!mid.length) return;
    PACEnsureStore();
    NSString *key = PACGridKey(mid);
    if (value) gEditOrigins[key] = value;
    else       [gEditOrigins removeObjectForKey:key];
}

static void PACInvalidateOtherOrientationOriginForModule(NSString *mid) {
    if (!mid.length) return;
    PACEnsureStore();
    BOOL landscape = PACIsLandscape();
    NSString *otherPrefix = landscape ? @"P|" : @"L|";
    NSString *key = [otherPrefix stringByAppendingString:mid];
    [gEditOrigins removeObjectForKey:key];
    if (!landscape) {
        [gEditOrigins removeObjectForKey:mid];
    }
}

static NSArray<NSNumber *> *PACSourceOriginForRotation(NSString *mid, BOOL toLandscape) {
    if (!mid.length) return nil;
    NSString *fromPrefix = toLandscape ? @"P|" : @"L|";
    NSArray *v = gEditOrigins[[fromPrefix stringByAppendingString:mid]];
    if (v) return v;
    if (toLandscape) return gEditOrigins[mid];
    return nil;
}

static NSArray<NSNumber *> *PACTargetOriginForRotation(NSString *mid, BOOL toLandscape) {
    if (!mid.length) return nil;
    NSString *toPrefix = toLandscape ? @"L|" : @"P|";
    return gEditOrigins[[toPrefix stringByAppendingString:mid]];
}

static void PACMigrateMissingOrigins(UIViewController *ov) {
    if (!ov) return;
    PACEnsureStore();
    PACRefreshGridConstants();

    BOOL toLandscape = PACIsLandscape();
    NSUInteger fromCols = toLandscape ? 4 : 8;
    NSUInteger fromRows = toLandscape ? 8 : 4;
    NSUInteger toCols   = toLandscape ? 8 : 4;
    NSUInteger toRows   = toLandscape ? 4 : 8;
    NSString *toPrefix = toLandscape ? @"L|" : @"P|";

    NSMutableArray<NSDictionary *> *toMigrate = [NSMutableArray array];
    NSMutableArray<NSString *>     *already   = [NSMutableArray array];

    for (UIViewController *m in ModuleControllers(ov)) {
        NSString *mid = PACMid(m);
        if (!mid.length) continue;

        if (PACTargetOriginForRotation(mid, toLandscape)) {
            [already addObject:mid];
            continue;
        }
        NSArray<NSNumber *> *src = PACSourceOriginForRotation(mid, toLandscape);
        if (src.count < 2) continue;

        NSUInteger c = src[0].unsignedIntegerValue;
        NSUInteger a = src[1].unsignedIntegerValue;
        NSUInteger page = a / fromRows;
        NSUInteger r    = a % fromRows;

        NSUInteger w = 1, h = 1;
        NSArray<NSNumber *> *sz = gEditSizes[mid];
        if (sz.count < 2) sz = gEditBaseSizes[mid];
        if (sz.count >= 2) {
            w = sz[0].unsignedIntegerValue;
            h = sz[1].unsignedIntegerValue;
        }
        if (w > toCols) w = toCols;
        if (h > toRows) h = toRows;
        if (!PACDragSizeAllowedForModule(mid, w, h)) { w = 1; h = 1; }

        [toMigrate addObject:@{
            @"mid":  mid,
            @"c":    @(c),
            @"r":    @(r),
            @"page": @(page),
            @"w":    @(w),
            @"h":    @(h),
        }];
    }

    if (!toMigrate.count) return;

    [toMigrate sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        for (NSString *k in @[@"page", @"r", @"c"]) {
            NSInteger va = [a[k] integerValue];
            NSInteger vb = [b[k] integerValue];
            if (va != vb) return va < vb ? NSOrderedAscending : NSOrderedDescending;
        }
        return [a[@"mid"] compare:b[@"mid"]];
    }];

    NSMutableDictionary<NSNumber *, NSMutableDictionary<NSString *, NSValue *> *> *pages =
        [NSMutableDictionary dictionary];

    for (NSString *mid in already) {
        NSArray<NSNumber *> *o = PACTargetOriginForRotation(mid, toLandscape);
        if (o.count < 2) continue;
        NSUInteger c = o[0].unsignedIntegerValue;
        NSUInteger a = o[1].unsignedIntegerValue;
        NSUInteger page = a / toRows;
        NSUInteger r    = a % toRows;

        NSUInteger w = 1, h = 1;
        NSArray<NSNumber *> *sz = gEditSizes[mid];
        if (sz.count < 2) sz = gEditBaseSizes[mid];
        if (sz.count >= 2) {
            w = sz[0].unsignedIntegerValue;
            h = sz[1].unsignedIntegerValue;
        }
        if (w > toCols) w = toCols;
        if (h > toRows) h = toRows;

        NSMutableDictionary *map = pages[@(page)];
        if (!map) { map = [NSMutableDictionary dictionary]; pages[@(page)] = map; }
        PACRect pr = {c, r, w, h};
        map[mid] = [NSValue value:&pr withObjCType:@encode(PACRect)];
    }

    for (NSDictionary *e in toMigrate) {
        NSString *mid = e[@"mid"];
        NSUInteger srcC = [e[@"c"]    unsignedIntegerValue];
        NSUInteger srcR = [e[@"r"]    unsignedIntegerValue];
        NSUInteger page = [e[@"page"] unsignedIntegerValue];
        NSUInteger w    = [e[@"w"]    unsignedIntegerValue];
        NSUInteger h    = [e[@"h"]    unsignedIntegerValue];

        NSUInteger prefC = (NSUInteger)llround(((double)srcC / (double)fromCols) * (double)toCols);
        NSUInteger prefR = (NSUInteger)llround(((double)srcR / (double)fromRows) * (double)toRows);
        if (prefC + w > toCols) prefC = (toCols >= w) ? (toCols - w) : 0;
        if (prefR + h > toRows) prefR = (toRows >= h) ? (toRows - h) : 0;

        NSMutableDictionary<NSString *, NSValue *> *placed = pages[@(page)];
        if (!placed) { placed = [NSMutableDictionary dictionary]; pages[@(page)] = placed; }

        NSUInteger maxRow = (toRows >= h) ? (toRows - h) : 0;
        NSUInteger outC = prefC, outR = prefR;
        BOOL ok = PACFindFreeCellFor(placed, prefC, prefR, w, h, maxRow, &outC, &outR);

        if (!ok) {
            NSUInteger p = page + 1;
            while (p < 8) {
                NSMutableDictionary *next = pages[@(p)];
                if (!next) { next = [NSMutableDictionary dictionary]; pages[@(p)] = next; }
                if (PACFindFreeCellFor(next, 0, 0, w, h, maxRow, &outC, &outR)) {
                    placed = next; page = p; ok = YES; break;
                }
                p++;
            }
        }
        if (!ok) continue;

        PACRect pr = {outC, outR, w, h};
        placed[mid] = [NSValue value:&pr withObjCType:@encode(PACRect)];
        gEditOrigins[[toPrefix stringByAppendingString:mid]] =
            @[@(outC), @(page * toRows + outR)];
    }

    PACSaveStore();
}

static NSString *PACMid(UIViewController *vc) {
    if (!vc) return nil;
    for (NSString *key in @[@"moduleIdentifier", @"_moduleIdentifier"]) {
        @try { id v = [vc valueForKey:key];
            if ([v isKindOfClass:NSString.class] && [v length]) return v; }
        @catch (__unused NSException *e) {}
    }
    return nil;
}

// Where the module sits in the collection view's own coordinates (the layout position, before the page offset).
// Built by adding up the view frames, so it does not matter how UIKit treats sublayerTransform in convertRect.
static BOOL PACRawFrame(UIViewController *m, UIViewController *overlay, CGRect *out) {
    UIViewController *col = ModuleCollection(overlay);
    UIView *cv = col.view;
    UIView *v = m.view;
    if (!cv || !v) return NO;
    CGRect r = v.bounds;
    while (v && v != cv) {
        UIView *sv = v.superview;
        if (!sv) return NO;
        CGPoint c = v.center;
        CGRect b = v.bounds;
        r.origin.x += c.x - b.size.width * 0.5 - b.origin.x;
        r.origin.y += c.y - b.size.height * 0.5 - b.origin.y;
        v = sv;
    }
    if (v != cv) return NO;
    *out = r;
    return YES;
}

static CGRect PACVisibleFrame(UIViewController *m, UIViewController *overlay) {
    if (!m.view || !overlay.view) return CGRectZero;
    UIViewController *col = ModuleCollection(overlay);
    CGRect raw;
    if (col.view && PACRawFrame(m, overlay, &raw)) {
        CATransform3D sub = col.view.layer.sublayerTransform;
        raw.origin.x += sub.m41;
        raw.origin.y += sub.m42;
        return [col.view convertRect:raw toView:overlay.view];
    }
    return [m.view convertRect:m.view.bounds toView:overlay.view];
}

// Reads the real cell size and gap from where the modules sit, so paging and the grid math fit this device.
static void PACUpdateGridMetrics(UIViewController *ov) {
    if (!ov || PACIsLandscape() || gPACPendingResizeID || gPageAnimating) return;
    static CFTimeInterval last = 0;
    CFTimeInterval now = CACurrentMediaTime();
    if (now - last < 0.5) return;
    last = now;
    PACEnsureStore();

    CGFloat minX = CGFLOAT_MAX, maxX = -CGFLOAT_MAX, minY = CGFLOAT_MAX, maxY = -CGFLOAT_MAX, minW = CGFLOAT_MAX;
    NSInteger cA = 0, cB = 0, rA = 0, rB = 0;
    BOOL anyX = NO, anyY = NO;
    for (UIViewController *m in ModuleControllers(ov)) {
        NSString *mid = PACMid(m);
        NSArray<NSNumber *> *o = mid.length ? PACGetOrigin(mid) : nil;
        CGRect raw;
        if (o.count < 2 || !PACRawFrame(m, ov, &raw) || CGRectIsEmpty(raw)) continue;
        NSInteger c = (NSInteger)o[0].unsignedIntegerValue, a = (NSInteger)o[1].unsignedIntegerValue;
        if (raw.origin.x < minX) { minX = raw.origin.x; cA = c; anyX = YES; }
        if (raw.origin.x > maxX) { maxX = raw.origin.x; cB = c; }
        if (raw.origin.y < minY) { minY = raw.origin.y; rA = a; anyY = YES; }
        if (raw.origin.y > maxY) { maxY = raw.origin.y; rB = a; }
        minW = MIN(minW, raw.size.width);
    }
    if (!anyX || !anyY) return;
    CGFloat stepX = (cB != cA) ? (maxX - minX) / (CGFloat)(cB - cA) : 0.0;
    CGFloat stepY = (rB != rA) ? (maxY - minY) / (CGFloat)(rB - rA) : 0.0;
    CGFloat step = 0.0;
    if (stepX > 0.0 && stepY > 0.0) {
        if (fabs(stepX - stepY) > 1.0) return;     // modules are still moving
        step = (stepX + stepY) * 0.5;
    } else {
        step = MAX(stepX, stepY);
    }
    if (step < 55.0 || step > 130.0 || minW < 45.0 || minW > 120.0) return;
    CGFloat cell = floor(minW * 2.0 + 0.5) / 2.0;
    step = floor(step * 2.0 + 0.5) / 2.0;
    CGFloat gap = step - cell;
    if (gap < 4.0 || gap > 40.0) return;
    if (fabs(cell - PACCGridCell()) < 0.4 && fabs(gap - PACCGridGap()) < 0.4) return;

    PACCSetGridMetrics(cell, gap);
    CFPreferencesSetAppValue(CFSTR("GridCell"), (__bridge CFPropertyListRef)@(cell), CFSTR("pawxed.ccock18.preferences"));
    CFPreferencesSetAppValue(CFSTR("GridGap"),  (__bridge CFPropertyListRef)@(gap),  CFSTR("pawxed.ccock18.preferences"));
    CFPreferencesAppSynchronize(CFSTR("pawxed.ccock18.preferences"));
    PACRefreshGridConstants();
    [ov.view setNeedsLayout];
}

static UIViewController *PACModuleAtPoint(CGPoint pt, UIViewController *overlay) {
    UIViewController *best = nil;
    CGFloat bestD = CGFLOAT_MAX;
    for (UIViewController *m in ModuleControllers(overlay)) {
        CGRect f = PACVisibleFrame(m, overlay);
        if (CGRectIsEmpty(f)) continue;
        if (CGRectContainsPoint(f, pt)) {
            CGFloat d = hypot(CGRectGetMidX(f) - pt.x, CGRectGetMidY(f) - pt.y);
            if (d < bestD) { bestD = d; best = m; }
        }
    }
    return best;
}

static CGPoint PACGridBase(UIViewController *overlay) {
    PACRefreshGridConstants();
    PACEnsureStore();
    CGFloat bx = CGFLOAT_MAX, by = CGFLOAT_MAX;
    NSInteger page = MAX((NSInteger)0, gCurrentPage);
    // Any module can tell where the grid starts, also one on another page (its frame already
    // includes the page offset), so an empty page still knows where its rows are.
    for (UIViewController *m in ModuleControllers(overlay)) {
        NSString *mid = PACMid(m);
        if (!mid.length) continue;
        NSArray<NSNumber *> *o = PACGetOrigin(mid);
        if (o.count < 2) continue;
        NSUInteger c = o[0].unsignedIntegerValue;
        NSUInteger a = o[1].unsignedIntegerValue;
        NSInteger lr = (NSInteger)a - page * (NSInteger)kPACStride;
        if (lr < 0 || lr > (NSInteger)kPACStride * 2) continue;
        CGRect f = PACVisibleFrame(m, overlay);
        if (CGRectIsEmpty(f)) continue;
        CGFloat x = CGRectGetMinX(f) - (CGFloat)c * kPACStep;
        CGFloat y = CGRectGetMinY(f) - (CGFloat)lr * kPACStep;
        if (x < bx) bx = x;
        if (y < by) by = y;
    }
    if (bx == CGFLOAT_MAX) {
        CGFloat w = CGRectGetWidth(overlay.view.bounds);
        CGFloat gw = kPACCols * kPACCell + (kPACCols - 1) * kPACgap;
        bx = (w - gw) * 0.5;
        by = 100.0;
    }
    return CGPointMake(bx, by);
}

static NSUInteger PACVisibleRowCap(UIViewController *ov) {
    if (!ov || !ov.view) return kPACRows - 1;
    CGPoint base = PACGridBase(ov);
    CGFloat overlayH = CGRectGetHeight(ov.view.bounds);
    CGFloat safeBottom = ov.view.safeAreaInsets.bottom;
    if (safeBottom < 1.0) safeBottom = 20.0;
    CGFloat usableBottom = overlayH - safeBottom - 8.0;
    CGFloat usableH = usableBottom - base.y;
    if (usableH < kPACStep) return 0;
    NSInteger rows = (NSInteger)floor(usableH / kPACStep);
    if (rows <= 0) rows = 1;
    NSUInteger cap = (NSUInteger)MAX(0, MIN((NSInteger)kPACRows - 1, rows - 1));
    return cap;
}

static NSArray<NSNumber *> *PACKnownBaseSize(NSString *mid) {
    if (!mid.length) return nil;
    NSString *lower = mid.lowercaseString;
    NSArray<NSArray<NSString *> *> *entries = @[
        @[@"control-center.connectivitymodule", @"2", @"2"],
        @[@"connectivitymodule", @"2", @"2"],
        @[@"mediaremote.controlcenter.nowplaying", @"2", @"2"],
        @[@"mediaremote.controlcenter.audio", @"1", @"2"],
        @[@"control-center.displaymodule", @"1", @"2"],
        @[@"control-center.focusui", @"2", @"1"],
        @[@"focusui", @"2", @"1"],
        @[@"donotdisturb", @"2", @"1"],
    ];
    for (NSArray *entry in entries) {
        if ([lower containsString:entry[0]]) {
            return @[@([entry[1] integerValue]), @([entry[2] integerValue])];
        }
    }
    return nil;
}

static void PACEnsureBaseSize(UIViewController *m, UIViewController *ov) {
    NSString *mid = PACMid(m);
    if (!mid.length) return;

    NSArray<NSNumber *> *known = PACKnownBaseSize(mid);
    if (known.count == 2) {
        if (![gEditBaseSizes[mid] isEqualToArray:known]) {
            gEditBaseSizes[mid] = known;
            PACSaveStore();
        }
        return;
    }

    if (gEditSizes[mid]) {
        if (![gEditBaseSizes[mid] isEqualToArray:@[@1, @1]]) {
            gEditBaseSizes[mid] = @[@1, @1];
            PACSaveStore();
        }
        return;
    }

    NSArray<NSNumber *> *existing = gEditBaseSizes[mid];
    if (existing.count >= 2 &&
        (existing[0].integerValue != 1 || existing[1].integerValue != 1)) {
        gEditBaseSizes[mid] = @[@1, @1];
        PACSaveStore();
        return;
    }
    if (existing) return;

    CGRect f = PACVisibleFrame(m, ov);
    if (CGRectIsEmpty(f)) return;
    NSUInteger w = (NSUInteger)MAX(1, MIN((NSInteger)kPACCols, (NSInteger)llround((CGRectGetWidth(f) + kPACgap) / kPACStep)));
    NSUInteger h = (NSUInteger)MAX(1, MIN((NSInteger)kPACRows, (NSInteger)llround((CGRectGetHeight(f) + kPACgap) / kPACStep)));
    gEditBaseSizes[mid] = @[@(w), @(h)];
    PACSaveStore();
}

static void PACEffectiveSize(NSString *mid, NSUInteger *w, NSUInteger *h) {
    PACEnsureStore();
    NSArray<NSNumber *> *s = gEditSizes[mid];
    if (!s) s = gEditBaseSizes[mid];
    *w = s.count >= 2 ? s[0].unsignedIntegerValue : 1;
    *h = s.count >= 2 ? s[1].unsignedIntegerValue : 1;
}

static void PACPresentationSize(NSString *mid, NSUInteger *w, NSUInteger *h) {
    if (gPACPendingResizeID && [gPACPendingResizeID isEqualToString:mid] &&
        gPACPendingResizeSize.width && gPACPendingResizeSize.height) {
        *w = gPACPendingResizeSize.width;
        *h = gPACPendingResizeSize.height;
        return;
    }
    PACEffectiveSize(mid, w, h);
}

typedef struct { NSTimeInterval duration; CGFloat c1x, c1y, c2x, c2y; } PACAnimSpec;

static PACAnimSpec PACResizeSpec(void) {
    if (gExperimentalPagingEnabled) return (PACAnimSpec){0.58, 0.32, 0.72, 0.0, 1.0};
    return (PACAnimSpec){0.25, 0.25, 0.10, 0.25, 1.0};
}

static CAMediaTimingFunction *PACResizeTiming(PACAnimSpec sp) {
    return [CAMediaTimingFunction functionWithControlPoints:(float)sp.c1x :(float)sp.c1y :(float)sp.c2x :(float)sp.c2y];
}

static BOOL PACAnimationsAllowed(void) {
    return CACurrentMediaTime() >= gPACRotationQuietUntil;
}

static BOOL PACModuleSupportsResizing(NSString *mid) {
    if (!mid.length) return NO;
    NSString *lower = mid.lowercaseString;
    if ([lower isEqualToString:@"com.apple.control-center.displaymodule"]) return NO;
    if ([lower containsString:@"mediaremote.controlcenter.audio"]) return NO;
    NSArray<NSNumber *> *base = gEditBaseSizes[mid];
    if (!base) base = PACKnownBaseSize(mid);
    if (base.count < 2) return NO;
    NSUInteger w = base[0].unsignedIntegerValue;
    NSUInteger h = base[1].unsignedIntegerValue;
    if (w == 1 && h == 1) return YES;
    if (w == 2 && h == 2) return YES;
    return NO;
}

static BOOL PACSizeAllowed(NSUInteger w, NSUInteger h) {
    if (w == 0 || h == 0) return NO;
    if (w > kPACCols || h > kPACRows) return NO;
    if (w > 4 || h > 4) return NO;
    if (w == 1 && h == 2) return NO;
    if (h == 1 && w == 3) return NO;
    if (h == 1 && w == 4) return NO;
    return YES;
}

// Connectivity and Music have their own list of sizes (2x2, 4x4, 4x6 / 2x2, 4x2, 4x4, 4x6).
static BOOL PACSizeAllowedFor(NSString *mid, NSUInteger w, NSUInteger h) {
    if (PACCBigKind(mid)) return PACCBigSizeAllowed(mid, w, h) && w <= kPACCols && h <= kPACRows;
    return PACSizeAllowed(w, h);
}

static BOOL PACDragSizeAllowedForModule(NSString *mid, NSUInteger w, NSUInteger h) {
    if (PACSizeAllowedFor(mid, w, h)) return YES;
    if (PACModuleSupportsResizing(mid)) return NO;
    NSUInteger bw = 1, bh = 1;
    PACEffectiveSize(mid, &bw, &bh);
    return (w == bw && h == bh);
}

static CCUILayoutSize PACResizeCandidate(NSString *mid, NSUInteger startW, NSUInteger startH, CGPoint translation) {
    NSInteger dc = (NSInteger)floor(translation.x / kPACStep + 0.5);
    NSInteger dr = (NSInteger)floor(translation.y / kPACStep + 0.5);
    NSInteger nw = MAX(1, MIN(4, (NSInteger)startW + dc));
    NSInteger nh = MAX(1, MIN(4, (NSInteger)startH + dr));
    if (PACCBigKind(mid)) {
        nh = MAX(1, MIN(6, (NSInteger)startH + dr));
        NSUInteger sw = 2, sh = 2;
        PACCBigSnapSize(mid, nw, nh, &sw, &sh);
        return (CCUILayoutSize){sw, sh};
    }
    return (CCUILayoutSize){(NSUInteger)nw, (NSUInteger)nh};
}

static NSString *PACBundleDisplayName(NSBundle *bundle) {
    if (!bundle) return nil;
    static NSSet<NSString *> *ignored = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        ignored = [NSSet setWithArray:@[
            @"ControlCenter", @"ControlCenterSettings", @"ControlCenterUIKit",
            @"ControlCenterServices", @"ControlCenterUI", @"ControlCenterSettingsBundles",
            @"CCSupport", @"SpringBoard", @"Preferences", @"UIKit", @"Foundation"]];
    });
    NSString *name = [bundle objectForInfoDictionaryKey:@"CFBundleDisplayName"];
    if (!name.length) name = [bundle objectForInfoDictionaryKey:@"CFBundleName"];
    if (!name.length) return nil;
    if ([ignored containsObject:name]) return nil;
    return name;
}

static NSString *PACPrettyNameForModule(UIViewController *m) {
    if (!m) return @"Control";

    NSString *mid = PACMid(m);
    NSString *lower = mid.lowercaseString;

    if ([lower containsString:@"screencapture"]) return @"Screen Recording";
    if ([lower containsString:@"control-center.displaymodule"] ||
        [lower isEqualToString:@"displaymodule"]) return @"Brightness";
    if ([lower containsString:@"controlcenter.audio"]) return @"Volume";
    if ([lower containsString:@"accessibility"]) return @"Accessibility Shortcuts";

    id contentModule = nil;
    @try { contentModule = [m valueForKey:@"module"]; } @catch (__unused NSException *e) {}
    for (NSString *key in @[@"displayName", @"title"]) {
        @try {
            id v = [contentModule valueForKey:key];
            if ([v isKindOfClass:NSString.class] && [v length]) return v;
        } @catch (__unused NSException *e) {}
    }

    id prov = PACSettingsProvider();
    if (prov) {
        id meta = nil;
        SEL metaSel = NSSelectorFromString(@"moduleMetadataForModuleIdentifier:");
        if ([prov respondsToSelector:metaSel]) {
            meta = ((id (*)(id, SEL, id))objc_msgSend)(prov, metaSel, mid);
        }
        if (!meta) {
            @try {
                NSDictionary *all = [prov valueForKey:@"moduleMetadata"];
                if ([all isKindOfClass:NSDictionary.class]) meta = all[mid];
            } @catch (__unused NSException *e) {}
        }
        for (NSString *key in @[@"displayName", @"name", @"title", @"localizedName"]) {
            @try {
                id v = [meta valueForKey:key];
                if ([v isKindOfClass:NSString.class] && [v length]) return v;
            } @catch (__unused NSException *e) {}
        }
        NSURL *bundleURL = nil;
        NSString *bundlePath = nil;
        @try { id v = [meta valueForKey:@"bundleURL"];
            if ([v isKindOfClass:NSURL.class]) bundleURL = v; } @catch (__unused NSException *e) {}
        @try { id v = [meta valueForKey:@"bundlePath"];
            if ([v isKindOfClass:NSString.class]) bundlePath = v; } @catch (__unused NSException *e) {}
        NSBundle *bundle = bundleURL ? [NSBundle bundleWithURL:bundleURL]
                      : bundlePath ? [NSBundle bundleWithPath:bundlePath] : nil;
        NSString *metaBundleName = PACBundleDisplayName(bundle);
        if (metaBundleName.length) return metaBundleName;
    }

    if (contentModule) {
        NSString *classBundleName = PACBundleDisplayName([NSBundle bundleForClass:[contentModule class]]);
        if (classBundleName.length) return classBundleName;
    }

    NSString *label = m.view.accessibilityLabel;
    if (label.length) return label;
    UIView *pres = objc_getAssociatedObject(m.view, kPACPresKey);
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithArray:m.view.subviews];
    while (queue.count) {
        UIView *v = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if (pres && v == pres) continue;
        if (v.accessibilityLabel.length) { label = v.accessibilityLabel; break; }
        [queue addObjectsFromArray:v.subviews];
    }
    if (label.length) return label;

    if (!mid.length) return @"Control";
    NSString *last = [mid componentsSeparatedByString:@"."].lastObject;
    if ([last hasSuffix:@"Module"] && last.length > 6) last = [last substringToIndex:last.length - 6];
    if (!last.length) return @"Control";
    NSMutableString *result = [NSMutableString string];
    for (NSUInteger i = 0; i < last.length; i++) {
        unichar c = [last characterAtIndex:i];
        if (i > 0 && [[NSCharacterSet uppercaseLetterCharacterSet] characterIsMember:c]) {
            [result appendString:@" "];
        }
        [result appendFormat:@"%C", c];
    }
    return result.length ? result : @"Control";
}

static BOOL PACRectsOverlap(PACRect a, PACRect b) {
    return (a.c < b.c + b.w && b.c < a.c + a.w &&
            a.r < b.r + b.h && b.r < a.r + a.h);
}

static BOOL PACFindFreeCellFor(NSDictionary<NSString *, NSValue *> *occupied,
                                NSUInteger preferCol, NSUInteger preferRow,
                                NSUInteger w, NSUInteger h,
                                NSUInteger maxRow,
                                NSUInteger *outCol, NSUInteger *outRow) {
    if (w == 0 || h == 0 || w > kPACCols || h > kPACRows) return NO;
    NSInteger maxC = (NSInteger)kPACCols - (NSInteger)w;
    NSInteger maxR = MIN((NSInteger)maxRow, (NSInteger)kPACRows - (NSInteger)h);
    if (maxC < 0 || maxR < 0) return NO;

    BOOL found = NO;
    NSInteger bestScore = NSIntegerMax;
    NSUInteger bestCol = 0, bestRow = 0;

    for (NSInteger r = 0; r <= maxR; r++) {
        for (NSInteger c = 0; c <= maxC; c++) {
            PACRect t = {(NSUInteger)c, (NSUInteger)r, w, h};
            BOOL ok = YES;
            for (NSValue *v in occupied.allValues) {
                PACRect o = {};
                [v getValue:&o];
                if (PACRectsOverlap(t, o)) { ok = NO; break; }
            }
            if (!ok) continue;
            NSInteger dx = c - (NSInteger)preferCol;
            NSInteger dy = r - (NSInteger)preferRow;
            NSInteger score = labs((long)dx) + labs((long)dy);
            if (score < bestScore ||
                (score == bestScore && (r < (NSInteger)bestRow ||
                 (r == (NSInteger)bestRow && c < (NSInteger)bestCol)))) {
                bestScore = score;
                bestCol = (NSUInteger)c;
                bestRow = (NSUInteger)r;
                found = YES;
            }
        }
    }
    if (found) { *outCol = bestCol; *outRow = bestRow; }
    return found;
}

static id PACSettingsProvider(void) {
    Class c = NSClassFromString(@"CCSModuleSettingsProvider");
    SEL s = NSSelectorFromString(@"sharedProvider");
    return (c && [c respondsToSelector:s]) ? ((id (*)(id, SEL))objc_msgSend)(c, s) : nil;
}

static NSArray<NSString *> *PACProviderOrderedIdentifiers(void) {
    id prov = PACSettingsProvider();
    SEL sel = NSSelectorFromString(@"orderedUserEnabledModuleIdentifiers");
    if (!prov || ![prov respondsToSelector:sel]) return nil;
    id list = ((id (*)(id, SEL))objc_msgSend)(prov, sel);
    return [list isKindOfClass:NSArray.class] ? (NSArray<NSString *> *)list : nil;
}

static UIView *PACModuleButtonView(UIView *moduleView) {
    if (!moduleView) return moduleView;
    if (kClsCCUIButtonModuleView && [moduleView isKindOfClass:kClsCCUIButtonModuleView]) return moduleView;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithArray:moduleView.subviews];
    while (queue.count) {
        UIView *v = queue.lastObject;
        [queue removeLastObject];
        if (kClsCCUIButtonModuleView && [v isKindOfClass:kClsCCUIButtonModuleView]) return v;
        if (v.subviews.count) [queue addObjectsFromArray:v.subviews];
    }
    return moduleView;
}

static NSArray<UIView *> *PACCompactGlyphHosts(UIView *view) {
    if (!view) return @[];
    NSMutableArray<UIView *> *hosts = [NSMutableArray array];
    for (NSString *key in @[@"_glyphImageView", @"glyphImageView", @"_glyphPackageView", @"glyphPackageView"]) {
        @try {
            id cand = [view valueForKey:key];
            if ([cand isKindOfClass:UIView.class] && ![hosts containsObject:cand]) [hosts addObject:cand];
        } @catch (__unused NSException *e) {}
    }
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithArray:view.subviews];
    while (queue.count) {
        UIView *v = queue.lastObject;
        [queue removeLastObject];
        BOOL hit = kClsCCUICAPackageView && [v isKindOfClass:kClsCCUICAPackageView];
        if (!hit) {
            NSString *cls = NSStringFromClass(v.class);
            hit = [cls isEqualToString:@"CCUICAPackageView"] || [cls containsString:@"CAPackage"];
        }
        if (!hit && [v isKindOfClass:UIImageView.class]) {
            UIImageView *iv = (UIImageView *)v;
            CGFloat mn = MIN(CGRectGetWidth(v.bounds), CGRectGetHeight(v.bounds));
            hit = iv.image != nil && mn >= 16.0 && !v.hidden && v.alpha > 0.01;
        }
        if (hit && ![hosts containsObject:v]) [hosts addObject:v];
        if (v.subviews.count) [queue addObjectsFromArray:v.subviews];
    }
    return hosts;
}

static BOOL PACIsGeometryKeyPath(NSString *keyPath) {
    return [keyPath hasPrefix:@"position"] ||
           [keyPath hasPrefix:@"bounds"] ||
           [keyPath hasPrefix:@"transform"] ||
           [keyPath hasPrefix:@"anchorPoint"];
}

static BOOL PACViewIsPinnedGlyph(UIView *view) {
    BOOL glyphSeen = NO;
    UIView *a = view;
    for (NSUInteger i = 0; a && i < 8; i++, a = a.superview) {
        if (objc_getAssociatedObject(a, kPACIconPinKey)) return glyphSeen;
        NSString *cls = NSStringFromClass(a.class);
        if ([a isKindOfClass:UIImageView.class] || [cls containsString:@"CAPackage"]) glyphSeen = YES;
    }
    return NO;
}

static BOOL PACShouldBlockGlyphAnimation(CALayer *layer, CAAnimation *anim) {
    if (![anim isKindOfClass:CAPropertyAnimation.class]) return NO;
    if (!PACIsGeometryKeyPath(((CAPropertyAnimation *)anim).keyPath)) return NO;
    CALayer *l = layer;
    for (NSUInteger i = 0; l && i < 8; i++, l = l.superlayer) {
        id d = l.delegate;
        if ([d isKindOfClass:UIView.class]) return PACViewIsPinnedGlyph((UIView *)d);
    }
    return NO;
}

static void PACLayoutModuleIcon(UIViewController *m) {
    if (!m || !m.view) return;
    UIView *buttonView = PACModuleButtonView(m.view);
    NSArray<UIView *> *glyphs = PACCompactGlyphHosts(buttonView);
    CGPoint targetInButton = CGPointMake(kPACCell * 0.5, kPACCell * 0.5);
    objc_setAssociatedObject(buttonView, kPACIconPinKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    for (UIView *glyph in glyphs) {
        UIView *host = glyph.superview;
        if (!host) continue;
        CGPoint target = [buttonView convertPoint:targetInButton toView:host];

        [UIView performWithoutAnimation:^{
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            for (NSString *k in [glyph.layer.animationKeys copy]) {
                CAAnimation *a = [glyph.layer animationForKey:k];
                if ([a isKindOfClass:CAPropertyAnimation.class] &&
                    PACIsGeometryKeyPath(((CAPropertyAnimation *)a).keyPath)) {
                    [glyph.layer removeAnimationForKey:k];
                }
            }
            glyph.layer.transform = CATransform3DIdentity;
            glyph.center = target;
            [CATransaction commit];
        }];
    }
}

static void PACRestoreModuleIcon(UIViewController *m) {
    if (!m || !m.view) return;
    UIView *buttonView = PACModuleButtonView(m.view);
    NSArray<UIView *> *glyphs = PACCompactGlyphHosts(buttonView);
    for (UIView *glyph in glyphs) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        [glyph.layer removeAnimationForKey:@"pac.glide"];
        glyph.transform = CGAffineTransformIdentity;
        [CATransaction commit];
    }
}

static CGFloat PACRadiusForSize(NSUInteger w, NSUInteger h) {
    if (w == 0 || h == 0) return 22.0;

    CGFloat widthPt  = (CGFloat)w * kPACCell + ((CGFloat)w - 1.0) * kPACgap;
    CGFloat heightPt = (CGFloat)h * kPACCell + ((CGFloat)h - 1.0) * kPACgap;
    if (widthPt <= 0.0 || heightPt <= 0.0) return 22.0;

    // LiquidAss rounds a squarish module with the radius of a 1x1 control and anything longer into a pill.
    // Using the same numbers keeps its glass and our corners in step, so resizing back leaves no odd shape.
    if (PACCLIQIsActive()) {
        CGFloat mn = MIN(widthPt, heightPt), mx = MAX(widthPt, heightPt);
        if (mx <= mn * 1.25) return floor(kPACCell * 0.5);
        return floor(mn * 0.5);
    }

    return calculatedRadius(CGRectMake(0.0, 0.0, widthPt, heightPt), 22.0);
}

static void PACRememberLayerState(UIView *v, NSMapTable<UIView *, NSDictionary *> *table) {
    if (!v || [table objectForKey:v]) return;
    [table setObject:@{ @"r":     @(v.layer.cornerRadius),
                        @"curve": v.layer.cornerCurve ?: kCACornerCurveCircular,
                        @"mask":  @(v.layer.masksToBounds) }
              forKey:v];
}

static BOOL PACModuleIsExpanded(UIViewController *m) {
    if (gCCAModuleExpanded) return YES;
    SEL sel = NSSelectorFromString(@"isExpanded");
    if ([m respondsToSelector:sel] && ((BOOL (*)(id, SEL))objc_msgSend)(m, sel)) return YES;
    UIView *root = m.view;
    if (!root) return NO;
    CGSize ms = root.bounds.size;

    NSString *mid = PACMid(m);
    if (mid.length && ms.width > 1.0 && ms.height > 1.0) {
        NSUInteger w = 1, h = 1;
        PACPresentationSize(mid, &w, &h);
        CGFloat ew = (CGFloat)w * kPACCell + ((CGFloat)w - 1.0) * kPACgap;
        CGFloat eh = (CGFloat)h * kPACCell + ((CGFloat)h - 1.0) * kPACgap;
        if (ms.width > ew * 1.35 + 8.0 || ms.height > eh * 1.35 + 8.0) return YES;
    }

    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithArray:root.subviews];
    NSUInteger visited = 0;
    while (queue.count && visited++ < 80) {
        UIView *v = queue.lastObject;
        [queue removeLastObject];
        NSString *cls = NSStringFromClass(v.class);
        if (([cls containsString:@"CCUIContentModuleContentContainer"] || [cls containsString:@"SliderView"]) &&
            (CGRectGetWidth(v.bounds) > ms.width + 14.0 || CGRectGetHeight(v.bounds) > ms.height + 14.0)) {
            return YES;
        }
        [queue addObjectsFromArray:v.subviews];
    }
    return NO;
}

static void PACSetRadius(CALayer *layer, CGFloat radius, BOOL animate) {
    if (PACCLIQIsActive()) {
        // LiquidAss follows the radius itself; an animated radius is what bends its glass.
        animate = NO;
        [layer removeAnimationForKey:@"pac.radius"];
    }
    CGFloat from = radius;
    if (animate) {
        CALayer *pl = layer.presentationLayer;
        from = pl ? pl.cornerRadius : layer.cornerRadius;
    }
    layer.cornerRadius = radius;
    layer.cornerCurve = kCACornerCurveContinuous;
    layer.masksToBounds = YES;
    CABasicAnimation *running = (CABasicAnimation *)[layer animationForKey:@"pac.radius"];
    BOOL sameGoal = running && [running.toValue isKindOfClass:NSNumber.class] &&
                    fabs([running.toValue doubleValue] - radius) < 0.01;
    if (animate && !sameGoal && fabs(from - radius) > 0.5) {
        PACAnimSpec sp = PACResizeSpec();
        CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"cornerRadius"];
        a.fromValue = @(from);
        a.toValue = @(radius);
        a.duration = sp.duration;
        a.timingFunction = PACResizeTiming(sp);
        [layer addAnimation:a forKey:@"pac.radius"];
    }
}

// Makes LiquidAss lay its glass out again for the module's current size.
static void PACResyncGlass(UIViewController *m) {
    if (!m.view || !PACCLIQIsActive()) return;
    UIView *root = m.view.superview ?: m.view;
    [UIView performWithoutAnimation:^{
        NSMutableArray<UIView *> *q = [NSMutableArray arrayWithObject:root];
        NSUInteger n = 0;
        while (q.count && n++ < 300) {
            UIView *v = q.lastObject;
            [q removeLastObject];
            [v setNeedsLayout];
            [q addObjectsFromArray:v.subviews];
        }
        [root layoutIfNeeded];
    }];
}

static void PACRunMaybeWithoutAnimation(void (^block)(void)) {
    if (CACurrentMediaTime() < gPACRotationQuietUntil) {
        [UIView performWithoutAnimation:^{
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            block();
            [CATransaction commit];
        }];
    } else {
        block();
    }
}

static void PACApplyRadiusToModule(UIViewController *m) {
    if (!m || !m.view) return;
    if (PACIsLandscape()) return;
    objc_setAssociatedObject(m.view, kPACLandscapeCleanKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    NSString *mid = PACMid(m);
    if (!mid.length) return;

    if (PACModuleIsExpanded(m)) {
        if (objc_getAssociatedObject(m.view, kPACLastRadiusKey)) PACRestoreModuleRadius(m);
        return;
    }

    NSUInteger w = 1, h = 1;
    PACEffectiveSize(mid, &w, &h);
    CGFloat radius = PACRadiusForSize(w, h);

    CGSize moduleSize = m.view.bounds.size;
    if (moduleSize.width < 1.0 || moduleSize.height < 1.0) return;

    NSValue *last = objc_getAssociatedObject(m.view, kPACLastRadiusKey);
    BOOL animateRadius = last != nil && PACAnimationsAllowed();
    BOOL resizeSettling = gPACPendingResizeID != nil ||
                          (CACurrentMediaTime() - gPACPendingResizeLastTouch) < 1.4;
    if (last && !resizeSettling) {
        NSMapTable<UIView *, NSDictionary *> *styled = objc_getAssociatedObject(m.view, kPACOrigRadiiKey);
        for (UIView *v in styled.keyEnumerator.allObjects) {
            if (!v.window || !v.layer.masksToBounds) continue;
            BOOL sameSizeAsModule = fabs(CGRectGetWidth(v.bounds) - moduleSize.width) < 8.0 &&
                                    fabs(CGRectGetHeight(v.bounds) - moduleSize.height) < 8.0;
            if (sameSizeAsModule && fabs(v.layer.cornerRadius - radius) > 0.5) {
                last = nil;
                break;
            }
        }
    }
    if (last && !resizeSettling) {
        CGSize ls = last.CGSizeValue;
        if (fabs(ls.width  - moduleSize.width)  < 0.5 &&
            fabs(ls.height - moduleSize.height) < 0.5 &&
            fabs(m.view.layer.cornerRadius - radius) < 0.5) {
            return;
        }
    }
    objc_setAssociatedObject(m.view, kPACLastRadiusKey,
                             [NSValue valueWithCGSize:moduleSize],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    NSMapTable<UIView *, NSDictionary *> *orig = objc_getAssociatedObject(m.view, kPACOrigRadiiKey);
    if (!orig) {
        orig = [NSMapTable weakToStrongObjectsMapTable];
        objc_setAssociatedObject(m.view, kPACOrigRadiiKey, orig, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    PACRunMaybeWithoutAnimation(^{
        PACRememberLayerState(m.view, orig);
        PACSetRadius(m.view.layer, radius, animateRadius);

        UIView *buttonView = PACModuleButtonView(m.view);
        if (buttonView) {
            PACRememberLayerState(buttonView, orig);
            PACSetRadius(buttonView.layer, radius, animateRadius);
        }

        NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithArray:m.view.subviews];
        while (queue.count) {
            UIView *v = queue.lastObject;
            [queue removeLastObject];
            BOOL isPillName = (kClsCCUIButtonModuleView && [v isKindOfClass:kClsCCUIButtonModuleView]);
            if (!isPillName) {
                NSString *cls = NSStringFromClass(v.class);
                isPillName = [cls containsString:@"CCUIButtonModuleView"] ||
                             [cls containsString:@"CCUIContentModuleContentContainer"];
            }
            NSString *vcls = NSStringFromClass(v.class);
            if ([vcls hasPrefix:@"LG"] || [vcls containsString:@"LiquidGlass"]) {
                if (v.subviews.count) [queue addObjectsFromArray:v.subviews];
                continue;
            }
            CGFloat vw = CGRectGetWidth(v.bounds);
            CGFloat vh = CGRectGetHeight(v.bounds);
            BOOL fills = (fabs(vw - moduleSize.width)  < 8.0) &&
                         (fabs(vh - moduleSize.height) < 8.0);
            if (isPillName || fills) {
                PACRememberLayerState(v, orig);
                PACSetRadius(v.layer, radius, animateRadius);
            }
            if (v.subviews.count) [queue addObjectsFromArray:v.subviews];
        }
    });
}

static void PACRestoreModuleRadius(UIViewController *m) {
    if (!m || !m.view) return;
    objc_setAssociatedObject(m.view, kPACLastRadiusKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSMapTable<UIView *, NSDictionary *> *orig = objc_getAssociatedObject(m.view, kPACOrigRadiiKey);
    if (!orig) return;

    [UIView performWithoutAnimation:^{
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        for (UIView *v in orig.keyEnumerator.allObjects) {
            NSDictionary *st = [orig objectForKey:v];
            if (!st) continue;
            CGFloat vw = CGRectGetWidth(v.bounds);
            CGFloat vh = CGRectGetHeight(v.bounds);
            BOOL smallSquare = vw > 1.0 && vh > 1.0 && fabs(vw - vh) < 1.5 && MIN(vw, vh) <= 76.0;
            if (smallSquare) {
                v.layer.cornerRadius = MIN(vw, vh) * 0.5;
                v.layer.cornerCurve  = kCACornerCurveContinuous;
            } else {
                v.layer.cornerRadius = [st[@"r"] doubleValue];
                v.layer.cornerCurve  = st[@"curve"] ?: kCACornerCurveCircular;
            }
            v.layer.masksToBounds = [st[@"mask"] boolValue];
        }
        [CATransaction commit];
    }];
}

static void PACTearDownModule(UIViewController *m) {
    if (!m || !m.view) return;
    UIView *view = m.view;
    CGSize sz = view.bounds.size;
    NSValue *done = objc_getAssociatedObject(view, kPACLandscapeCleanKey);
    if (done && fabs(done.CGSizeValue.width  - sz.width)  < 0.5 &&
                fabs(done.CGSizeValue.height - sz.height) < 0.5) return;
    objc_setAssociatedObject(view, kPACLandscapeCleanKey, [NSValue valueWithCGSize:sz],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    [UIView performWithoutAnimation:^{
        [CATransaction begin];
        [CATransaction setDisableActions:YES];

        UIView *pres = objc_getAssociatedObject(view, kPACPresKey);
        [pres removeFromSuperview];
        objc_setAssociatedObject(view, kPACPresKey,     nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(view, kPACLastPresKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        PACStripChrome(m);
        PACRestoreModuleIcon(m);
        PACRestoreModuleRadius(m);

        [PACModuleButtonView(view) setNeedsLayout];

        [CATransaction commit];
    }];
}

static void PACTearDownAllModules(UIViewController *ov) {
    if (!ov) return;
    for (UIViewController *m in ModuleControllers(ov)) PACTearDownModule(m);
}

static BOOL PACWasResizedFromOneByOne(NSString *mid) {
    if (!mid.length) return NO;

    NSUInteger curW = 1, curH = 1;
    PACPresentationSize(mid, &curW, &curH);
    if (curW == 1 && curH == 1) return NO;

    NSArray<NSNumber *> *known = PACKnownBaseSize(mid);
    if (known.count >= 2) {
        return (known[0].integerValue == 1 && known[1].integerValue == 1);
    }

    NSMutableSet<NSString *> *resized = objc_getAssociatedObject(UIApplication.sharedApplication, kPACResizedSetKey);
    if ([resized containsObject:mid]) return YES;

    if (gEditSizes[mid]) return YES;

    NSArray<NSNumber *> *base = gEditBaseSizes[mid];
    if (base.count >= 2) {
        return (base[0].integerValue == 1 && base[1].integerValue == 1);
    }
    return NO;
}

static UIViewPropertyAnimator *PACBezierAnimator(NSTimeInterval duration,
                                                 CGFloat c1x, CGFloat c1y,
                                                 CGFloat c2x, CGFloat c2y) {
    UICubicTimingParameters *timing =
        [[UICubicTimingParameters alloc] initWithControlPoint1:CGPointMake(c1x, c1y)
                                                controlPoint2:CGPointMake(c2x, c2y)];
    UIViewPropertyAnimator *a = [[UIViewPropertyAnimator alloc] initWithDuration:duration
                                                                timingParameters:timing];
    a.interruptible = YES;
    a.userInteractionEnabled = YES;
    return a;
}

static UIView *PACMakeBorder(void) {
    UIView *v = [UIView new];
    v.userInteractionEnabled = NO;
    v.backgroundColor = UIColor.clearColor;
    v.layer.cornerCurve = kCACornerCurveContinuous;
    v.layer.masksToBounds = NO;
    
    v.layer.borderColor = [UIColor colorWithWhite:0.75 alpha:0.35].CGColor;
    
    v.layer.borderWidth = kPACBorderWidth;
    v.layer.shadowColor = UIColor.blackColor.CGColor;
    v.layer.shadowOpacity = 0.08;
    v.layer.shadowRadius = 3.0;
    v.layer.shadowOffset = CGSizeZero;

    CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"opacity"];
    pulse.fromValue = @0.85;
    pulse.toValue = @1.0;
    pulse.duration = 1.6;
    pulse.autoreverses = YES;
    pulse.repeatCount = HUGE_VALF;
    pulse.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [v.layer addAnimation:pulse forKey:@"PACEditPulse"];
    return v;
}

static UIButton *PACMakeRemoveButton(NSString *mid) {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.tag = kPACRemoveTag;
    b.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.94];
    b.frame = CGRectMake(0, 0, 30, 30);
    b.layer.cornerRadius = 15.0;
    b.layer.cornerCurve = kCACornerCurveContinuous;
    b.layer.masksToBounds = NO;
    b.layer.shadowColor = UIColor.blackColor.CGColor;
    b.layer.shadowOpacity = 0.14;
    b.layer.shadowRadius = 4.0;
    b.layer.shadowOffset = CGSizeMake(0, 1);

    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration
        configurationWithPointSize:15 weight:UIImageSymbolWeightBold];
    UIImageView *icon = [[UIImageView alloc]
        initWithImage:[UIImage systemImageNamed:@"minus" withConfiguration:cfg]];
    icon.tintColor = [UIColor colorWithWhite:0.10 alpha:0.85];
    icon.contentMode = UIViewContentModeCenter;
    icon.userInteractionEnabled = NO;
    icon.frame = b.bounds;
    icon.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [b addSubview:icon];

    objc_setAssociatedObject(b, kPACMidKey, mid, OBJC_ASSOCIATION_COPY_NONATOMIC);
    return b;
}

static UIButton *PACMakeResizeButton(NSString *mid) {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.tag = kPACResizeTag;
    b.backgroundColor = UIColor.clearColor;
    b.frame = CGRectMake(0, 0, 42, 42);

    UIBezierPath *cornerPath = [UIBezierPath bezierPath];
    [cornerPath moveToPoint:CGPointMake(20.29, 40.01)];
    [cornerPath addCurveToPoint:CGPointMake(40.01, 20.29)
                  controlPoint1:CGPointMake(31.20, 40.01)
                  controlPoint2:CGPointMake(40.01, 31.20)];

    UIVisualEffectView *material = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialLight]];
    material.frame = b.bounds;
    material.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    material.userInteractionEnabled = NO;
    CAShapeLayer *materialMask = [CAShapeLayer layer];
    materialMask.path = cornerPath.CGPath;
    materialMask.fillColor = UIColor.clearColor.CGColor;
    materialMask.strokeColor = UIColor.blackColor.CGColor;
    materialMask.lineWidth = 12.0;
    materialMask.lineCap = kCALineCapRound;
    materialMask.lineJoin = kCALineJoinRound;
    material.layer.mask = materialMask;
    [b addSubview:material];

    CAShapeLayer *pill = [CAShapeLayer layer];
    pill.path = cornerPath.CGPath;
    pill.fillColor = UIColor.clearColor.CGColor;
    pill.strokeColor = [UIColor.whiteColor colorWithAlphaComponent:0.82].CGColor;
    pill.lineWidth = 12.5;
    pill.lineCap = kCALineCapRound;
    pill.lineJoin = kCALineJoinRound;
    [b.layer addSublayer:pill];

    objc_setAssociatedObject(b, kPACMidKey, mid, OBJC_ASSOCIATION_COPY_NONATOMIC);
    return b;
}

static UIButton *PACMakeResetButton(void) {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.tag = kPACResetTag;
    b.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.90];
    b.layer.cornerRadius = 20.0;
    b.layer.cornerCurve = kCACornerCurveContinuous;
    b.layer.masksToBounds = YES;

    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightSemibold];
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"arrow.counterclockwise" withConfiguration:cfg]];
    icon.tintColor = UIColor.whiteColor;
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.userInteractionEnabled = NO;
    icon.tag = 9001;

    UILabel *label = [[UILabel alloc] init];
    label.text = @"Reset Layout";
    label.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    label.textColor = UIColor.whiteColor;
    label.userInteractionEnabled = NO;
    label.tag = 9002;

    CGSize textSize = [label sizeThatFits:CGSizeMake(300, 20)];
    CGFloat iconSide = 18.0;
    CGFloat gap = 7.0;
    CGFloat padX = 16.0;
    CGFloat height = 40.0;
    CGFloat width = padX + iconSide + gap + textSize.width + padX;

    b.bounds = CGRectMake(0, 0, width, height);
    icon.frame = CGRectMake(padX, (height - iconSide) * 0.5, iconSide, iconSide);
    label.frame = CGRectMake(padX + iconSide + gap, 0, textSize.width, height);
    [b addSubview:icon];
    [b addSubview:label];
    return b;
}

static void PACAnimateChromeEntry(UIView *chrome) {
    if (!chrome) return;
    chrome.transform = CGAffineTransformMakeScale(0.82, 0.82);
    UIViewPropertyAnimator *anim = PACBezierAnimator(0.45, 0.32, 0.72, 0.0, 1.0);
    [anim addAnimations:^{
        chrome.transform = CGAffineTransformIdentity;
    }];
    [anim startAnimation];
}

static void PACAnimateChromeEntryDelayed(UIView *chrome, NSTimeInterval delay) {
    if (!chrome) return;
    chrome.transform = CGAffineTransformMakeScale(0.4, 0.4);
    chrome.alpha = 0.0;
    UIViewPropertyAnimator *anim = PACBezierAnimator(0.42, 0.32, 0.72, 0.0, 1.0);
    [anim addAnimations:^{
        chrome.transform = CGAffineTransformIdentity;
        chrome.alpha = 1.0;
    }];
    [anim startAnimationAfterDelay:delay];
}

#pragma mark - Add a Control

static void PACLog(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);
static void PACLog(NSString *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSString *dir = @"/var/mobile/Library/CCock26";
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *path = [dir stringByAppendingPathComponent:@"log.txt"];
    NSString *old = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] ?: @"";
    if (old.length > 20000) old = [old substringFromIndex:old.length - 10000];
    [[old stringByAppendingFormat:@"%@ %@\n", [NSDate date], msg] writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

static id PACModuleRepository(void) {
    Class cls = NSClassFromString(@"CCUIModuleInstanceManager");
    SEL sel = NSSelectorFromString(@"sharedInstance");
    id mgr = (cls && [cls respondsToSelector:sel]) ? ((id (*)(id, SEL))objc_msgSend)(cls, sel) : nil;
    if (!mgr) return nil;
    @try { return [mgr valueForKey:@"_repository"]; } @catch (__unused NSException *e) {}
    return nil;
}

static void PACCollectIdentifiers(id container, NSMutableOrderedSet<NSString *> *out) {
    if ([container isKindOfClass:NSDictionary.class]) {
        for (id k in [(NSDictionary *)container allKeys]) if ([k isKindOfClass:NSString.class]) [out addObject:k];
    } else if ([container isKindOfClass:NSArray.class] || [container isKindOfClass:NSSet.class] ||
               [container isKindOfClass:NSOrderedSet.class]) {
        for (id k in container) if ([k isKindOfClass:NSString.class]) [out addObject:k];
    }
}

// Every module the Control Center knows about that is not on the screen right now.
static NSArray<NSString *> *PACAvailableModuleIdentifiers(void) {
    NSMutableOrderedSet<NSString *> *all = [NSMutableOrderedSet orderedSet];
    id prov = PACSettingsProvider();
    for (NSString *name in @[@"orderedUserDisabledModuleIdentifiers", @"userDisabledModuleIdentifiers",
                             @"disabledModuleIdentifiers"]) {
        SEL sel = NSSelectorFromString(name);
        if (prov && [prov respondsToSelector:sel]) {
            PACCollectIdentifiers(((id (*)(id, SEL))objc_msgSend)(prov, sel), all);
        }
    }
    id repo = PACModuleRepository();
    if (repo) {
        for (NSString *key in @[@"moduleIdentifiers", @"allModuleIdentifiers", @"loadableModuleIdentifiers",
                                @"moduleMetadataByIdentifier", @"_moduleMetadataByIdentifier"]) {
            @try { PACCollectIdentifiers([repo valueForKey:key], all); } @catch (__unused NSException *e) {}
        }
    }
    if (!all.count) {
        NSString *dir = @"/System/Library/ControlCenter/Bundles";
        for (NSString *file in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil]) {
            if (![file.pathExtension isEqualToString:@"bundle"]) continue;
            NSBundle *b = [NSBundle bundleWithPath:[dir stringByAppendingPathComponent:file]];
            if (b.bundleIdentifier.length) [all addObject:b.bundleIdentifier];
        }
    }
    // Connectivity and Music are fixed modules, so the settings provider never lists them as available.
    [all addObject:@"com.apple.control-center.ConnectivityModule"];
    [all addObject:@"com.apple.mediaremote.controlcenter.nowplaying"];
    NSArray<NSString *> *enabled = PACProviderOrderedIdentifiers() ?: @[];
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    for (NSString *mid in all) {
        // Connectivity and Music stay in the list even when already on the grid; picking one moves it to the first free spot
        BOOL alwaysListed = [mid isEqualToString:@"com.apple.control-center.ConnectivityModule"] ||
                            [mid isEqualToString:@"com.apple.mediaremote.controlcenter.nowplaying"];
        if (!alwaysListed && [enabled containsObject:mid]) continue;
        if ([mid containsString:@"SilenceCalls"]) continue;
        [result addObject:mid];
    }
    return result;
}

static NSString *PACNameForIdentifier(NSString *mid) {
    if (!mid.length) return @"Control";
    NSString *lower = mid.lowercaseString;
    if ([lower containsString:@"screencapture"]) return @"Screen Recording";
    if ([lower containsString:@"control-center.displaymodule"]) return @"Brightness";
    if ([lower containsString:@"controlcenter.audio"]) return @"Volume";
    if ([lower containsString:@"connectivitymodule"]) return @"Connectivity";
    if ([lower containsString:@"controlcenter.nowplaying"]) return @"Music Player";

    Class pm = NSClassFromString(@"CCSModuleProviderManager");
    if (pm && [pm respondsToSelector:NSSelectorFromString(@"sharedInstance")]) {
        id mgr = ((id (*)(id, SEL))objc_msgSend)(pm, NSSelectorFromString(@"sharedInstance"));
        SEL dn = NSSelectorFromString(@"displayNameForModuleIdentifier:");
        if (mgr && [mgr respondsToSelector:dn]) {
            id n = ((id (*)(id, SEL, id))objc_msgSend)(mgr, dn, mid);
            if ([n isKindOfClass:NSString.class] && [n length]) return n;
        }
    }

    id repo = PACModuleRepository();
    SEL ms = NSSelectorFromString(@"moduleMetadataForModuleIdentifier:");
    if (repo && [repo respondsToSelector:ms]) {
        id meta = ((id (*)(id, SEL, id))objc_msgSend)(repo, ms, mid);
        NSURL *url = nil;
        @try { id v = [meta valueForKey:@"moduleBundleURL"]; if ([v isKindOfClass:NSURL.class]) url = v; }
        @catch (__unused NSException *e) {}
        NSBundle *bundle = url ? [NSBundle bundleWithURL:url] : nil;
        NSString *name = PACBundleDisplayName(bundle);
        if (name.length) return name;
    }

    NSString *last = [mid componentsSeparatedByString:@"."].lastObject;
    if ([last hasSuffix:@"Module"] && last.length > 6) last = [last substringToIndex:last.length - 6];
    if ([last hasSuffix:@"UIModule"] && last.length > 8) last = [last substringToIndex:last.length - 8];
    if (!last.length) return @"Control";
    NSMutableString *result = [NSMutableString string];
    for (NSUInteger i = 0; i < last.length; i++) {
        unichar c = [last characterAtIndex:i];
        if (i > 0 && [[NSCharacterSet uppercaseLetterCharacterSet] characterIsMember:c]) [result appendString:@" "];
        [result appendFormat:@"%C", c];
    }
    return result.length ? result : @"Control";
}

// Ask the Control Center to load the modules again after the enabled list changed (same call CCSupport uses).
static void PACReloadModuleRepository(void) {
    id repo = PACModuleRepository();
    if (!repo) { PACLog(@"reload: no repository"); return; }
    SEL direct = NSSelectorFromString(@"_updateAllModuleMetadata");
    SEL queued = NSSelectorFromString(@"_queue_updateAllModuleMetadata");
    if ([repo respondsToSelector:direct]) {
        ((void (*)(id, SEL))objc_msgSend)(repo, direct);
        PACLog(@"reload: _updateAllModuleMetadata");
    } else if ([repo respondsToSelector:queued]) {
        dispatch_queue_t q = nil;
        @try { q = [repo valueForKey:@"_queue"]; } @catch (__unused NSException *e) {}
        if (q) {
            dispatch_async(q, ^{ ((void (*)(id, SEL))objc_msgSend)(repo, queued); });
            PACLog(@"reload: _queue_updateAllModuleMetadata");
        } else {
            PACLog(@"reload: repository has no queue");
        }
    } else {
        PACLog(@"reload: repository has no update method");
    }
}

static void PACLogMethods(Class cls) {
    if (!cls) return;
    unsigned int n = 0;
    Method *list = class_copyMethodList(cls, &n);
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (unsigned int i = 0; i < n; i++) {
        NSString *s = NSStringFromSelector(method_getName(list[i]));
        NSString *l = s.lowercaseString;
        if ([l containsString:@"update"] || [l containsString:@"reload"] || [l containsString:@"refresh"] ||
            [l containsString:@"modulesettings"]) [names addObject:s];
    }
    free(list);
    PACLog(@"%@: %@", NSStringFromClass(cls), [names componentsJoinedByString:@", "]);
}


#pragma mark - copies (a second Connectivity or Music Player on another page)

static const NSInteger kPACCloneTag   = 182200;
static const NSInteger kPACCloneBgTag = 182201;
static const void *kPACCloneIDKey = &kPACCloneIDKey;
static NSMutableArray<NSMutableDictionary *> *gPACClones;      // {id, mid, c, a, w, h}

static void PACEnsureClones(void) {
    if (gPACClones) return;
    gPACClones = [NSMutableArray array];
    CFPropertyListRef v = CFPreferencesCopyAppValue(CFSTR("EditClones"), CFSTR("pawxed.ccock18.preferences"));
    if (v && CFGetTypeID(v) == CFArrayGetTypeID()) {
        for (id d in (__bridge NSArray *)v) {
            if ([d isKindOfClass:NSDictionary.class]) [gPACClones addObject:[d mutableCopy]];
        }
    }
    if (v) CFRelease(v);
}

static void PACSaveClones(void) {
    PACEnsureClones();
    CFPreferencesSetAppValue(CFSTR("EditClones"), (__bridge CFPropertyListRef)[gPACClones copy], CFSTR("pawxed.ccock18.preferences"));
    CFPreferencesAppSynchronize(CFSTR("pawxed.ccock18.preferences"));
}

// Where the grid starts inside the collection view (page independent), cached for moments when modules are moving.
static BOOL PACRawGridBase(UIViewController *ov, CGFloat *ox, CGFloat *oy) {
    static CGFloat cx = 0, cy = 0;
    static BOOL have = NO;
    PACRefreshGridConstants();
    PACEnsureStore();
    if (!gPACPendingResizeID && !gPageAnimating) {
        CGFloat bx = CGFLOAT_MAX, by = CGFLOAT_MAX;
        for (UIViewController *m in ModuleControllers(ov)) {
            NSString *mid = PACMid(m);
            NSArray<NSNumber *> *o = mid.length ? PACGetOrigin(mid) : nil;
            CGRect raw;
            if (o.count < 2 || !PACRawFrame(m, ov, &raw) || CGRectIsEmpty(raw)) continue;
            CGFloat x = raw.origin.x - (CGFloat)o[0].unsignedIntegerValue * kPACStep;
            CGFloat y = raw.origin.y - (CGFloat)o[1].unsignedIntegerValue * kPACStep;
            if (x < bx) bx = x;
            if (y < by) by = y;
        }
        if (bx != CGFLOAT_MAX) { cx = bx; cy = by; have = YES; }
    }
    if (!have) return NO;
    *ox = cx; *oy = cy;
    return YES;
}

static void PACRemoveCloneChrome(UIView *cl) {
    [objc_getAssociatedObject(cl, kPACBorderKey) removeFromSuperview];
    [objc_getAssociatedObject(cl, kPACRemoveKey) removeFromSuperview];
    objc_setAssociatedObject(cl, kPACBorderKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(cl, kPACRemoveKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void PACCloneChromeToFront(UIViewController *ov) {
    UIView *cv = ModuleCollection(ov).view;
    for (UIView *cl in cv.subviews) {
        if (cl.tag != kPACCloneTag) continue;
        UIView *rm = objc_getAssociatedObject(cl, kPACRemoveKey);
        if (rm.superview == ov.view) [ov.view bringSubviewToFront:rm];
    }
}

void PACCSyncClones(UIViewController *ov, BOOL animated) {
    static BOOL busy = NO;
    if (busy || !ov || !ov.view) return;
    UIView *cv = ModuleCollection(ov).view;
    if (!cv) return;
    busy = YES;
    PACEnsureClones();

    NSMutableDictionary<NSString *, UIView *> *have = [NSMutableDictionary dictionary];
    for (UIView *sv in [cv.subviews copy]) {
        if (sv.tag != kPACCloneTag) continue;
        NSString *cid = objc_getAssociatedObject(sv, kPACCloneIDKey);
        NSDictionary *d = nil;
        for (NSDictionary *c in gPACClones) if ([c[@"id"] isEqualToString:cid ?: @""]) { d = c; break; }
        if (!d) { PACRemoveCloneChrome(sv); [sv removeFromSuperview]; continue; }
        have[cid] = sv;
    }

    CGFloat bx = 0, by = 0;
    BOOL ok = !PACIsLandscape() && PACRawGridBase(ov, &bx, &by);
    UIView *connHost = nil;
    for (UIViewController *m in ModuleControllers(ov)) {
        NSString *mid = PACMid(m);
        if (mid.length && PACCBigKind(mid) == 1) { connHost = m.view; break; }
    }

    CATransform3D sub = cv.layer.sublayerTransform;
    for (NSDictionary *d in gPACClones) {
        NSString *cid = d[@"id"];
        NSString *mid = d[@"mid"];
        int kind = PACCBigKind(mid);
        UIView *cl = have[cid];
        if (!ok || !kind) { cl.hidden = YES; PACRemoveCloneChrome(cl); continue; }
        NSUInteger c = [d[@"c"] unsignedIntegerValue], a = [d[@"a"] unsignedIntegerValue];
        NSUInteger w = [d[@"w"] unsignedIntegerValue], h = [d[@"h"] unsignedIntegerValue];

        if (!cl) {
            cl = PACCBigNewClone(kind);
            cl.tag = kPACCloneTag;
            cl.clipsToBounds = YES;
            objc_setAssociatedObject(cl, kPACCloneIDKey, cid, OBJC_ASSOCIATION_COPY_NONATOMIC);
            UIVisualEffectView *bg = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialDark]];
            bg.tag = kPACCloneBgTag;
            bg.userInteractionEnabled = NO;
            [cl addSubview:bg];
            [cl sendSubviewToBack:bg];
            [cv addSubview:cl];
        }
        cl.hidden = NO;
        CGRect f = CGRectMake(bx + (CGFloat)c * kPACStep, by + (CGFloat)a * kPACStep,
                              (CGFloat)w * kPACStep - kPACgap, (CGFloat)h * kPACStep - kPACgap);
        if (!CGRectEqualToRect(cl.frame, f)) cl.frame = f;
        UIView *bg = [cl viewWithTag:kPACCloneBgTag];
        if (bg) { if (!CGRectEqualToRect(bg.frame, cl.bounds)) bg.frame = cl.bounds; [cl sendSubviewToBack:bg]; }
        cl.layer.cornerRadius = kPACCell * 0.5;
        cl.layer.cornerCurve = kCACornerCurveContinuous;
        cl.userInteractionEnabled = !gEditModeActive;
        PACCBigConfigureClone(cl, kind, w, h, connHost);

        BOOL onPage = ((NSInteger)(a / kPACStride) == gCurrentPage);
        CGFloat alpha = onPage ? 1.0 : 0.0;
        if (fabs(cl.alpha - alpha) > 0.01) {
            if (animated) [UIView animateWithDuration:0.35 delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{ cl.alpha = alpha; } completion:nil];
            else cl.alpha = alpha;
        }

        // edit mode: outline and the minus button, like on a real module
        if (gEditModeActive && onPage) {
            CGRect raw = f;
            raw.origin.x += sub.m41;
            raw.origin.y += sub.m42;
            CGRect vis = [cv convertRect:raw toView:ov.view];
            UIView *border = objc_getAssociatedObject(cl, kPACBorderKey);
            if (!border) {
                border = PACMakeBorder();
                objc_setAssociatedObject(cl, kPACBorderKey, border, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            if (border.superview != ov.view) [ov.view addSubview:border];
            border.frame = CGRectInset(vis, -kPACBorderInset, -kPACBorderInset);
            border.layer.cornerRadius = kPACCell * 0.5 + kPACBorderInset;
            border.hidden = NO;
            UIButton *rm = objc_getAssociatedObject(cl, kPACRemoveKey);
            if (!rm) {
                rm = PACMakeRemoveButton([@"clone:" stringByAppendingString:cid]);
                id proxy = ((id (*)(id, SEL))objc_msgSend)(NSClassFromString(@"PACEditProxy"), NSSelectorFromString(@"shared"));
                [rm addTarget:proxy action:NSSelectorFromString(@"removeTap:") forControlEvents:UIControlEventTouchUpInside];
                objc_setAssociatedObject(cl, kPACRemoveKey, rm, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            if (rm.superview != ov.view) [ov.view addSubview:rm];
            rm.frame = CGRectMake(vis.origin.x - 8.0, vis.origin.y - 8.0, 30.0, 30.0);
            rm.hidden = NO;
        } else {
            PACRemoveCloneChrome(cl);
        }
    }
    if (gEditModeActive) PACCloneChromeToFront(ov);
    busy = NO;
}

// First free cell of a page, reading row by row from the top left (so a new control lands at the start).
static BOOL PACFirstFreeCell(NSDictionary<NSString *, NSValue *> *occupied, NSUInteger w, NSUInteger h,
                             NSUInteger maxRow, NSUInteger *outCol, NSUInteger *outRow) {
    if (w == 0 || h == 0 || w > kPACCols || h > kPACRows) return NO;
    NSUInteger maxC = kPACCols - w;
    for (NSUInteger r = 0; r <= maxRow; r++) {
        for (NSUInteger c = 0; c <= maxC; c++) {
            PACRect t = {c, r, w, h};
            BOOL ok = YES;
            for (NSValue *v in occupied.allValues) {
                PACRect o = {};
                [v getValue:&o];
                if (PACRectsOverlap(t, o)) { ok = NO; break; }
            }
            if (ok) { *outCol = c; *outRow = r; return YES; }
        }
    }
    return NO;
}

static BOOL PACFindSlot(NSString *mid, NSUInteger w, NSUInteger h, UIViewController *ov,
                        NSUInteger *outCol, NSUInteger *outAbs, NSUInteger *outPage) {
    PACRefreshGridConstants();
    PACEnsureStore();
    NSMutableDictionary<NSNumber *, NSMutableDictionary<NSString *, NSValue *> *> *pages = [NSMutableDictionary dictionary];
    for (UIViewController *m in ModuleControllers(ov)) {
        NSString *other = PACMid(m);
        if (!other.length || [other isEqualToString:mid]) continue;
        PACEnsureBaseSize(m, ov);
        NSArray<NSNumber *> *o = PACGetOrigin(other);
        if (o.count < 2) continue;
        NSUInteger c = o[0].unsignedIntegerValue;
        NSUInteger a = o[1].unsignedIntegerValue;
        NSUInteger ow = 1, oh = 1;
        PACEffectiveSize(other, &ow, &oh);
        PACRect pr = {c, a % kPACStride, ow, oh};
        NSNumber *pn = @(a / kPACStride);
        NSMutableDictionary *map = pages[pn];
        if (!map) { map = [NSMutableDictionary dictionary]; pages[pn] = map; }
        map[other] = [NSValue value:&pr withObjCType:@encode(PACRect)];
    }
    PACEnsureClones();
    for (NSDictionary *cd in gPACClones) {
        NSUInteger a = [cd[@"a"] unsignedIntegerValue];
        PACRect pr = {[cd[@"c"] unsignedIntegerValue], a % kPACStride, [cd[@"w"] unsignedIntegerValue], [cd[@"h"] unsignedIntegerValue]};
        NSNumber *pn = @(a / kPACStride);
        NSMutableDictionary *map = pages[pn];
        if (!map) { map = [NSMutableDictionary dictionary]; pages[pn] = map; }
        map[[@"clone:" stringByAppendingString:cd[@"id"]]] = [NSValue value:&pr withObjCType:@encode(PACRect)];
    }

    // Page 0 comes first; then the pages the user added. The media / promo pages cannot hold controls.
    NSMutableArray<NSNumber *> *order = [NSMutableArray arrayWithObject:@0];
    for (NSUInteger p = PACBasePageCount(); p < PACBasePageCount() + gPACUserPages; p++) [order addObject:@(p)];
    NSInteger cur = gCurrentPage;
    if (cur > 0 && PACIsUserPage((NSUInteger)cur)) {      // looking at a user page: fill that one first
        [order removeObject:@(cur)];
        [order insertObject:@(cur) atIndex:0];
    }

    NSUInteger cap = PACVisibleRowCap(ov);
    for (NSNumber *pn in order) {
        NSUInteger p = pn.unsignedIntegerValue;
        NSUInteger maxRow = (cap + 1 >= h) ? cap + 1 - h : 0;
        if (kPACRows >= h) maxRow = MIN(maxRow, kPACRows - h);
        NSUInteger oc = 0, orr = 0;
        if (PACFirstFreeCell(pages[pn] ?: @{}, w, h, maxRow, &oc, &orr)) {
            if (outCol) *outCol = oc;
            if (outAbs) *outAbs = p * kPACStride + orr;
            if (outPage) *outPage = p;
            return YES;
        }
    }
    return NO;
}

static BOOL PACPlaceNewModule(NSString *mid, NSUInteger w, NSUInteger h, UIViewController *ov, NSUInteger *outPage) {
    NSUInteger oc = 0, oa = 0;
    if (!PACFindSlot(mid, w, h, ov, &oc, &oa, outPage)) return NO;
    PACSetOrigin(mid, @[@(oc), @(oa)]);
    PACInvalidateOtherOrientationOriginForModule(mid);
    return YES;
}

static void PACShowToast(UIViewController *ov, NSString *text) {
    if (!ov.view || !text.length) return;
    [[ov.view viewWithTag:kPACToastTag] removeFromSuperview];

    UIVisualEffectView *pill = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThickMaterialDark]];
    pill.tag = kPACToastTag;
    pill.userInteractionEnabled = NO;
    pill.layer.cornerRadius = 20.0;
    pill.layer.cornerCurve = kCACornerCurveContinuous;
    pill.layer.masksToBounds = YES;

    UILabel *label = [UILabel new];
    label.text = text;
    label.textColor = UIColor.whiteColor;
    label.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    label.numberOfLines = 2;
    label.textAlignment = NSTextAlignmentCenter;
    CGFloat maxW = CGRectGetWidth(ov.view.bounds) - 64.0;
    CGSize fit = [label sizeThatFits:CGSizeMake(maxW - 32.0, 80.0)];
    CGFloat w = MIN(maxW, fit.width + 32.0), h = fit.height + 20.0;
    pill.bounds = CGRectMake(0, 0, w, h);
    label.frame = CGRectMake(16.0, 10.0, w - 32.0, fit.height);
    [pill.contentView addSubview:label];

    CGFloat safeBottom = ov.view.safeAreaInsets.bottom;
    if (safeBottom < 1.0) safeBottom = 20.0;
    pill.center = CGPointMake(CGRectGetMidX(ov.view.bounds), CGRectGetHeight(ov.view.bounds) - safeBottom - 104.0);
    pill.alpha = 0.0;
    pill.transform = CGAffineTransformMakeScale(0.8, 0.8);
    [ov.view addSubview:pill];

    [UIView animateWithDuration:0.5 delay:0 usingSpringWithDamping:0.62 initialSpringVelocity:0.6 options:0 animations:^{
        pill.alpha = 1.0;
        pill.transform = CGAffineTransformIdentity;
    } completion:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [UIView animateWithDuration:0.25 animations:^{ pill.alpha = 0.0; } completion:^(BOOL f) { [pill removeFromSuperview]; }];
    });
}

static UIButton *PACMakeAddButton(void) {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.tag = kPACAddTag;
    b.layer.cornerCurve = kCACornerCurveContinuous;
    b.layer.masksToBounds = YES;

    UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThickMaterialDark]];
    blur.userInteractionEnabled = NO;
    [b addSubview:blur];

    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightSemibold];
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"plus.circle.fill" withConfiguration:cfg]];
    icon.tintColor = UIColor.whiteColor;
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.userInteractionEnabled = NO;

    UILabel *label = [UILabel new];
    label.text = @"Add a Control";
    label.font = [UIFont systemFontOfSize:19 weight:UIFontWeightBold];
    label.textColor = UIColor.whiteColor;
    label.userInteractionEnabled = NO;

    CGSize textSize = [label sizeThatFits:CGSizeMake(300, 30)];
    CGFloat height = 54.0, iconSide = 24.0, gap = 10.0, padX = 24.0;
    CGFloat width = padX + iconSide + gap + textSize.width + padX;
    b.bounds = CGRectMake(0, 0, width, height);
    b.layer.cornerRadius = height * 0.5;
    blur.frame = b.bounds;
    icon.frame = CGRectMake(padX, (height - iconSide) * 0.5, iconSide, iconSide);
    label.frame = CGRectMake(padX + iconSide + gap, 0, textSize.width, height);
    [b addSubview:icon];
    [b addSubview:label];
    return b;
}

static UIButton *PACMakeRoundButton(NSString *symbol, CGFloat side, CGFloat pointSize, NSInteger tag) {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.tag = tag;
    b.bounds = CGRectMake(0, 0, side, side);
    b.layer.cornerRadius = side * 0.5;
    b.layer.masksToBounds = YES;

    UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThickMaterialDark]];
    blur.frame = b.bounds;
    blur.userInteractionEnabled = NO;
    [b addSubview:blur];

    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:pointSize weight:UIImageSymbolWeightSemibold];
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol withConfiguration:cfg]];
    icon.tintColor = UIColor.whiteColor;
    icon.contentMode = UIViewContentModeCenter;
    icon.frame = b.bounds;
    icon.userInteractionEnabled = NO;
    [b addSubview:icon];
    return b;
}

// "+" under the page dots: adds a new page.
static void PACPositionPageAddButton(UIViewController *ov) {
    UIView *ind = [ov.view viewWithTag:kPageIndicatorTag];
    UIView *plus = [ov.view viewWithTag:kPACPageAddTag];
    if (!ind || !plus) return;
    plus.center = CGPointMake(CGRectGetMidX(ind.frame), CGRectGetMaxY(ind.frame) + 30.0);
}

// Keeps the chrome of every module in step with the page the user is looking at while editing.
static NSTimer *gPACPageWatch = nil;
static NSInteger gPACLastPage = 0;

static void PACStopPageWatch(void) {
    [gPACPageWatch invalidate];
    gPACPageWatch = nil;
}

#pragma mark Picker

@interface PACAddPicker : UIView <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy) void (^onPick)(NSString *mid);
@property (nonatomic, copy) void (^onClose)(void);
- (instancetype)initWithFrame:(CGRect)frame items:(NSArray<NSDictionary *> *)items;
- (void)presentAnimated;
- (void)dismissAnimated:(void (^)(void))completion;
@end

@implementation PACAddPicker {
    NSArray<NSDictionary *> *_items;
    UIView *_dim;
    UIVisualEffectView *_sheet;
    UITableView *_table;
    CGFloat _sheetH;
}

- (instancetype)initWithFrame:(CGRect)frame items:(NSArray<NSDictionary *> *)items {
    if ((self = [super initWithFrame:frame])) {
        _items = items;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

        _dim = [[UIView alloc] initWithFrame:self.bounds];
        _dim.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.45];
        _dim.alpha = 0.0;
        _dim.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [_dim addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(closeTapped)]];
        [self addSubview:_dim];

        _sheet = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThickMaterialDark]];
        _sheet.layer.cornerRadius = 32.0;
        _sheet.layer.cornerCurve = kCACornerCurveContinuous;
        _sheet.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
        _sheet.layer.masksToBounds = YES;
        [self addSubview:_sheet];

        UILabel *title = [UILabel new];
        title.text = @"Add a Control";
        title.textColor = UIColor.whiteColor;
        title.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
        title.tag = 71;
        [_sheet.contentView addSubview:title];

        UIButton *close = [UIButton buttonWithType:UIButtonTypeCustom];
        close.tag = 72;
        close.tintColor = [UIColor colorWithWhite:1.0 alpha:0.55];
        [close setImage:[UIImage systemImageNamed:@"xmark.circle.fill"
                                 withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:28 weight:UIImageSymbolWeightRegular]]
               forState:UIControlStateNormal];
        [close addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
        [_sheet.contentView addSubview:close];

        _table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
        _table.backgroundColor = UIColor.clearColor;
        _table.separatorColor = [UIColor colorWithWhite:1.0 alpha:0.12];
        _table.rowHeight = 58.0;
        _table.dataSource = self;
        _table.delegate = self;
        _table.alwaysBounceVertical = YES;
        [_sheet.contentView addSubview:_table];

        if (!items.count) {
            UILabel *empty = [UILabel new];
            empty.tag = 73;
            empty.text = @"All controls are already added";
            empty.textColor = [UIColor colorWithWhite:1.0 alpha:0.6];
            empty.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
            empty.textAlignment = NSTextAlignmentCenter;
            [_sheet.contentView addSubview:empty];
        }
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = CGRectGetWidth(self.bounds), H = CGRectGetHeight(self.bounds);
    CGFloat safeBottom = self.safeAreaInsets.bottom;
    if (safeBottom < 1.0) safeBottom = 12.0;
    CGFloat want = 76.0 + MAX(1, (NSInteger)_items.count) * 58.0 + safeBottom + 8.0;
    _sheetH = MIN(H * 0.72, MAX(230.0, want));
    BOOL presented = (_sheet.transform.ty == 0.0);
    CGAffineTransform keep = _sheet.transform;
    _sheet.transform = CGAffineTransformIdentity;
    _sheet.frame = CGRectMake(0, H - _sheetH, w, _sheetH);
    _sheet.transform = presented ? CGAffineTransformIdentity : keep;

    [_sheet.contentView viewWithTag:71].frame = CGRectMake(24, 22, w - 100, 30);
    [_sheet.contentView viewWithTag:72].frame = CGRectMake(w - 24 - 36, 19, 36, 36);
    _table.frame = CGRectMake(0, 70, w, _sheetH - 70);
    _table.contentInset = UIEdgeInsetsMake(0, 0, safeBottom, 0);
    [_sheet.contentView viewWithTag:73].frame = CGRectMake(24, 100, w - 48, 24);
}

- (void)presentAnimated {
    [self layoutIfNeeded];
    _sheet.transform = CGAffineTransformMakeTranslation(0, _sheetH + 20.0);
    [UIView animateWithDuration:0.7 delay:0.0 usingSpringWithDamping:0.78 initialSpringVelocity:0.5
                        options:UIViewAnimationOptionAllowUserInteraction animations:^{
        self->_sheet.transform = CGAffineTransformIdentity;
        self->_dim.alpha = 1.0;
    } completion:nil];
}

- (void)dismissAnimated:(void (^)(void))completion {
    [UIView animateWithDuration:0.28 delay:0.0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        self->_sheet.transform = CGAffineTransformMakeTranslation(0, self->_sheetH + 20.0);
        self->_dim.alpha = 0.0;
    } completion:^(BOOL finished) {
        if (completion) completion();
    }];
}

- (void)closeTapped { if (self.onClose) self.onClose(); }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section { return (NSInteger)_items.count; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"pac"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"pac"];
        cell.backgroundColor = UIColor.clearColor;
        cell.textLabel.textColor = UIColor.whiteColor;
        cell.textLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightMedium];
        UIView *sel = [UIView new];
        sel.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.12];
        cell.selectedBackgroundView = sel;
        UIImageView *plus = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"plus.circle.fill"
            withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:24 weight:UIImageSymbolWeightRegular]]];
        plus.tintColor = [UIColor colorWithWhite:1.0 alpha:0.9];
        cell.accessoryView = plus;
    }
    cell.textLabel.text = _items[ip.row][@"name"];
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    NSString *mid = _items[ip.row][@"mid"];
    if (self.onPick && mid.length) self.onPick(mid);
}

@end

#pragma mark - Pages added by the user

extern "C" NSUInteger PACCUserPageCount(void) {
    PACEnsureUserPages();
    return gPACUserPages;
}

// Page (0 based) a module belongs to, from its saved grid position.
extern "C" NSInteger PACCModulePageForIdentifier(NSString *mid) {
    if (!mid.length) return 0;
    PACRefreshGridConstants();
    NSArray<NSNumber *> *o = PACGetOrigin(mid);
    if (o.count < 2) return 0;
    return (NSInteger)(o[1].unsignedIntegerValue / kPACStride);
}

@interface PACEditShield : UIView
@end

@implementation PACEditShield
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.hidden || self.alpha < 0.01 || !self.userInteractionEnabled) return nil;
    return self;
}
@end

@interface PACLiveGlassProxyView : UIView
@end

@implementation PACLiveGlassProxyView
+ (Class)layerClass {
    return kClsCABackdropLayer ?: [CALayer class];
}
@end

static UIImage *PACSnapshotContentOnly(UIView *src, BOOL liquidassActive) {
    CGSize sz = src.bounds.size;
    if (sz.width < 1 || sz.height < 1) return nil;

    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:sz];

    if (!liquidassActive) {
        return [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
            [src drawViewHierarchyInRect:CGRectMake(0, 0, sz.width, sz.height)
                     afterScreenUpdates:NO];
        }];
    }

    NSMutableArray<UIView *> *hidden = [NSMutableArray array];
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithArray:src.subviews];
    while (queue.count) {
        UIView *v = queue.lastObject;
        [queue removeLastObject];
        BOOL isMaterial = (kClsCABackdropLayer && [v.layer isKindOfClass:kClsCABackdropLayer]);
        if (!isMaterial) {
            NSString *cls = NSStringFromClass(v.class);
            isMaterial = [cls containsString:@"MTMaterial"] ||
                         [cls containsString:@"MaterialView"] ||
                         [cls containsString:@"Backdrop"] ||
                         [v isKindOfClass:UIVisualEffectView.class];
        }
        if (isMaterial) {
            if (!v.hidden && v.alpha > 0.01) {
                v.hidden = YES;
                [hidden addObject:v];
            }
        } else {
            if (v.subviews.count) [queue addObjectsFromArray:v.subviews];
        }
    }

    UIColor *savedBg = src.backgroundColor;
    src.backgroundColor = UIColor.clearColor;

    UIImage *result = [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [src drawViewHierarchyInRect:CGRectMake(0, 0, sz.width, sz.height)
                 afterScreenUpdates:YES];
    }];

    for (UIView *v in hidden) v.hidden = NO;
    src.backgroundColor = savedBg;
    return result;
}

static void PACBringChromeToFront(UIViewController *ov) {
    if (!ov || !ov.view) return;
    UIView *shield = [ov.view viewWithTag:kPACShieldTag];
    if (shield) [ov.view bringSubviewToFront:shield];
    for (UIViewController *m in ModuleControllers(ov)) {
        UIButton *rm = objc_getAssociatedObject(m.view, kPACRemoveKey);
        UIButton *rz = objc_getAssociatedObject(m.view, kPACResizeKey);
        if (rm) [ov.view bringSubviewToFront:rm];
        if (rz) [ov.view bringSubviewToFront:rz];
        UIView *pr = objc_getAssociatedObject(m.view, kPACPresKey);
        if (pr) [ov.view bringSubviewToFront:pr];
    }
    PACCloneChromeToFront(ov);
    UIView *rp = [ov.view viewWithTag:kPACResetTag];
    if (rp) [ov.view bringSubviewToFront:rp];
    { UIView *pacI = [ov.view viewWithTag:kPageIndicatorTag]; if (pacI && gEditModeActive) [ov.view bringSubviewToFront:pacI];
      UIView *pacG = [ov.view viewWithTag:kPACPageAddTag]; if (pacG) [ov.view bringSubviewToFront:pacG];
      UIView *pacL = [ov.view viewWithTag:kPACLayersTag]; if (pacL) [ov.view bringSubviewToFront:pacL];
      UIView *pacA = [ov.view viewWithTag:kPACAddTag]; if (pacA) [ov.view bringSubviewToFront:pacA];
      UIView *pacP = [ov.view viewWithTag:kPACPickerTag]; if (pacP) [ov.view bringSubviewToFront:pacP]; }
}

static UIView *PACModuleMoverView(UIViewController *m, UIViewController *col) {
    UIView *v = m.view;
    if (!v) return nil;
    UIView *stop = col.view;
    if (!stop) return v;
    UIView *cur = v;
    while (cur.superview && cur.superview != stop) cur = cur.superview;
    return cur.superview == stop ? cur : v;
}

static NSDictionary<NSString *, NSValue *> *PACCaptureModuleFrames(UIViewController *ov, NSString *excludeMid) {
    NSMutableDictionary<NSString *, NSValue *> *frames = [NSMutableDictionary dictionary];
    for (UIViewController *m in ModuleControllers(ov)) {
        NSString *mid = PACMid(m);
        if (!mid.length || [mid isEqualToString:excludeMid]) continue;
        CGRect f = PACVisibleFrame(m, ov);
        if (CGRectIsEmpty(f)) continue;
        frames[mid] = [NSValue valueWithCGRect:f];
    }
    return frames;
}

static BOOL PACSlideModules(UIViewController *ov, NSDictionary<NSString *, NSValue *> *oldFrames) {
    if (!ov || !oldFrames.count || !PACAnimationsAllowed()) return NO;
    UIViewController *col = ModuleCollection(ov);
    PACAnimSpec sp = PACResizeSpec();
    BOOL started = NO;
    for (UIViewController *m in ModuleControllers(ov)) {
        NSString *mid = PACMid(m);
        NSValue *oldValue = mid.length ? oldFrames[mid] : nil;
        if (!oldValue) continue;
        CGRect oldF = oldValue.CGRectValue;
        CGRect newF = PACVisibleFrame(m, ov);
        if (CGRectIsEmpty(newF)) continue;
        CGFloat dx = oldF.origin.x - newF.origin.x;
        CGFloat dy = oldF.origin.y - newF.origin.y;
        if (hypot(dx, dy) < 0.5) continue;

        UIView *mover = PACModuleMoverView(m, col);
        if (!mover) continue;
        if ([mover.layer animationForKey:@"position"]) continue;

        CABasicAnimation *running = (CABasicAnimation *)[mover.layer animationForKey:@"pac.slide"];
        if (running && [running.fromValue isKindOfClass:NSValue.class]) {
            CGPoint rf = [running.fromValue CGPointValue];
            if (hypot(rf.x - dx, rf.y - dy) < 0.5) continue;
        }

        CABasicAnimation *slide = [CABasicAnimation animationWithKeyPath:@"position"];
        slide.additive = YES;
        slide.fromValue = [NSValue valueWithCGPoint:CGPointMake(dx, dy)];
        slide.toValue = [NSValue valueWithCGPoint:CGPointZero];
        slide.duration = sp.duration;
        slide.timingFunction = PACResizeTiming(sp);
        [mover.layer addAnimation:slide forKey:@"pac.slide"];
        started = YES;
    }
    return started;
}

static void PACAnimateChromeRefreshExcluding(UIViewController *ov, NSString *excludeMid) {
    if (!ov || !ov.view || !gEditModeActive) return;
    PACAnimSpec sp = PACResizeSpec();
    UIViewPropertyAnimator *anim = PACBezierAnimator(sp.duration, sp.c1x, sp.c1y, sp.c2x, sp.c2y);
    [anim addAnimations:^{
        for (UIViewController *m in ModuleControllers(ov)) {
            if (excludeMid.length && [PACMid(m) isEqualToString:excludeMid]) continue;
            PACApplyChrome(m, ov);
        }
    }];
    [anim startAnimation];
    PACBringChromeToFront(ov);
}

static void PACAnimateChromeRefresh(UIViewController *ov) {
    PACAnimateChromeRefreshExcluding(ov, nil);
}

// Every module on the page being shown must have its border, remove button and resize handle in the right spot,
// whenever and however it got there (a control added to a new page, a page switch, a late layout).
static void PACSyncChromeToPage(UIViewController *ov) {
    if (!ov || !ov.view || !gEditModeActive || gPACPendingResizeID) return;
    for (UIViewController *m in ModuleControllers(ov)) {
        NSString *mid = PACMid(m);
        UIView *v = m.view;
        if (!mid.length || !v) continue;
        UIView *border = objc_getAssociatedObject(v, kPACBorderKey);
        UIButton *rm = objc_getAssociatedObject(v, kPACRemoveKey);
        UIButton *rz = objc_getAssociatedObject(v, kPACResizeKey);
        BOOL onThisPage = (PACCModulePageForIdentifier(mid) == gCurrentPage);
        if (!onThisPage) {
            border.hidden = YES; rm.hidden = YES; rz.hidden = YES;
            continue;
        }
        CGRect vis = PACVisibleFrame(m, ov);
        if (CGRectIsEmpty(vis)) continue;
        BOOL stale = !border || !rm || rm.hidden || border.hidden || rm.superview != ov.view ||
                     fabs(rm.frame.origin.x - (vis.origin.x - 8.0)) > 2.0 ||
                     fabs(rm.frame.origin.y - (vis.origin.y - 8.0)) > 2.0;
        if (!stale && PACModuleSupportsResizing(mid) && (!rz || rz.hidden || rz.superview != ov.view)) stale = YES;
        if (stale) PACApplyChrome(m, ov);
    }
    PACCSyncClones(ov, NO);
    PACBringChromeToFront(ov);
}

// Pages the user added but left empty go away when editing ends (the later pages move up).
static void PACPruneEmptyPages(UIViewController *ov) {
    if (ov) PACCSyncClones(ov, NO);
    if (!ov || PACIsLandscape()) return;
    PACEnsureUserPages();
    PACEnsureStore();
    PACRefreshGridConstants();
    NSUInteger base = PACBasePageCount();
    if (!gPACUserPages) return;

    NSMutableSet<NSNumber *> *used = [NSMutableSet set];
    for (UIViewController *m in ModuleControllers(ov)) {
        NSString *mid = PACMid(m);
        if (!mid.length) continue;
        NSArray<NSNumber *> *o = PACGetOrigin(mid);
        if (o.count >= 2) [used addObject:@(o[1].unsignedIntegerValue / kPACStride)];
    }
    PACEnsureClones();
    for (NSDictionary *cd in gPACClones) [used addObject:@([cd[@"a"] unsignedIntegerValue] / kPACStride)];

    NSInteger oldCur = gCurrentPage, newCur = gCurrentPage;
    BOOL changed = NO;
    for (NSUInteger p = base + gPACUserPages; p-- > base; ) {
        if ([used containsObject:@(p)]) continue;
        // move every control on a later page one page up
        for (NSString *key in gEditOrigins.allKeys) {
            if (![key hasPrefix:@"P|"]) continue;
            NSArray<NSNumber *> *o = gEditOrigins[key];
            if (o.count < 2) continue;
            NSUInteger a = o[1].unsignedIntegerValue;
            if (a / kPACStride > p) gEditOrigins[key] = @[o[0], @(a - kPACStride)];
        }
        for (NSMutableDictionary *cd in gPACClones) {
            NSUInteger a = [cd[@"a"] unsignedIntegerValue];
            if (a / kPACStride > p) cd[@"a"] = @(a - kPACStride);
        }
        NSMutableSet *shifted = [NSMutableSet set];
        for (NSNumber *u in used) [shifted addObject:(u.unsignedIntegerValue > p ? @(u.unsignedIntegerValue - 1) : u)];
        used = shifted;
        if (newCur == (NSInteger)p) newCur = 0;
        else if (newCur > (NSInteger)p) newCur--;
        gPACUserPages--;
        changed = YES;
    }
    if (!changed) return;
    PACSaveStore();
    PACSaveClones();
    PACSaveUserPages();

    UIViewController *col = ModuleCollection(ov);
    CGFloat span = PageSpan();
    if (col.view) {
        CATransform3D t = col.view.layer.sublayerTransform;
        t.m42 += (CGFloat)(oldCur - newCur) * span;
        col.view.layer.sublayerTransform = t;
    }
    gCurrentPage = newCur;
    [PACC.shared installPageIndicatorOnOverlay:ov];
    CCAPageIndicator *ind = (CCAPageIndicator *)[ov.view viewWithTag:kPageIndicatorTag];
    ind.currentPage = (NSUInteger)newCur;
    [ind layoutButtons];
    [PACC.shared syncModuleVisibilityForOverlay:ov animated:NO];
    id proxy = ((id (*)(id, SEL))objc_msgSend)(NSClassFromString(@"PACEditProxy"), NSSelectorFromString(@"shared"));
    ((void (*)(id, SEL, id))objc_msgSend)(proxy, NSSelectorFromString(@"relayout:"), ov);
}

static void PACStartPageWatch(UIViewController *ov) {
    PACStopPageWatch();
    gPACLastPage = gCurrentPage;
    __weak UIViewController *weakOv = ov;
    gPACPageWatch = [NSTimer scheduledTimerWithTimeInterval:0.2 repeats:YES block:^(NSTimer *t) {
        UIViewController *o = weakOv;
        if (!o || !gEditModeActive) { [t invalidate]; if (gPACPageWatch == t) gPACPageWatch = nil; return; }
        if (gCurrentPage == gPACLastPage) { PACSyncChromeToPage(o); return; }
        gPACLastPage = gCurrentPage;
        PACAnimateChromeRefresh(o);
        PACBringChromeToFront(o);
        for (NSNumber *d in @[@0.35, @0.7]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(d.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (!gEditModeActive) return;
                PACAnimateChromeRefresh(o);
                PACBringChromeToFront(o);
            });
        }
    }];
}

static void PACAdjustStatusBar(UIViewController *ov) {
    if (!ov) return;
    PACC *pacc = [PACC shared];
    if ([pacc respondsToSelector:@selector(adjustStatusBarForOverlay:)]) {
        [pacc adjustStatusBarForOverlay:ov];
    }
}

static void PACSettleEditLayoutEx(UIViewController *ov, BOOL refreshChrome) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!gEditModeActive) return;
        if (refreshChrome) PACAnimateChromeRefresh(ov);
        PACAdjustStatusBar(ov);
    });
    static const double delays[] = { 0.30, 0.65 };
    for (size_t i = 0; i < sizeof(delays) / sizeof(delays[0]); i++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delays[i] * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (!gEditModeActive) return;
            PACAdjustStatusBar(ov);
        });
    }
}

static void PACSettleEditLayout(UIViewController *ov) {
    PACSettleEditLayoutEx(ov, YES);
}

static void PACForceExitEdit(UIViewController *ov) {
    gEditModeActive = NO;
    gPACEditEpoch++;
    gPACPendingResizeID = nil;
    gPACPendingResizeSize = (CCUILayoutSize){0, 0};
    gPACPendingResizeLastTouch = 0;
    if (!ov || !ov.view) return;
    for (UIViewController *m in ModuleControllers(ov)) PACStripChrome(m);
    PACPruneEmptyPages(ov);
    [[ov.view viewWithTag:kPACShieldTag] removeFromSuperview];
    [[ov.view viewWithTag:kPACResetTag] removeFromSuperview];
    PACStopPageWatch();
    [[ov.view viewWithTag:kPACAddTag] removeFromSuperview];
    [[ov.view viewWithTag:kPACLayersTag] removeFromSuperview];
    [[ov.view viewWithTag:kPACPageAddTag] removeFromSuperview];
    [[ov.view viewWithTag:kPACPickerTag] removeFromSuperview];
    [[ov.view viewWithTag:kPACToastTag] removeFromSuperview];
    [[ov.view viewWithTag:kPACHintTag] removeFromSuperview];
    NSArray<UIGestureRecognizer *> *disabled = objc_getAssociatedObject(ov, kPACDisabledGesturesKey);
    for (UIGestureRecognizer *gr in disabled) gr.enabled = YES;
    objc_setAssociatedObject(ov, kPACDisabledGesturesKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIView *ind = [ov.view viewWithTag:kPageIndicatorTag];
    ind.userInteractionEnabled = YES;
    ind.alpha = 1.0;
}

@interface PACEditProxy : NSObject <UIGestureRecognizerDelegate>
+ (instancetype)shared;
- (void)bgHold:(UILongPressGestureRecognizer *)g;
- (void)shieldPan:(UIGestureRecognizer *)g;
- (void)shieldTap:(UITapGestureRecognizer *)g;
- (void)resizePan:(UIPanGestureRecognizer *)g;
- (void)removeTap:(UIButton *)b;
- (void)resetTap:(UIButton *)b;
- (void)addControlTap:(UIButton *)b;
- (void)addPageTap:(UIButton *)b;
- (void)layersTap:(UIButton *)b;
- (void)addModule:(NSString *)mid overlay:(UIViewController *)ov;
- (void)exitEditOn:(UIViewController *)ov;
- (void)compactGridAfterRemoval:(UIViewController *)ov;
- (void)relayout:(UIViewController *)ov;
- (BOOL)computeArrangementForMid:(NSString *)mid
                             col:(NSUInteger)col
                             row:(NSUInteger)row
                               w:(NSUInteger)w
                               h:(NSUInteger)h
                         overlay:(UIViewController *)ov;
- (void)commitResize:(NSString *)mid w:(NSUInteger)w h:(NSUInteger)h overlay:(UIViewController *)ov;
@end

static void PACAddCloneOf(NSString *mid, UIViewController *ov) {
    int kind = PACCBigKind(mid);
    if (!kind) return;
    NSUInteger w = 4, h = (kind == 1) ? 4 : 2;
    NSUInteger oc = 0, oa = 0, page = 0;
    BOOL placed = PACFindSlot(@"", w, h, ov, &oc, &oa, &page);
    if (!placed) {
        PACEnsureUserPages();
        if (PACBasePageCount() + gPACUserPages < kPACMaxPages) {
            gPACUserPages++;
            PACSaveUserPages();
            [PACC.shared installPageIndicatorOnOverlay:ov];
            PACPositionPageAddButton(ov);
            placed = PACFindSlot(@"", w, h, ov, &oc, &oa, &page);
        }
    }
    if (!placed) { PACShowToast(ov, @"No room left for another control"); return; }
    PACEnsureClones();
    NSString *cid = [NSString stringWithFormat:@"%llx", (unsigned long long)(CACurrentMediaTime() * 1000.0)];
    [gPACClones addObject:[@{@"id": cid, @"mid": mid, @"c": @(oc), @"a": @(oa), @"w": @(w), @"h": @(h)} mutableCopy]];
    PACSaveClones();
    PACCSyncClones(ov, NO);
    PACLog(@"add copy of %@ at page %lu", mid, (unsigned long)page);

    UIView *cl = nil;
    for (UIView *sv in ModuleCollection(ov).view.subviews) {
        if (sv.tag == kPACCloneTag && [objc_getAssociatedObject(sv, kPACCloneIDKey) isEqualToString:cid]) { cl = sv; break; }
    }
    if (cl) {
        cl.transform = CGAffineTransformMakeScale(0.4, 0.4);
        [UIView animateWithDuration:0.6 delay:0 usingSpringWithDamping:0.55 initialSpringVelocity:0.8 options:0 animations:^{
            cl.transform = CGAffineTransformIdentity;
        } completion:nil];
    }
    if (page != (NSUInteger)gCurrentPage) {
        CCAPageIndicator *pager = (CCAPageIndicator *)[ov.view viewWithTag:kPageIndicatorTag];
        [pager setCurrentPage:page forOverlay:ov];
        PACShowToast(ov, [NSString stringWithFormat:@"%@ added to page %lu", PACNameForIdentifier(mid), (unsigned long)(page + 1)]);
    }
    PACCSyncClones(ov, YES);
}

@implementation PACEditProxy
+ (instancetype)shared {
    static PACEditProxy *s; static dispatch_once_t o;
    dispatch_once(&o, ^{ s = [self new]; });
    return s;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)touch {
    if (!PACEditAllowed()) return NO;
    UIViewController *ov = OverlayIn(UIApplication.sharedApplication.keyWindow.rootViewController);
    if (!ov) return NO;
    if (g.view != ov.view) return YES;
    if ([g isKindOfClass:UILongPressGestureRecognizer.class]) {
        UIView *v = touch.view;
        while (v) {
            for (UIViewController *m in ModuleControllers(ov)) {
                if (m.view == v) return NO;
            }
            if (v == ov.view) break;
            v = v.superview;
        }
    }
    return YES;
}

- (void)bgHold:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    if (!PACEditAllowed()) return;
    PACRefreshGridConstants();
    UIViewController *ov = OverlayIn(UIApplication.sharedApplication.keyWindow.rootViewController);
    if (!ov) return;

    if (gEditModeActive) {
    if ([ov.view viewWithTag:kPACShieldTag].superview) return;
    PACForceExitEdit(ov);
    return;
    }

    CGPoint lp = [g locationInView:ov.view];
    if (PACModuleAtPoint(lp, ov)) return;

    gEditModeActive = YES;
    gPACEditEpoch++;
    gEditModeEnteredAt = CACurrentMediaTime();
    gPACPendingResizeID = nil;
    gPACPendingResizeSize = (CCUILayoutSize){0, 0};
    gPACPendingResizeLastTouch = 0;
    if (gHapticsEnabled) Haptic();

    for (UIViewController *m in ModuleControllers(ov)) {
        PACEnsureBaseSize(m, ov);
        PACApplyRadiusToModule(m);
    }

    PACEditShield *shield = (PACEditShield *)[ov.view viewWithTag:kPACShieldTag];
    if (!shield) {
        shield = [[PACEditShield alloc] initWithFrame:ov.view.bounds];
        shield.tag = kPACShieldTag;
        shield.backgroundColor = UIColor.clearColor;
        shield.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        shield.userInteractionEnabled = YES;

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(shieldPan:)];
        pan.maximumNumberOfTouches = 1;
        pan.cancelsTouchesInView = YES;

        UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(shieldPan:)];
        hold.minimumPressDuration = 0.22;
        hold.allowableMovement = 12.0;
        hold.cancelsTouchesInView = YES;

        [pan requireGestureRecognizerToFail:hold];

        [shield addGestureRecognizer:pan];
        [shield addGestureRecognizer:hold];

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(shieldTap:)];
        tap.cancelsTouchesInView = NO;
        [shield addGestureRecognizer:tap];

        [ov.view addSubview:shield];
    } else if (shield.superview != ov.view) {
        [shield removeFromSuperview];
        [ov.view addSubview:shield];
    }
    shield.hidden = NO;
    shield.frame = ov.view.bounds;

    NSMutableArray<UIGestureRecognizer *> *disabled = [NSMutableArray array];
    UIView *walk = ov.view.superview;
    while (walk) {
        for (UIGestureRecognizer *gr in walk.gestureRecognizers) {
            if (!gr.enabled) continue;
            if ([gr isKindOfClass:UIPanGestureRecognizer.class] ||
                [gr isKindOfClass:UIPinchGestureRecognizer.class] ||
                [gr isKindOfClass:UISwipeGestureRecognizer.class]) {
                gr.enabled = NO;
                [disabled addObject:gr];
            }
        }
        walk = walk.superview;
    }
    objc_setAssociatedObject(ov, kPACDisabledGesturesKey, disabled, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    for (UIViewController *m in ModuleControllers(ov)) PACApplyChrome(m, ov);

    UIButton *reset = (UIButton *)[ov.view viewWithTag:kPACResetTag];
    if (!reset) {
        reset = PACMakeResetButton();
        [reset addTarget:self action:@selector(resetTap:) forControlEvents:UIControlEventTouchUpInside];
        [ov.view addSubview:reset];
    }
    CGFloat safeTop = ov.view.safeAreaInsets.top;
    if (safeTop < 1.0) safeTop = 20.0;
    reset.center = CGPointMake(CGRectGetMidX(ov.view.bounds), safeTop + 32.0);
    reset.alpha = 0.0;
    reset.transform = CGAffineTransformMakeTranslation(0, -8);
    UIViewPropertyAnimator *resetAnim = PACBezierAnimator(0.32, 0.32, 0.72, 0.0, 1.0);
    [resetAnim addAnimations:^{
        reset.alpha = 1.0;
        reset.transform = CGAffineTransformIdentity;
    }];
    [resetAnim startAnimationAfterDelay:0.05];
    [ov.view bringSubviewToFront:reset];

    UIButton *addButton = (UIButton *)[ov.view viewWithTag:kPACAddTag];
    if (!addButton) {
        addButton = PACMakeAddButton();
        [addButton addTarget:self action:@selector(addControlTap:) forControlEvents:UIControlEventTouchUpInside];
        [ov.view addSubview:addButton];
    }
    CGFloat addBottom = ov.view.safeAreaInsets.bottom;
    if (addBottom < 1.0) addBottom = 20.0;
    addButton.center = CGPointMake(CGRectGetMidX(ov.view.bounds), CGRectGetHeight(ov.view.bounds) - addBottom - 38.0);
    addButton.alpha = 0.0;
    addButton.transform = CGAffineTransformMakeScale(0.7, 0.7);
    [UIView animateWithDuration:0.65 delay:0.12 usingSpringWithDamping:0.58 initialSpringVelocity:0.7
                        options:UIViewAnimationOptionAllowUserInteraction animations:^{
        addButton.alpha = 1.0;
        addButton.transform = CGAffineTransformIdentity;
    } completion:nil];
    [ov.view bringSubviewToFront:addButton];

    UIButton *layers = (UIButton *)[ov.view viewWithTag:kPACLayersTag];
    if (!layers) {
        layers = PACMakeRoundButton(@"square.stack.3d.up.fill", 48.0, 20.0, kPACLayersTag);
        [layers addTarget:self action:@selector(layersTap:) forControlEvents:UIControlEventTouchUpInside];
        [ov.view addSubview:layers];
    }
    layers.center = CGPointMake(CGRectGetMinX(addButton.frame) - 14.0 - 24.0, addButton.center.y);
    layers.alpha = 0.0;
    layers.transform = CGAffineTransformMakeScale(0.7, 0.7);
    [UIView animateWithDuration:0.65 delay:0.18 usingSpringWithDamping:0.58 initialSpringVelocity:0.7
                        options:UIViewAnimationOptionAllowUserInteraction animations:^{
        layers.alpha = 1.0;
        layers.transform = CGAffineTransformIdentity;
    } completion:nil];

    // Page dots stay visible in edit mode so pages can be switched, with a "+" under them.
    UIView *ind = [ov.view viewWithTag:kPageIndicatorTag];
    ind.hidden = NO;
    ind.userInteractionEnabled = YES;
    [UIView animateWithDuration:0.2 animations:^{ ind.alpha = 1.0; }];

    UIButton *plus = (UIButton *)[ov.view viewWithTag:kPACPageAddTag];
    if (!plus) {
        plus = PACMakeRoundButton(@"plus", 34.0, 15.0, kPACPageAddTag);
        [plus addTarget:self action:@selector(addPageTap:) forControlEvents:UIControlEventTouchUpInside];
        [ov.view addSubview:plus];
    }
    PACPositionPageAddButton(ov);
    plus.alpha = 0.0;
    plus.transform = CGAffineTransformMakeScale(0.6, 0.6);
    [UIView animateWithDuration:0.6 delay:0.2 usingSpringWithDamping:0.55 initialSpringVelocity:0.8
                        options:UIViewAnimationOptionAllowUserInteraction animations:^{
        plus.alpha = 1.0;
        plus.transform = CGAffineTransformIdentity;
    } completion:nil];
    [ov.view bringSubviewToFront:ind];
    [ov.view bringSubviewToFront:plus];
    [ov.view bringSubviewToFront:layers];
    [ov.view bringSubviewToFront:addButton];
    PACStartPageWatch(ov);
}

- (void)shieldTap:(UITapGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateRecognized) return;
    if (!gEditModeActive) return;
    UIViewController *ov = OverlayIn(UIApplication.sharedApplication.keyWindow.rootViewController);
    if (!ov) return;
    CGPoint pt = [g locationInView:ov.view];
    if (PACModuleAtPoint(pt, ov)) return;
    [self exitEditOn:ov];
}

- (void)exitEditOn:(UIViewController *)ov {
    if (!gEditModeActive) return;
    gEditModeActive = NO;
    gPACEditEpoch++;
    NSUInteger epochAtExit = gPACEditEpoch;
    gPACPendingResizeID = nil;
    gPACPendingResizeSize = (CCUILayoutSize){0, 0};
    gPACPendingResizeLastTouch = 0;
    if (gHapticsEnabled) Haptic();

    NSMutableArray<UIView *> *chromeViews = [NSMutableArray array];
    for (UIViewController *m in ModuleControllers(ov)) {
        UIView *v = m.view;
        if (!v) continue;
        UIView *b = objc_getAssociatedObject(v, kPACBorderKey);
        UIButton *rm = objc_getAssociatedObject(v, kPACRemoveKey);
        UIButton *rz = objc_getAssociatedObject(v, kPACResizeKey);
        if (b) [chromeViews addObject:b];
        if (rm) [chromeViews addObject:rm];
        if (rz) [chromeViews addObject:rz];
        objc_setAssociatedObject(PACModuleButtonView(v), kPACIconPinKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(v, kPACBorderKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(v, kPACRemoveKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(v, kPACResizeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (chromeViews.count) {
        UIViewPropertyAnimator *exitAnim = PACBezierAnimator(0.24, 0.4, 0.0, 0.2, 1.0);
        [exitAnim addAnimations:^{
            for (UIView *v in chromeViews) {
                v.alpha = 0.0;
                v.transform = CGAffineTransformMakeScale(0.85, 0.85);
            }
        }];
        [exitAnim addCompletion:^(__unused UIViewAnimatingPosition pos) {
            if (epochAtExit != gPACEditEpoch) return;
            for (UIView *v in chromeViews) [v removeFromSuperview];
        }];
        [exitAnim startAnimation];
    }

    UIView *shield = [ov.view viewWithTag:kPACShieldTag];
    [shield removeFromSuperview];

    NSArray<UIGestureRecognizer *> *disabled = objc_getAssociatedObject(ov, kPACDisabledGesturesKey);
    for (UIGestureRecognizer *gr in disabled) gr.enabled = YES;
    objc_setAssociatedObject(ov, kPACDisabledGesturesKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UIView *reset = [ov.view viewWithTag:kPACResetTag];
    reset.tag = 0;
    UIViewPropertyAnimator *resetOut = PACBezierAnimator(0.2, 0.4, 0.0, 0.2, 1.0);
    [resetOut addAnimations:^{
        reset.alpha = 0.0;
        reset.transform = CGAffineTransformMakeTranslation(0, -8);
    }];
    [resetOut addCompletion:^(__unused UIViewAnimatingPosition pos) {
        if (epochAtExit != gPACEditEpoch) return;
        [reset removeFromSuperview];
    }];
    [resetOut startAnimation];

    [[ov.view viewWithTag:kPACHintTag] removeFromSuperview];
    [[ov.view viewWithTag:kPACPickerTag] removeFromSuperview];

    PACStopPageWatch();
    for (NSNumber *tagNum in @[@(kPACLayersTag), @(kPACPageAddTag)]) {
        UIView *extra = [ov.view viewWithTag:tagNum.integerValue];
        extra.tag = 0;
        [UIView animateWithDuration:0.2 animations:^{ extra.alpha = 0.0; extra.transform = CGAffineTransformMakeScale(0.8, 0.8); }
                         completion:^(BOOL f) { [extra removeFromSuperview]; }];
    }
    UIView *addOut = [ov.view viewWithTag:kPACAddTag];
    addOut.tag = 0;
    [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        addOut.alpha = 0.0;
        addOut.transform = CGAffineTransformMakeScale(0.8, 0.8);
    } completion:^(BOOL finished) {
        if (epochAtExit != gPACEditEpoch) return;
        [addOut removeFromSuperview];
    }];

    PACPruneEmptyPages(ov);
    UIView *ind = [ov.view viewWithTag:kPageIndicatorTag];
    ind.userInteractionEnabled = YES;
    [UIView animateWithDuration:0.2 animations:^{ ind.alpha = 1.0; }];
}

- (BOOL)computeArrangementForMid:(NSString *)mid
                             col:(NSUInteger)col
                             row:(NSUInteger)row
                               w:(NSUInteger)w
                               h:(NSUInteger)h
                         overlay:(UIViewController *)ov {
    PACEnsureStore();
    NSUInteger page = (NSUInteger)gCurrentPage;

    if (!PACDragSizeAllowedForModule(mid, w, h)) return NO;

    NSArray<NSNumber *> *oldO = PACGetOrigin(mid);
    if (oldO.count < 2) return NO;
    NSUInteger oldCol = oldO[0].unsignedIntegerValue;
    NSUInteger oldAbs = oldO[1].unsignedIntegerValue;
    NSUInteger oldRow = oldAbs % kPACStride;

    NSUInteger oldW = 1, oldH = 1;
    PACEffectiveSize(mid, &oldW, &oldH);
    if (oldCol == col && oldRow == row && (oldAbs / kPACStride) == page &&
        oldW == w && oldH == h) {
        return NO;
    }

    NSMutableDictionary<NSString *, NSValue *> *snapshot = [NSMutableDictionary dictionary];
    for (UIViewController *m in ModuleControllers(ov)) {
        NSString *oid = PACMid(m);
        if (!oid.length || [oid isEqualToString:mid]) continue;
        NSArray<NSNumber *> *o = PACGetOrigin(oid);
        if (o.count < 2) continue;
        NSUInteger oc = o[0].unsignedIntegerValue;
        NSUInteger oa = o[1].unsignedIntegerValue;
        if (oa / kPACStride != page) continue;
        NSUInteger orow = oa % kPACStride;
        NSUInteger ow = 1, oh = 1;
        PACEffectiveSize(oid, &ow, &oh);
        PACRect r = {oc, orow, ow, oh};
        snapshot[oid] = [NSValue value:&r withObjCType:@encode(PACRect)];
    }

    NSMutableDictionary<NSString *, NSValue *> *placed = [NSMutableDictionary dictionaryWithDictionary:snapshot];
    PACRect targetRect = {col, row, w, h};
    placed[mid] = [NSValue value:&targetRect withObjCType:@encode(PACRect)];

    NSMutableArray<NSString *> *colliders = [NSMutableArray array];
    for (NSString *oid in snapshot) {
        PACRect other = {};
        [snapshot[oid] getValue:&other];
        if (PACRectsOverlap(targetRect, other)) [colliders addObject:oid];
    }

    [colliders sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        PACRect ra = {}, rb = {};
        [snapshot[a] getValue:&ra];
        [snapshot[b] getValue:&rb];
        if (ra.r != rb.r) return ra.r < rb.r ? NSOrderedAscending : NSOrderedDescending;
        if (ra.c != rb.c) return ra.c < rb.c ? NSOrderedAscending : NSOrderedDescending;
        return [a compare:b];
    }];

    NSUInteger visibleCap = PACVisibleRowCap(ov);

    for (NSString *oid in colliders) {
        PACRect orig = {};
        [snapshot[oid] getValue:&orig];
        [placed removeObjectForKey:oid];
        NSUInteger maxTopRow = (visibleCap + 1 >= orig.h) ? (visibleCap - orig.h + 1) : 0;
        NSUInteger newC = 0, newR = 0;
        if (!PACFindFreeCellFor(placed, orig.c, orig.r, orig.w, orig.h, maxTopRow, &newC, &newR)) {
            return NO;
        }
        PACRect np = {newC, newR, orig.w, orig.h};
        placed[oid] = [NSValue value:&np withObjCType:@encode(PACRect)];
    }

    for (NSString *oid in placed) {
        PACRect r = {};
        [placed[oid] getValue:&r];
        PACSetOrigin(oid, @[@(r.c), @(page * kPACStride + r.r)]);
    }
    return YES;
}

- (void)shieldPan:(UIGestureRecognizer *)g {
    if (!PACEditAllowed()) return;
    UIViewController *ov = OverlayIn(UIApplication.sharedApplication.keyWindow.rootViewController);
    if (!ov) return;
    PACRefreshGridConstants();

    if (g.state == UIGestureRecognizerStateBegan) {
        CGPoint pt = [g locationInView:ov.view];
        UIViewController *src = PACModuleAtPoint(pt, ov);
        if (!src) return;
        NSString *mid = PACMid(src);
        if (!mid.length) return;

        CGRect vis = PACVisibleFrame(src, ov);
        CGPoint grab = CGPointMake(pt.x - CGRectGetMinX(vis), pt.y - CGRectGetMinY(vis));

        UIView *shadow = [[UIView alloc] initWithFrame:vis];
        shadow.tag = kPACProxyShadowTag;
        shadow.userInteractionEnabled = NO;
        shadow.backgroundColor = UIColor.clearColor;
        shadow.layer.shadowColor = UIColor.blackColor.CGColor;
        shadow.layer.shadowOpacity = 0.35;
        shadow.layer.shadowRadius = 16.0;
        shadow.layer.shadowOffset = CGSizeMake(0, 8);
        shadow.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:shadow.bounds
                                                            cornerRadius:src.view.layer.cornerRadius].CGPath;
        [ov.view addSubview:shadow];

        BOOL liquidassActive = PACCLIQIsActive();
        CGFloat proxyRadius = src.view.layer.cornerRadius;

        UIView *proxy;
        if (liquidassActive) {
            proxy = [[PACLiveGlassProxyView alloc] initWithFrame:shadow.bounds];
        } else {
            proxy = [[UIView alloc] initWithFrame:shadow.bounds];
        }
        proxy.tag = kPACProxyTag;
        proxy.userInteractionEnabled = NO;
        proxy.layer.cornerRadius = proxyRadius;
        proxy.layer.cornerCurve = kCACornerCurveContinuous;
        proxy.layer.masksToBounds = YES;

        if (liquidassActive) {
            proxy.backgroundColor = UIColor.clearColor;
            if (kClsCABackdropLayer && [proxy.layer isKindOfClass:kClsCABackdropLayer]) {
                [proxy.layer setValue:@NO  forKey:@"layerUsesCoreImageFilters"];
                [proxy.layer setValue:@YES forKey:@"windowServerAware"];
                [proxy.layer setValue:@"dylv.liquidglass.sharedGroup" forKey:@"groupName"];
                [proxy.layer setValue:@"dylv.liquidglass" forKey:@"groupNamespace"];
                [proxy.layer setValue:@(0.5) forKey:@"scale"];
                id glassFilter = PACCLIQBuildGlassFilter();
                if (glassFilter) proxy.layer.filters = @[glassFilter];
            }
        } else {
            proxy.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.6];
        }

        UIImage *snapImage = PACSnapshotContentOnly(src.view, liquidassActive);
        if (snapImage) {
            UIImageView *snap = [[UIImageView alloc] initWithImage:snapImage];
            snap.frame = proxy.bounds;
            snap.contentMode = UIViewContentModeScaleToFill;
            snap.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [proxy addSubview:snap];
        }
        [shadow addSubview:proxy];

        UIView *pres = objc_getAssociatedObject(src.view, kPACPresKey);
        [UIView animateWithDuration:0.12
                              delay:0.0
                            options:UIViewAnimationOptionCurveEaseOut |
                                    UIViewAnimationOptionBeginFromCurrentState |
                                    UIViewAnimationOptionAllowUserInteraction
                         animations:^{
            src.view.alpha = 0.0;
            pres.alpha = 0.0;
        } completion:nil];
        for (UIViewController *m in ModuleControllers(ov)) PACStripChrome(m);

        NSDictionary *origLayout = [gEditOrigins copy] ?: @{};
        objc_setAssociatedObject(g, kPACOrigLayoutKey, origLayout, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        objc_setAssociatedObject(g, kPACLastCellKey, @[@(NSIntegerMax), @(NSIntegerMax)], OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        objc_setAssociatedObject(g, kPACDragSrcKey,   src,    OBJC_ASSOCIATION_ASSIGN);
        objc_setAssociatedObject(g, kPACDragProxyKey, shadow, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(g, kPACDragGrabKey,  [NSValue valueWithCGPoint:grab], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (gHapticsEnabled) Haptic();

    } else if (g.state == UIGestureRecognizerStateChanged) {
        UIViewController *src = objc_getAssociatedObject(g, kPACDragSrcKey);
        UIView *shadow = objc_getAssociatedObject(g, kPACDragProxyKey);
        NSValue *gv = objc_getAssociatedObject(g, kPACDragGrabKey);
        if (!src || !shadow || !gv) return;
        CGPoint grab = gv.CGPointValue;
        CGPoint pt = [g locationInView:ov.view];
        NSString *mid = PACMid(src);
        NSUInteger w = 1, h = 1;
        PACEffectiveSize(mid, &w, &h);
        CGPoint base = PACGridBase(ov);

        CGRect f = shadow.frame;
        f.origin = CGPointMake(pt.x - grab.x, pt.y - grab.y);
        shadow.frame = f;

        NSInteger col = (NSInteger)lround((CGRectGetMinX(f) - base.x) / kPACStep);
        NSInteger row = (NSInteger)lround((CGRectGetMinY(f) - base.y) / kPACStep);
        col = MAX(0, MIN((NSInteger)kPACCols - (NSInteger)w, col));
        NSUInteger cap = PACVisibleRowCap(ov);
        NSInteger maxRow = MAX(0, (NSInteger)cap - (NSInteger)h + 1);
        row = MAX(0, MIN(maxRow, row));

        NSArray<NSNumber *> *last = objc_getAssociatedObject(g, kPACLastCellKey);
        if (!last ||
            [last[0] integerValue] != col ||
            [last[1] integerValue] != row) {
            objc_setAssociatedObject(g, kPACLastCellKey, @[@(col), @(row)], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            if ([self computeArrangementForMid:mid
                                          col:(NSUInteger)col
                                          row:(NSUInteger)row
                                            w:w h:h
                                      overlay:ov]) {
                [self relayout:ov];
            }
        }

    } else if (g.state == UIGestureRecognizerStateEnded ||
               g.state == UIGestureRecognizerStateCancelled ||
               g.state == UIGestureRecognizerStateFailed) {
        UIViewController *src = objc_getAssociatedObject(g, kPACDragSrcKey);
        UIView *shadow = objc_getAssociatedObject(g, kPACDragProxyKey);
        __block UIViewController *heldSrc = src;

        if (g.state != UIGestureRecognizerStateEnded) {
            NSDictionary *origLayout = objc_getAssociatedObject(g, kPACOrigLayoutKey);
            if (origLayout) {
                PACEnsureStore();
                [gEditOrigins removeAllObjects];
                [gEditOrigins addEntriesFromDictionary:origLayout];
                PACSaveStore();
                [self relayout:ov];
            }
        } else {
            PACSaveStore();
        }

        if (shadow) {
            [shadow removeFromSuperview];
        }
        NSUInteger epochAtDragEnd = gPACEditEpoch;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.06 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (epochAtDragEnd != gPACEditEpoch) return;
            if (!gEditModeActive) return;
            UIViewController *releaseSrc = heldSrc;
            if (releaseSrc) {
                UIView *pres = objc_getAssociatedObject(releaseSrc.view, kPACPresKey);
                [UIView animateWithDuration:0.18
                                      delay:0.0
                                    options:UIViewAnimationOptionCurveEaseOut |
                                            UIViewAnimationOptionBeginFromCurrentState |
                                            UIViewAnimationOptionAllowUserInteraction
                                 animations:^{
                    releaseSrc.view.alpha = 1.0;
                    pres.alpha = 1.0;
                } completion:nil];
            }
            for (UIViewController *m in ModuleControllers(ov)) {
                PACApplyRadiusToModule(m);
                PACApplyChrome(m, ov);
                PACRefreshPresentation(m, ov);
            }
            UIView *shield = [ov.view viewWithTag:kPACShieldTag];
            if (shield) [ov.view bringSubviewToFront:shield];
            for (UIViewController *m in ModuleControllers(ov)) {
                UIButton *rm = objc_getAssociatedObject(m.view, kPACRemoveKey);
                UIButton *rz = objc_getAssociatedObject(m.view, kPACResizeKey);
                if (rm) [ov.view bringSubviewToFront:rm];
                if (rz) [ov.view bringSubviewToFront:rz];
                UIView *pr = objc_getAssociatedObject(m.view, kPACPresKey);
                if (pr) [ov.view bringSubviewToFront:pr];
            }
            UIView *rp = [ov.view viewWithTag:kPACResetTag];
            if (rp) [ov.view bringSubviewToFront:rp];
            { UIView *pacA = [ov.view viewWithTag:kPACAddTag]; if (pacA) [ov.view bringSubviewToFront:pacA];
              UIView *pacP = [ov.view viewWithTag:kPACPickerTag]; if (pacP) [ov.view bringSubviewToFront:pacP]; }
        });

        objc_setAssociatedObject(g, kPACDragSrcKey,   nil, OBJC_ASSOCIATION_ASSIGN);
        objc_setAssociatedObject(g, kPACDragProxyKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(g, kPACDragGrabKey,  nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(g, kPACLastCellKey,  nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(g, kPACOrigLayoutKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

- (void)compactGridAfterRemoval:(UIViewController *)ov {
    PACEnsureStore();
    NSUInteger page = (NSUInteger)gCurrentPage;
    NSUInteger cap  = PACVisibleRowCap(ov);

    NSMutableDictionary<NSString *, NSValue *> *placed = [NSMutableDictionary dictionary];
    NSMutableArray<NSDictionary *> *entries = [NSMutableArray array];

    for (UIViewController *m in ModuleControllers(ov)) {
        NSString *mid = PACMid(m);
        if (!mid.length) continue;
        NSArray<NSNumber *> *o = PACGetOrigin(mid);
        if (o.count < 2) continue;
        NSUInteger abs = o[1].unsignedIntegerValue;
        if (abs / kPACStride != page) continue;

        NSUInteger w = 1, h = 1;
        PACEffectiveSize(mid, &w, &h);
        NSUInteger c = o[0].unsignedIntegerValue;
        NSUInteger r = abs % kPACStride;

        PACRect rect = {c, r, w, h};
        placed[mid] = [NSValue value:&rect withObjCType:@encode(PACRect)];
        [entries addObject:@{@"mid":mid, @"c":@(c), @"r":@(r), @"w":@(w), @"h":@(h)}];
    }

    [entries sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSInteger ar = [a[@"r"] integerValue], br = [b[@"r"] integerValue];
        if (ar != br) return ar < br ? NSOrderedAscending : NSOrderedDescending;
        NSInteger ac = [a[@"c"] integerValue], bc = [b[@"c"] integerValue];
        return ac < bc ? NSOrderedAscending : (ac > bc ? NSOrderedDescending : NSOrderedSame);
    }];

    for (NSDictionary *e in entries) {
        NSString *mid = e[@"mid"];
        NSUInteger w = [e[@"w"] unsignedIntegerValue];
        NSUInteger h = [e[@"h"] unsignedIntegerValue];
        NSInteger oc = [e[@"c"] integerValue];
        NSInteger orr = [e[@"r"] integerValue];

        [placed removeObjectForKey:mid];

        NSInteger maxC = (NSInteger)kPACCols - (NSInteger)w;
        NSInteger maxR = (NSInteger)MIN(cap, kPACRows - 1) - (NSInteger)h + 1;
        NSInteger bestC = oc, bestR = orr;
        NSInteger bestScore = NSIntegerMax;
        BOOL found = NO;

        for (NSInteger r = 0; r <= maxR; r++) {
            for (NSInteger c = 0; c <= maxC; c++) {
                if (r > orr) continue;
                if (r == orr && c >= oc) continue;

                PACRect t = {(NSUInteger)c, (NSUInteger)r, w, h};
                BOOL ok = YES;
                for (NSValue *v in placed.allValues) {
                    PACRect o = {};
                    [v getValue:&o];
                    if (PACRectsOverlap(t, o)) { ok = NO; break; }
                }
                if (!ok) continue;

                NSInteger score = r * (NSInteger)kPACCols + c;
                if (score < bestScore) {
                    bestScore = score;
                    bestC = c;
                    bestR = r;
                    found = YES;
                }
            }
        }

        PACRect rect = {(NSUInteger)bestC, (NSUInteger)bestR, w, h};
        placed[mid] = [NSValue value:&rect withObjCType:@encode(PACRect)];
        if (found) {
            PACSetOrigin(mid, @[@(bestC), @(page * kPACStride + bestR)]);
        }
    }
    PACSaveStore();
}

- (void)relayout:(UIViewController *)ov {
    UIViewController *col = ModuleCollection(ov);
    if (!col) return;

    SEL providerSel = NSSelectorFromString(@"_activePositionProvider");
    id provider = [col respondsToSelector:providerSel]
        ? ((id (*)(id, SEL))objc_msgSend)(col, providerSel) : nil;
    SEL regenSel = NSSelectorFromString(@"regenerateRectsWithOrderedIdentifiers:orderedSizes:");
    if (provider && [provider respondsToSelector:regenSel]) {
        NSMutableArray<NSString *> *ids = [NSMutableArray array];
        NSMutableArray<NSValue *> *sizes = [NSMutableArray array];
        for (UIViewController *m in ModuleControllers(ov)) {
            NSString *mid = PACMid(m);
            if (!mid.length) continue;
            NSUInteger w = 1, h = 1;
            PACEffectiveSize(mid, &w, &h);
            CCUILayoutSize sz = {w, h};
            [ids addObject:mid];
            [sizes addObject:[NSValue value:&sz withObjCType:@encode(CCUILayoutSize)]];
        }
        if (ids.count) {
            ((void (*)(id, SEL, id, id))objc_msgSend)(provider, regenSel, ids, sizes);
        }
    }

    for (UIViewController *m in ModuleControllers(ov)) [m.view setNeedsLayout];
    [col.view setNeedsLayout];

    void (^fixups)(void) = ^{
        for (UIViewController *m in ModuleControllers(ov)) {
            UIView *superview = m.view.superview;
            if (!superview || superview == col.view) continue;
            NSString *sn = NSStringFromClass(superview.class);
            if (![sn containsString:@"ContentModuleContainer"] &&
                ![sn containsString:@"ModuleWrapper"]) continue;
            CGRect target = superview.bounds;
            if (!CGRectEqualToRect(m.view.bounds, target)) {
                m.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
                m.view.frame = target;
            }
        }
        for (UIViewController *m in ModuleControllers(ov)) PACApplyRadiusToModule(m);
    };

    if (gExperimentalPagingEnabled) {
        UIViewPropertyAnimator *relayout = PACBezierAnimator(0.58, 0.32, 0.72, 0.0, 1.0);
        [relayout addAnimations:^{
            for (UIViewController *m in ModuleControllers(ov)) [m.view layoutIfNeeded];
            [col.view layoutIfNeeded];
        }];
        [relayout addCompletion:^(UIViewAnimatingPosition finalPosition) {
            if (finalPosition != UIViewAnimatingPositionEnd) return;
            fixups();
        }];
        [relayout startAnimation];
    } else {
        [UIView performWithoutAnimation:^{
            for (UIViewController *m in ModuleControllers(ov)) [m.view layoutIfNeeded];
            [col.view layoutIfNeeded];
        }];
        fixups();
    }
}

- (void)addControlTap:(UIButton *)b {
    if (!gEditModeActive) return;
    UIViewController *ov = OverlayIn(UIApplication.sharedApplication.keyWindow.rootViewController);
    if (!ov || [ov.view viewWithTag:kPACPickerTag]) return;
    if (gHapticsEnabled) Haptic();

    NSMutableArray<NSDictionary *> *items = [NSMutableArray array];
    for (NSString *mid in PACAvailableModuleIdentifiers()) {
        [items addObject:@{@"mid": mid, @"name": PACNameForIdentifier(mid)}];
    }
    [items sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *c) {
        return [a[@"name"] localizedCaseInsensitiveCompare:c[@"name"]];
    }];
    PACLog(@"picker: %lu available", (unsigned long)items.count);

    PACAddPicker *picker = [[PACAddPicker alloc] initWithFrame:ov.view.bounds items:items];
    picker.tag = kPACPickerTag;
    __weak PACAddPicker *weakPicker = picker;
    __weak UIViewController *weakOv = ov;
    picker.onClose = ^{
        PACAddPicker *p = weakPicker;
        [p dismissAnimated:^{ [p removeFromSuperview]; }];
    };
    picker.onPick = ^(NSString *mid) {
        PACAddPicker *p = weakPicker;
        [p dismissAnimated:^{
            [p removeFromSuperview];
            UIViewController *o = weakOv;
            if (o) [[PACEditProxy shared] addModule:mid overlay:o];
        }];
    };
    [ov.view addSubview:picker];
    [picker presentAnimated];
}

- (void)addPageTap:(UIButton *)b {
    if (!gEditModeActive) return;
    UIViewController *ov = OverlayIn(UIApplication.sharedApplication.keyWindow.rootViewController);
    if (!ov) return;
    PACEnsureUserPages();
    if (PACBasePageCount() + gPACUserPages >= kPACMaxPages) {
        PACShowToast(ov, @"You can't add more pages");
        return;
    }
    if (gHapticsEnabled) Haptic();
    gPACUserPages++;
    PACSaveUserPages();

    [PACC.shared installPageIndicatorOnOverlay:ov];
    PACPositionPageAddButton(ov);
    UIView *ind = [ov.view viewWithTag:kPageIndicatorTag];
    ind.hidden = NO;
    ind.alpha = 1.0;
    ind.userInteractionEnabled = YES;
    dispatch_async(dispatch_get_main_queue(), ^{ PACPositionPageAddButton(ov); });

    NSUInteger newPage = PACBasePageCount() + gPACUserPages - 1;
    CCAPageIndicator *indicator = (CCAPageIndicator *)ind;
    [indicator setCurrentPage:newPage forOverlay:ov];
    PACBringChromeToFront(ov);
    PACShowToast(ov, @"Page added. Tap Add a Control to fill it");
}

- (void)layersTap:(UIButton *)b {
    if (!gEditModeActive) return;
    UIViewController *ov = OverlayIn(UIApplication.sharedApplication.keyWindow.rootViewController);
    if (!ov) return;
    PACEnsureUserPages();
    NSUInteger total = PACBasePageCount() + gPACUserPages;
    if (total < 2) return;
    if (gHapticsEnabled) Haptic();
    NSUInteger next = (NSUInteger)((gCurrentPage + 1) % (NSInteger)total);
    CCAPageIndicator *indicator = (CCAPageIndicator *)[ov.view viewWithTag:kPageIndicatorTag];
    [indicator setCurrentPage:next forOverlay:ov];
}

- (void)addModule:(NSString *)mid overlay:(UIViewController *)ov {
    if (!mid.length || !ov || !gEditModeActive) return;
    id prov = PACSettingsProvider();
    SEL get = NSSelectorFromString(@"orderedUserEnabledModuleIdentifiers");
    SEL set = NSSelectorFromString(@"setAndSaveOrderedUserEnabledModuleIdentifiers:");
    if (PACCBigKind(mid)) {      // already on the grid: add a second copy instead of moving it
        BOOL onGrid = NO;
        for (UIViewController *m in ModuleControllers(ov)) if ([PACMid(m) isEqualToString:mid]) { onGrid = YES; break; }
        if (!onGrid && prov && [prov respondsToSelector:get]) {
            NSArray *cur = ((id (*)(id, SEL))objc_msgSend)(prov, get);
            onGrid = [cur isKindOfClass:NSArray.class] && [cur containsObject:mid];
        }
        BOOL onUserPage = (gCurrentPage > 0 && PACIsUserPage((NSUInteger)gCurrentPage));
        // adding on a new page always gives the big one (4x4 / 4x2); Connectivity needs the real module on the grid to press its buttons
        if (onGrid || (onUserPage && PACCBigKind(mid) == 2)) { PACAddCloneOf(mid, ov); return; }
    }
    if (!prov || ![prov respondsToSelector:get] || ![prov respondsToSelector:set]) {
        PACShowToast(ov, @"Couldn't add this control");
        PACLog(@"add %@: settings provider unavailable", mid);
        return;
    }

    PACEnsureStore();
    NSArray<NSNumber *> *known = PACKnownBaseSize(mid);
    NSUInteger w = known.count >= 2 ? known[0].unsignedIntegerValue : 1;
    NSUInteger h = known.count >= 2 ? known[1].unsignedIntegerValue : 1;
    gEditBaseSizes[mid] = known.count >= 2 ? known : @[@1, @1];
    [gEditSizes removeObjectForKey:mid];

    NSUInteger page = 0;
    BOOL placed = PACPlaceNewModule(mid, w, h, ov, &page);
    if (!placed) {
        // every page is full: open a new one, like iOS does
        PACEnsureUserPages();
        if (PACBasePageCount() + gPACUserPages < kPACMaxPages) {
            gPACUserPages++;
            PACSaveUserPages();
            [PACC.shared installPageIndicatorOnOverlay:ov];
            PACPositionPageAddButton(ov);
            placed = PACPlaceNewModule(mid, w, h, ov, &page);
        }
    }
    if (!placed) {
        PACShowToast(ov, @"No room left for another control");
        PACLog(@"add %@: no free cell", mid);
        return;
    }
    PACSaveStore();

    NSMutableArray *ids = [((id (*)(id, SEL))objc_msgSend)(prov, get) mutableCopy] ?: [NSMutableArray array];
    if (![ids containsObject:mid]) [ids addObject:mid];
    ((void (*)(id, SEL, id))objc_msgSend)(prov, set, ids);
    PACLog(@"add %@: saved (page %lu)", mid, (unsigned long)page);

    static dispatch_once_t once;
    dispatch_once(&once, ^{
        PACLogMethods(NSClassFromString(@"CCUIModuleInstanceManager"));
        PACLogMethods(NSClassFromString(@"CCUIModuleCollectionViewController"));
        PACLogMethods(NSClassFromString(@"CCSModuleRepository"));
    });
    PACReloadModuleRepository();

    __weak UIViewController *weakOv = ov;
    NSString *name = PACNameForIdentifier(mid);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.7 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIViewController *o = weakOv;
        if (!o || !gEditModeActive) return;
        UIViewController *added = nil;
        for (UIViewController *m in ModuleControllers(o)) {
            if ([PACMid(m) isEqualToString:mid]) { added = m; break; }
        }
        PACLog(@"add %@: module visible = %d", mid, added != nil);
        if (!added) {
            PACShowToast(o, [NSString stringWithFormat:@"%@ added. It will appear when you reopen Control Center", name]);
            return;
        }
        [self relayout:o];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (!gEditModeActive) return;
            for (UIViewController *m in ModuleControllers(o)) {
                PACApplyRadiusToModule(m);
                PACApplyChrome(m, o);
                PACRefreshPresentation(m, o);
            }
            PACBringChromeToFront(o);
            UIView *pop = added.view;
            pop.transform = CGAffineTransformMakeScale(0.4, 0.4);
            [UIView animateWithDuration:0.6 delay:0 usingSpringWithDamping:0.55 initialSpringVelocity:0.8 options:0 animations:^{
                pop.transform = CGAffineTransformIdentity;
            } completion:nil];
            if (page != (NSUInteger)gCurrentPage) {
                CCAPageIndicator *pager = (CCAPageIndicator *)[o.view viewWithTag:kPageIndicatorTag];
                [pager setCurrentPage:page forOverlay:o];
                PACShowToast(o, [NSString stringWithFormat:@"%@ added to page %lu", name, (unsigned long)(page + 1)]);
            }
        });
    });
}

- (void)resizePan:(UIPanGestureRecognizer *)g {
    if (!PACEditAllowed()) return;
    UIButton *btn = (UIButton *)g.view;
    NSString *mid = objc_getAssociatedObject(btn, kPACMidKey);
    if (!mid.length) return;
    PACRefreshGridConstants();
    gPACPendingResizeLastTouch = CACurrentMediaTime();
    UIViewController *ov = OverlayIn(UIApplication.sharedApplication.keyWindow.rootViewController);
    if (!ov) return;

    if (g.state == UIGestureRecognizerStateBegan) {
        PACEnsureStore();
        NSUInteger sw = 1, sh = 1;
        PACEffectiveSize(mid, &sw, &sh);
        objc_setAssociatedObject(g, kPACStartSzKey, @[@(sw), @(sh)], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        gPACPendingResizeID = [mid copy];
        gPACPendingResizeSize = (CCUILayoutSize){sw, sh};
        if (gHapticsEnabled) Haptic();

    } else if (g.state == UIGestureRecognizerStateChanged) {
        NSArray<NSNumber *> *s = objc_getAssociatedObject(g, kPACStartSzKey);
        if (s.count < 2) return;
        NSUInteger sw = s[0].unsignedIntegerValue, sh = s[1].unsignedIntegerValue;
        CGPoint t = [g translationInView:ov.view];
        CCUILayoutSize next = PACResizeCandidate(mid, sw, sh, t);
        if (!PACSizeAllowedFor(mid, next.width, next.height)) {
            next = gPACPendingResizeSize;
        }
        if (next.width != gPACPendingResizeSize.width ||
            next.height != gPACPendingResizeSize.height) {
            gPACPendingResizeSize = next;

            NSArray<NSNumber *> *cur = PACGetOrigin(mid);
            if (cur.count >= 2) {
                NSUInteger cCol = cur[0].unsignedIntegerValue;
                NSUInteger cAbs = cur[1].unsignedIntegerValue;
                NSUInteger cRow = cAbs % kPACStride;
                [self computeArrangementForMid:mid
                                           col:cCol
                                           row:cRow
                                             w:next.width
                                             h:next.height
                                       overlay:ov];
            }

            [self relayout:ov];
            PACSettleEditLayout(ov);
        }

    } else if (g.state == UIGestureRecognizerStateEnded ||
               g.state == UIGestureRecognizerStateCancelled ||
               g.state == UIGestureRecognizerStateFailed) {
        CCUILayoutSize p = gPACPendingResizeSize;
        gPACPendingResizeID = nil;
        gPACPendingResizeSize = (CCUILayoutSize){0, 0};
        if (g.state == UIGestureRecognizerStateEnded && p.width && p.height &&
            PACSizeAllowedFor(mid, p.width, p.height)) {
            [self commitResize:mid w:p.width h:p.height overlay:ov];
        }
        objc_setAssociatedObject(g, kPACStartSzKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self relayout:ov];
        PACSettleEditLayout(ov);
        NSUInteger epochAtResizeEnd = gPACEditEpoch;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.30 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (epochAtResizeEnd != gPACEditEpoch) return;
            if (!gEditModeActive) return;
            for (UIViewController *m in ModuleControllers(ov)) {
                PACApplyRadiusToModule(m);
                PACApplyChrome(m, ov);
                PACRefreshPresentation(m, ov);
            }
            UIView *shield = [ov.view viewWithTag:kPACShieldTag];
            if (shield) [ov.view bringSubviewToFront:shield];
            for (UIViewController *m in ModuleControllers(ov)) {
                UIButton *rm = objc_getAssociatedObject(m.view, kPACRemoveKey);
                UIButton *rz = objc_getAssociatedObject(m.view, kPACResizeKey);
                if (rm) [ov.view bringSubviewToFront:rm];
                if (rz) [ov.view bringSubviewToFront:rz];
                UIView *pr = objc_getAssociatedObject(m.view, kPACPresKey);
                if (pr) [ov.view bringSubviewToFront:pr];
            }
            UIView *rp = [ov.view viewWithTag:kPACResetTag];
            if (rp) [ov.view bringSubviewToFront:rp];
            { UIView *pacA = [ov.view viewWithTag:kPACAddTag]; if (pacA) [ov.view bringSubviewToFront:pacA];
              UIView *pacP = [ov.view viewWithTag:kPACPickerTag]; if (pacP) [ov.view bringSubviewToFront:pacP]; }
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.62 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (epochAtResizeEnd != gPACEditEpoch) return;
            if (!gEditModeActive) return;
            for (UIViewController *m in ModuleControllers(ov)) {
                PACApplyRadiusToModule(m);
                PACRefreshPresentation(m, ov);
                PACResyncGlass(m);
            }
        });
    }
}

- (void)commitResize:(NSString *)mid w:(NSUInteger)w h:(NSUInteger)h overlay:(UIViewController *)ov {
    PACEnsureStore();
    if (!PACSizeAllowedFor(mid, w, h)) return;

    NSArray<NSNumber *> *o = PACGetOrigin(mid);
    if (o.count < 2) return;
    NSUInteger col = o[0].unsignedIntegerValue;
    NSUInteger absRow = o[1].unsignedIntegerValue;
    NSUInteger page = absRow / kPACStride;
    NSUInteger row = absRow % kPACStride;
    if (col + w > kPACCols) w = kPACCols - col;
    if (row + h > kPACRows) h = kPACRows - row;
    if (!PACSizeAllowedFor(mid, w, h)) return;

    NSUInteger capR = PACVisibleRowCap(ov);

    NSMutableDictionary<NSString *, NSValue *> *snapshot = [NSMutableDictionary dictionary];
    for (UIViewController *m in ModuleControllers(ov)) {
        NSString *oid = PACMid(m);
        if (!oid.length || [oid isEqualToString:mid]) continue;
        NSArray<NSNumber *> *oo = PACGetOrigin(oid);
        if (oo.count < 2) continue;
        NSUInteger oc = oo[0].unsignedIntegerValue;
        NSUInteger oa = oo[1].unsignedIntegerValue;
        if (oa / kPACStride != page) continue;
        NSUInteger orow = oa % kPACStride;
        NSUInteger ow = 1, oh = 1;
        PACEffectiveSize(oid, &ow, &oh);
        PACRect r = {oc, orow, ow, oh};
        snapshot[oid] = [NSValue value:&r withObjCType:@encode(PACRect)];
    }

    BOOL resolved = NO;

    if (row + h <= capR + 1) {
        PACRect targetRect = {col, row, w, h};

        NSMutableDictionary<NSString *, NSValue *> *placed =
            [NSMutableDictionary dictionaryWithDictionary:snapshot];

        NSMutableArray<NSString *> *colliders = [NSMutableArray array];
        for (NSString *oid in snapshot) {
            PACRect other = {};
            [snapshot[oid] getValue:&other];
            if (PACRectsOverlap(targetRect, other)) [colliders addObject:oid];
        }
        for (NSString *oid in colliders) [placed removeObjectForKey:oid];
        placed[mid] = [NSValue value:&targetRect withObjCType:@encode(PACRect)];

        [colliders sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
            PACRect ra = {}, rb = {};
            [snapshot[a] getValue:&ra];
            [snapshot[b] getValue:&rb];
            if (ra.r != rb.r) return ra.r < rb.r ? NSOrderedAscending : NSOrderedDescending;
            if (ra.c != rb.c) return ra.c < rb.c ? NSOrderedAscending : NSOrderedDescending;
            return [a compare:b];
        }];

        BOOL allFit = YES;
        for (NSString *oid in colliders) {
            PACRect orig = {};
            [snapshot[oid] getValue:&orig];
            NSUInteger cMaxRow = (capR + 1 >= orig.h) ? (capR - orig.h + 1) : 0;
            NSUInteger nc = 0, nr = 0;
            if (!PACFindFreeCellFor(placed, orig.c, orig.r, orig.w, orig.h, cMaxRow, &nc, &nr)) {
                allFit = NO;
                break;
            }
            PACRect np = {nc, nr, orig.w, orig.h};
            placed[oid] = [NSValue value:&np withObjCType:@encode(PACRect)];
        }

        if (allFit) {
            resolved = YES;
            gEditSizes[mid] = @[@(w), @(h)];
            for (NSString *oid in placed) {
                PACRect r = {};
                [placed[oid] getValue:&r];
                PACSetOrigin(oid, @[@(r.c), @(page * kPACStride + r.r)]);
            }
        }
    }

    if (!resolved) {
        NSMutableDictionary<NSString *, NSValue *> *placed =
            [NSMutableDictionary dictionaryWithDictionary:snapshot];
        NSUInteger cMaxRow = (capR + 1 >= h) ? (capR - h + 1) : 0;
        NSUInteger newCol = 0, newRow = 0;
        if (!PACFindFreeCellFor(placed, col, row, w, h, cMaxRow, &newCol, &newRow)) return;
        gEditSizes[mid]   = @[@(w), @(h)];
        PACSetOrigin(mid, @[@(newCol), @(page * kPACStride + newRow)]);
    }

    PACInvalidateOtherOrientationOriginForModule(mid);
    PACSaveStore();

    NSMutableSet<NSString *> *resized = objc_getAssociatedObject(UIApplication.sharedApplication, kPACResizedSetKey);
    if (!resized) {
        resized = [NSMutableSet set];
        objc_setAssociatedObject(UIApplication.sharedApplication, kPACResizedSetKey, resized, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [resized addObject:mid];

    for (UIViewController *m in ModuleControllers(ov)) {
        if (![PACMid(m) isEqualToString:mid]) continue;
        id contentModule = nil;
        @try { contentModule = [m valueForKey:@"module"]; } @catch (__unused NSException *e) {}
        id ctx = nil;
        @try { ctx = [contentModule valueForKey:@"contentModuleContext"]; } @catch (__unused NSException *e) {}
        if ([ctx respondsToSelector:NSSelectorFromString(@"requestLayoutSizeUpdate")]) {
            ((void (*)(id, SEL))objc_msgSend)(ctx, NSSelectorFromString(@"requestLayoutSizeUpdate"));
        }
        break;
    }
}

- (void)removeTap:(UIButton *)b {
    if (!gEditModeActive) return;
    NSString *mid = objc_getAssociatedObject(b, kPACMidKey);
    if (!mid.length) return;
    if (gHapticsEnabled) Haptic();

    UIViewController *ov = OverlayIn(UIApplication.sharedApplication.keyWindow.rootViewController);
    if (!ov) return;

    if ([mid hasPrefix:@"clone:"]) {
        NSString *cid = [mid substringFromIndex:6];
        PACEnsureClones();
        for (NSMutableDictionary *cd in [gPACClones copy]) if ([cd[@"id"] isEqualToString:cid]) [gPACClones removeObject:cd];
        PACSaveClones();
        for (UIView *sv in ModuleCollection(ov).view.subviews) {
            if (sv.tag == kPACCloneTag && [objc_getAssociatedObject(sv, kPACCloneIDKey) isEqualToString:cid]) {
                PACRemoveCloneChrome(sv);
                [UIView animateWithDuration:0.24 animations:^{ sv.transform = CGAffineTransformMakeScale(0.35, 0.35); sv.alpha = 0.0; }
                                 completion:^(BOOL f) { [sv removeFromSuperview]; }];
            }
        }
        return;
    }

    UIViewController *victim = nil;
    for (UIViewController *m in ModuleControllers(ov)) {
        if ([PACMid(m) isEqualToString:mid]) { victim = m; break; }
    }
    UIView   *victimBorder = victim ? objc_getAssociatedObject(victim.view, kPACBorderKey) : nil;
    UIButton *victimRM     = victim ? objc_getAssociatedObject(victim.view, kPACRemoveKey) : nil;
    UIButton *victimRZ     = victim ? objc_getAssociatedObject(victim.view, kPACResizeKey) : nil;

    if (victim) {
        [UIView animateWithDuration:0.24
                              delay:0.0
                            options:UIViewAnimationOptionCurveEaseIn |
                                    UIViewAnimationOptionBeginFromCurrentState |
                                    UIViewAnimationOptionAllowUserInteraction
                         animations:^{
            CGAffineTransform s = CGAffineTransformMakeScale(0.35, 0.35);
            victim.view.transform   = s;  victim.view.alpha   = 0.0;
            victimBorder.transform  = s;  victimBorder.alpha  = 0.0;
            victimRM.transform      = s;  victimRM.alpha      = 0.0;
            victimRZ.transform      = s;  victimRZ.alpha      = 0.0;
        } completion:nil];
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.24 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        id prov = PACSettingsProvider();
        SEL get = NSSelectorFromString(@"orderedUserEnabledModuleIdentifiers");
        SEL set = NSSelectorFromString(@"setAndSaveOrderedUserEnabledModuleIdentifiers:");

        NSUInteger visibleCount = 0;
        for (UIViewController *m in ModuleControllers(ov)) {
            if (PACMid(m).length) visibleCount++;
        }
        NSArray *enabledNow = [prov respondsToSelector:get] ? ((id (*)(id, SEL))objc_msgSend)(prov, get) : nil;
        NSUInteger enabledCount = [enabledNow isKindOfClass:NSArray.class] ? enabledNow.count : 0;
        BOOL slide = PACIsNonNotchedDevice() && (visibleCount == 12 || enabledCount == 12);
        NSDictionary<NSString *, NSValue *> *oldFrames = slide ? PACCaptureModuleFrames(ov, mid) : nil;

        if ([prov respondsToSelector:get] && [prov respondsToSelector:set]) {
            NSArray *ids = ((id (*)(id, SEL))objc_msgSend)(prov, get);
            NSMutableArray *mut = [ids mutableCopy];
            [mut removeObject:mid];
            ((void (*)(id, SEL, id))objc_msgSend)(prov, set, mut);
        }

        PACEnsureStore();
        PACSetOrigin(mid, nil);
        [gEditSizes removeObjectForKey:mid];
        PACInvalidateOtherOrientationOriginForModule(mid);
        PACSaveStore();

        if (victim) PACStripChrome(victim);
        [victimBorder removeFromSuperview];
        [victimRM removeFromSuperview];
        [victimRZ removeFromSuperview];

        [self compactGridAfterRemoval:ov];
        [self relayout:ov];

        NSTimeInterval settleDelay = 0.45;
        if (slide) {
            PACSlideModules(ov, oldFrames);
            PACAnimateChromeRefreshExcluding(ov, mid);
            PACSettleEditLayoutEx(ov, NO);
            CFTimeInterval startedAt = CACurrentMediaTime();
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!gEditModeActive) return;
                if (CACurrentMediaTime() - startedAt > 0.1) return;
                if (PACSlideModules(ov, oldFrames)) PACAnimateChromeRefreshExcluding(ov, mid);
            });
            settleDelay = MAX(settleDelay, PACResizeSpec().duration + 0.08);
        } else {
            PACSettleEditLayout(ov);
        }

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(settleDelay * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (!gEditModeActive) return;
            for (UIViewController *m in ModuleControllers(ov)) {
                PACApplyRadiusToModule(m);
                PACApplyChrome(m, ov);
                PACRefreshPresentation(m, ov);
            }
            UIView *shield = [ov.view viewWithTag:kPACShieldTag];
            if (shield) [ov.view bringSubviewToFront:shield];
            for (UIViewController *m in ModuleControllers(ov)) {
                UIButton *rm = objc_getAssociatedObject(m.view, kPACRemoveKey);
                UIButton *rz = objc_getAssociatedObject(m.view, kPACResizeKey);
                if (rm) [ov.view bringSubviewToFront:rm];
                if (rz) [ov.view bringSubviewToFront:rz];
                UIView *pr = objc_getAssociatedObject(m.view, kPACPresKey);
                if (pr) [ov.view bringSubviewToFront:pr];
            }
            UIView *rp = [ov.view viewWithTag:kPACResetTag];
            if (rp) [ov.view bringSubviewToFront:rp];
            { UIView *pacA = [ov.view viewWithTag:kPACAddTag]; if (pacA) [ov.view bringSubviewToFront:pacA];
              UIView *pacP = [ov.view viewWithTag:kPACPickerTag]; if (pacP) [ov.view bringSubviewToFront:pacP]; }
        });
    });
}

- (void)resetTap:(UIButton *)b {
    if (!gEditModeActive) return;
    PACRefreshGridConstants();
    gPACEditEpoch++;
    NSUInteger epochAtReset = gPACEditEpoch;
    gEditModeEnteredAt = CACurrentMediaTime();
    gPACPendingResizeID = nil;
    gPACPendingResizeSize = (CCUILayoutSize){0, 0};
    gPACPendingResizeLastTouch = 0;
    if (gHapticsEnabled) {
        UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [gen prepare];
        [gen impactOccurred];
    }

    UIViewController *ov = OverlayIn(UIApplication.sharedApplication.keyWindow.rootViewController);
    if (!ov) return;

    for (UIViewController *m in ModuleControllers(ov)) {
        PACEnsureBaseSize(m, ov);
    }

    NSArray<NSString *> *ordered = PACProviderOrderedIdentifiers();

    PACEnsureStore();
    NSString *prefix = PACIsLandscape() ? @"L|" : @"P|";
    for (NSString *key in [gEditOrigins.allKeys copy]) {
        if ([key hasPrefix:prefix]) [gEditOrigins removeObjectForKey:key];
    }
    [gEditSizes removeAllObjects];
    PACEnsureClones();
    [gPACClones removeAllObjects];
    PACSaveClones();
    PACCSyncClones(ov, NO);

    NSMutableDictionary<NSString *, NSValue *> *placed = [NSMutableDictionary dictionary];

    NSMutableArray<NSString *> *ids = [NSMutableArray array];
    if (ordered.count) [ids addObjectsFromArray:ordered];
    for (UIViewController *m in ModuleControllers(ov)) {
        NSString *mid = PACMid(m);
        if (!mid.length) continue;
        if (![ids containsObject:mid]) [ids addObject:mid];
    }

    NSUInteger perPage = kPACRows;
    for (NSString *mid in ids) {
        NSArray<NSNumber *> *base = gEditBaseSizes[mid];
        if (base.count < 2) base = PACKnownBaseSize(mid);
        if (base.count < 2) continue;
        NSUInteger w = base[0].unsignedIntegerValue;
        NSUInteger h = base[1].unsignedIntegerValue;
        if (w == 0 || h == 0 || w > kPACCols || h > kPACRows) continue;

        BOOL found = NO;
        for (NSUInteger page = 0; page < 4 && !found; page++) {
            NSUInteger maxR = kPACRows - h;
            NSUInteger maxC = kPACCols - w;
            for (NSUInteger r = 0; r <= maxR && !found; r++) {
                for (NSUInteger c = 0; c <= maxC; c++) {
                    PACRect t = {c, r, w, h};
                    BOOL ok = YES;
                    for (NSValue *v in placed.allValues) {
                        PACRect o = {};
                        [v getValue:&o];
                        if (PACRectsOverlap(t, o)) { ok = NO; break; }
                    }
                    if (!ok) continue;
                    PACRect copy = t;
                    placed[mid] = [NSValue value:&copy withObjCType:@encode(PACRect)];
                    PACSetOrigin(mid, @[@(c), @(page * perPage + r)]);
                    found = YES;
                    break;
                }
            }
        }
    }
    PACSaveStore();

    for (UIViewController *m in ModuleControllers(ov)) PACStripChrome(m);
    UIView *hint = [ov.view viewWithTag:kPACHintTag];
    hint.hidden = YES;

    [UIView animateWithDuration:0.10 animations:^{
        b.transform = CGAffineTransformMakeScale(0.94, 0.94);
    } completion:^(__unused BOOL f) {
        [UIView animateWithDuration:0.18 delay:0.0
                            options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
                         animations:^{ b.transform = CGAffineTransformIdentity; }
                         completion:nil];
    }];

    [self relayout:ov];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (epochAtReset != gPACEditEpoch) return;
        if (!gEditModeActive) return;
        for (UIViewController *m in ModuleControllers(ov)) {
            PACApplyRadiusToModule(m);
            PACApplyChrome(m, ov);
            PACRefreshPresentation(m, ov);
        }
        UIView *shield = [ov.view viewWithTag:kPACShieldTag];
        if (shield) [ov.view bringSubviewToFront:shield];
        for (UIViewController *m in ModuleControllers(ov)) {
            UIButton *rm = objc_getAssociatedObject(m.view, kPACRemoveKey);
            UIButton *rz = objc_getAssociatedObject(m.view, kPACResizeKey);
            if (rm) [ov.view bringSubviewToFront:rm];
            if (rz) [ov.view bringSubviewToFront:rz];
            UIView *pr = objc_getAssociatedObject(m.view, kPACPresKey);
            if (pr) [ov.view bringSubviewToFront:pr];
        }
        [ov.view bringSubviewToFront:b];
    });
}

@end

static void PACRefreshPresentationImpl(UIViewController *m, UIViewController *ov) {
    if (!m || !m.view) return;
    NSString *mid = PACMid(m);
    if (!mid.length) return;

    PACEnsureStore();
    PACEnsureBaseSize(m, ov);

    BOOL expandedNow = PACModuleIsExpanded(m);
    if (PACCBigKind(mid)) {
        NSUInteger bw = 1, bh = 1;
        PACEffectiveSize(mid, &bw, &bh);
        PACCBigStyle(m, mid, bw, bh, expandedNow);
    }
    if (expandedNow) return;

    NSUInteger curW = 1, curH = 1;
    PACPresentationSize(mid, &curW, &curH);

    UIView *buttonView = PACModuleButtonView(m.view);
    if (!buttonView) return;

    BOOL animate = PACAnimationsAllowed();
    NSUInteger radiusW = 1, radiusH = 1;
    PACEffectiveSize(mid, &radiusW, &radiusH);
    CGFloat radius = PACRadiusForSize(radiusW, radiusH);
    PACSetRadius(buttonView.layer, radius, animate && objc_getAssociatedObject(m.view, kPACLastRadiusKey) != nil);

    BOOL isResizedFromOneByOne = PACWasResizedFromOneByOne(mid);

    UIView *pres = objc_getAssociatedObject(m.view, kPACPresKey);
    if (!isResizedFromOneByOne) {
        if (pres) {
            objc_setAssociatedObject(m.view, kPACPresKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            if (animate && pres.superview) {
                [UIView animateWithDuration:0.15
                                      delay:0.0
                                    options:UIViewAnimationOptionBeginFromCurrentState |
                                            UIViewAnimationOptionAllowUserInteraction
                                 animations:^{ pres.alpha = 0.0; }
                                 completion:^(__unused BOOL finished) { [pres removeFromSuperview]; }];
            } else {
                [pres removeFromSuperview];
            }
        }
        objc_setAssociatedObject(m.view, kPACLastPresKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        PACRestoreModuleIcon(m);
        return;
    }

    PACLayoutModuleIcon(m);

    NSString *newText = PACPrettyNameForModule(m);
    CGSize bvSize = buttonView.bounds.size;
    NSUInteger sig = 1469598103934665603ULL;
    sig = (sig ^ (NSUInteger)llround(bvSize.width))  * 1099511628211ULL;
    sig = (sig ^ (NSUInteger)llround(bvSize.height)) * 1099511628211ULL;
    sig = (sig ^ curW) * 1099511628211ULL;
    sig = (sig ^ curH) * 1099511628211ULL;
    sig = (sig ^ (NSUInteger)newText.hash) * 1099511628211ULL;

    NSNumber *lastSig = objc_getAssociatedObject(m.view, kPACLastPresKey);
    if (lastSig && lastSig.unsignedIntegerValue == sig &&
        pres && pres.superview == buttonView) {
        return;
    }
    objc_setAssociatedObject(m.view, kPACLastPresKey, @(sig), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UILabel *titleLabel = nil;
    BOOL created = (!pres || pres.superview != buttonView);
    if (created) {
        [pres removeFromSuperview];
        pres = [[UIView alloc] initWithFrame:buttonView.bounds];
        pres.userInteractionEnabled = NO;
        pres.backgroundColor = UIColor.clearColor;
        pres.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        pres.clipsToBounds = YES;
        pres.alpha = animate ? 0.0 : 1.0;

        titleLabel = [[UILabel alloc] init];
        titleLabel.tag = 9001;
        titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
        titleLabel.textColor = UIColor.whiteColor;
        titleLabel.numberOfLines = 2;
        titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        titleLabel.textAlignment = NSTextAlignmentLeft;
        [pres addSubview:titleLabel];

        objc_setAssociatedObject(m.view, kPACPresKey, pres, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [buttonView addSubview:pres];
    } else {
        titleLabel = (UILabel *)[pres viewWithTag:9001];
    }

    if (created) {
        [UIView performWithoutAnimation:^{ pres.frame = buttonView.bounds; }];
    } else {
        pres.frame = buttonView.bounds;
    }
    pres.hidden = NO;

    titleLabel.text = newText;

    CGFloat W = CGRectGetWidth(pres.bounds);
    CGFloat H = CGRectGetHeight(pres.bounds);
    CGFloat lineHeight = 14.3333;
    CGFloat textW;
    CGFloat textX;
    CGFloat iconCenterY = H * 0.5;
    if (curW > 1 && curH == 1) {
        textX = kPACCell - 10.0;
        iconCenterY = H * 0.5;
        textW = MAX(0.0, W - textX - 12.0);
    } else {
        textX = curW > 1 ? 21.0 : 10.0;
        textW = MAX(0.0, W - textX - (curW > 1 ? 24.0 : 10.0));
    }
    CGSize measured = [titleLabel.text boundingRectWithSize:CGSizeMake(textW, lineHeight * 2.0)
                                                    options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                                 attributes:@{NSFontAttributeName: titleLabel.font}
                                                    context:nil].size;
    CGFloat titleH = measured.height > lineHeight + 1.0 ? lineHeight * 2.0 : lineHeight;

    CGFloat top;
    if (curW > 1 && curH == 1) {
        top = iconCenterY - titleH * 0.5;
        if (top < 4.0) top = 4.0;
        if (top > H - titleH - 4.0) top = H - titleH - 4.0;
    } else {
        top = MAX(kPACCell + 7.0, H - 17.3333 - titleH);
    }
    CGRect labelFrame = CGRectMake(textX, top, textW, titleH);
    if (created) {
        [UIView performWithoutAnimation:^{ titleLabel.frame = labelFrame; }];
    } else {
        titleLabel.frame = labelFrame;
    }
    [buttonView bringSubviewToFront:pres];
    [pres bringSubviewToFront:titleLabel];

    if (created && animate) {
        [UIView animateWithDuration:0.22
                              delay:0.08
                            options:UIViewAnimationOptionBeginFromCurrentState |
                                    UIViewAnimationOptionAllowUserInteraction
                         animations:^{ pres.alpha = 1.0; }
                         completion:nil];
    }
}

static void PACRefreshPresentation(UIViewController *m, UIViewController *ov) {
    if (!m || !m.view) return;
    if (PACIsLandscape()) return;
    objc_setAssociatedObject(m.view, kPACLandscapeCleanKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    PACRunMaybeWithoutAnimation(^{ PACRefreshPresentationImpl(m, ov); });
}

static void PACApplyChrome(UIViewController *m, UIViewController *ov) {
    if (!gEditModeActive) return;
    if (PACIsLandscape()) return;
    UIView *view = m.view;
    if (!view) return;
    NSString *mid = PACMid(m);
    if (!mid.length) return;
    CGRect vis = PACVisibleFrame(m, ov);
    if (CGRectIsEmpty(vis)) return;

    PACApplyRadiusToModule(m);

    CGFloat radius = view.layer.cornerRadius;
    if (radius < 1.0) radius = MIN(CGRectGetWidth(vis), CGRectGetHeight(vis)) * 0.5;

    UIView *border = objc_getAssociatedObject(view, kPACBorderKey);
    BOOL borderIsNew = (border == nil);
    if (borderIsNew) {
        border = PACMakeBorder();
        objc_setAssociatedObject(view, kPACBorderKey, border, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [ov.view addSubview:border];

    border.frame = CGRectInset(vis, -kPACBorderInset, -kPACBorderInset);
    CGFloat anchorRadius = radius;
    if (anchorRadius < 1.0) {
        anchorRadius = MIN(CGRectGetWidth(vis), CGRectGetHeight(vis)) * 0.5;
    }
    border.layer.cornerRadius = anchorRadius + kPACBorderInset;
    border.hidden = NO;
    if (borderIsNew) PACAnimateChromeEntry(border);

    UIButton *rm = objc_getAssociatedObject(view, kPACRemoveKey);
    BOOL rmIsNew = (rm == nil);
    if (rmIsNew) {
        rm = PACMakeRemoveButton(mid);
        [rm addTarget:[PACEditProxy shared] action:@selector(removeTap:) forControlEvents:UIControlEventTouchUpInside];
        objc_setAssociatedObject(view, kPACRemoveKey, rm, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [ov.view addSubview:rm];
    }
    CGFloat rmSize = 30.0;
    rm.frame = CGRectMake(vis.origin.x - 8.0, vis.origin.y - 8.0, rmSize, rmSize);
    rm.hidden = NO;
    if (rmIsNew) PACAnimateChromeEntryDelayed(rm, 0.04);

    BOOL supportsResize = PACModuleSupportsResizing(mid);
    objc_setAssociatedObject(PACModuleButtonView(view), kPACIconPinKey,
                             supportsResize ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIButton *rz = objc_getAssociatedObject(view, kPACResizeKey);
    if (supportsResize) {
        BOOL rzIsNew = (rz == nil);
        if (rzIsNew) {
            rz = PACMakeResizeButton(mid);
            objc_setAssociatedObject(view, kPACResizeKey, rz, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            UIPanGestureRecognizer *rp = [[UIPanGestureRecognizer alloc] initWithTarget:[PACEditProxy shared] action:@selector(resizePan:)];
            rp.maximumNumberOfTouches = 1;
            rp.cancelsTouchesInView = YES;
            [rz addGestureRecognizer:rp];
            [ov.view addSubview:rz];
        }
        CGFloat rzSize = 42.0;
        CGFloat rzOverhang = 2.0;
        rz.frame = CGRectMake(CGRectGetMaxX(vis) - rzSize + rzOverhang,
                              CGRectGetMaxY(vis) - rzSize + rzOverhang,
                              rzSize, rzSize);
        rz.hidden = NO;
        if (rzIsNew) PACAnimateChromeEntryDelayed(rz, 0.04);
    } else if (rz) {
        [rz removeFromSuperview];
        objc_setAssociatedObject(view, kPACResizeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    PACRefreshPresentation(m, ov);
}

static void PACStripChrome(UIViewController *m) {
    UIView *view = m.view;
    if (!view) return;
    objc_setAssociatedObject(PACModuleButtonView(view), kPACIconPinKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [objc_getAssociatedObject(view, kPACBorderKey) removeFromSuperview];
    [objc_getAssociatedObject(view, kPACRemoveKey) removeFromSuperview];
    [objc_getAssociatedObject(view, kPACResizeKey) removeFromSuperview];
    objc_setAssociatedObject(view, kPACBorderKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, kPACRemoveKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, kPACResizeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void PACInstallGestures(UIViewController *ov) {
    if (!ov.view) return;
    if (objc_getAssociatedObject(ov, kPACGestKey)) return;
    objc_setAssociatedObject(ov, kPACGestKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc]
        initWithTarget:[PACEditProxy shared] action:@selector(bgHold:)];
    hold.minimumPressDuration = 0.55;
    hold.cancelsTouchesInView = NO;
    hold.delegate = [PACEditProxy shared];
    objc_setAssociatedObject(hold, kPACOwnGestureKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [ov.view addGestureRecognizer:hold];
}

%hook CCUIModuleCollectionViewController

- (CCUILayoutRect)layoutView:(id)layoutView layoutRectForSubview:(UIView *)subview {
    CCUILayoutRect r = %orig;
    if (!PACEditAllowed()) return r;
    PACRefreshGridConstants();

    NSDictionary *containers = nil;
    @try { containers = [(id)self valueForKey:@"moduleContainerViewByIdentifier"]; }
    @catch (__unused NSException *e) {}
    __block NSString *mid = nil;
    [containers enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
        UIView *cand = [value isKindOfClass:UIView.class] ? value
                    : ([value respondsToSelector:@selector(view)] ? [value view] : nil);
        if (cand == subview) { mid = key; *stop = YES; }
    }];
    if (!mid.length) return r;

    PACEnsureStore();

    PACMigrateMissingOrigins(OverlayIn(UIApplication.sharedApplication.keyWindow.rootViewController));

    if (!PACGetOrigin(mid) && !gEditOrigins[mid]) {
        PACSetOrigin(mid, @[@(r.origin.x), @(r.origin.y)]);
    }

    NSArray<NSNumber *> *sz = gEditSizes[mid];
    if (sz.count >= 2) {
        CCUILayoutSize s = { sz[0].unsignedIntegerValue, sz[1].unsignedIntegerValue };
        r.size = s;
    }

    BOOL pendingFresh = gPACPendingResizeID &&
                        [mid isEqualToString:gPACPendingResizeID] &&
                        gPACPendingResizeSize.width &&
                        gPACPendingResizeSize.height &&
                        (CACurrentMediaTime() - gPACPendingResizeLastTouch) < 3.0;
    if (pendingFresh) {
        r.size = gPACPendingResizeSize;
    }

    NSArray<NSNumber *> *o = PACGetOrigin(mid);
    if (!o) o = gEditOrigins[mid];
    if (o.count >= 2) {
        CCUILayoutPoint p = { o[0].unsignedIntegerValue, o[1].unsignedIntegerValue };
        r.origin = p;
    }
    return r;
}

- (CCUILayoutSize)moduleLayoutSizeForContentModuleContext:(id)context forOrientation:(NSInteger)orientation {
    CCUILayoutSize s = %orig;
    if (!PACEditAllowed()) return s;
    NSString *mid = nil;
    if ([context respondsToSelector:@selector(moduleIdentifier)]) {
        mid = ((id (*)(id, SEL))objc_msgSend)(context, @selector(moduleIdentifier));
    }
    if (!mid.length) return s;
    PACEnsureStore();

    NSArray<NSNumber *> *sz = gEditSizes[mid];
    if (sz.count >= 2) {
        CCUILayoutSize ns = { sz[0].unsignedIntegerValue, sz[1].unsignedIntegerValue };
        s = ns;
    }

    BOOL pendingFresh = gPACPendingResizeID &&
                        [mid isEqualToString:gPACPendingResizeID] &&
                        gPACPendingResizeSize.width &&
                        gPACPendingResizeSize.height &&
                        (CACurrentMediaTime() - gPACPendingResizeLastTouch) < 3.0;
    if (pendingFresh) {
        s = gPACPendingResizeSize;
    }
    return s;
}

%end

%hook CALayer

- (void)addAnimation:(CAAnimation *)anim forKey:(NSString *)key {
    if (gEditModeActive && PACShouldBlockGlyphAnimation((CALayer *)self, anim)) return;
    %orig;
}

%end

%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (!PACEditAllowed()) return;
    if ([NSStringFromClass(self.class) containsString:@"ControlCenterOverlayViewController"]) {
        PACRefreshGridConstants();
        PACInstallGestures((UIViewController *)self);
        UIViewController *selfOv = (UIViewController *)self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            PACUpdateGridMetrics(selfOv);
        });
    }
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    if (!gEditModeActive) return;
    if ([NSStringFromClass(self.class) containsString:@"ControlCenterOverlayViewController"]) {
        [[PACEditProxy shared] exitEditOn:(UIViewController *)self];
    }
}
%end

%hook CCUIContentModuleContainerViewController

- (void)viewDidLayoutSubviews {
    %orig;
    if (!PACEditAllowed()) {
        if (PACIsLandscape()) PACTearDownModule((UIViewController *)self);
        return;
    }
    UIViewController *ov = OverlayIn(UIApplication.sharedApplication.keyWindow.rootViewController);
    if (!ov) return;
    UIViewController *module = (UIViewController *)self;

    PACApplyRadiusToModule(module);
    PACRefreshPresentation(module, ov);

    __weak UIViewController *wm = module;
    __weak UIViewController *wo = ov;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *m2 = wm, *o2 = wo;
        if (!m2 || !o2) return;
        PACUpdateGridMetrics(o2);
        PACCSyncClones(o2, NO);
        PACApplyRadiusToModule(m2);
        PACRefreshPresentation(m2, o2);
    });
}

%end

%hook CCUIButtonModuleView

- (void)layoutSubviews {
    %orig;
    BOOL landscape = PACIsLandscape();
    if (!landscape && !PACEditAllowed()) return;
    UIResponder *r = (UIResponder *)(id)self;
    UIViewController *module = nil;
    while (r) {
        if ([r isKindOfClass:UIViewController.class] &&
            [NSStringFromClass(((UIViewController *)r).class) containsString:@"ContentModuleContainerViewController"]) {
            module = (UIViewController *)r;
            break;
        }
        r = r.nextResponder;
    }
    if (!module) return;
    if (landscape) { PACTearDownModule(module); return; }
    UIViewController *ov = OverlayIn(UIApplication.sharedApplication.keyWindow.rootViewController);
    if (!ov) return;

    PACApplyRadiusToModule(module);
    PACRefreshPresentation(module, ov);

    __weak UIViewController *wm = module;
    __weak UIViewController *wo = ov;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *m2 = wm, *o2 = wo;
        if (!m2 || !o2) return;
        PACApplyRadiusToModule(m2);
        PACRefreshPresentation(m2, o2);
    });
}

%end

%hook CCUIModularControlCenterOverlayViewController

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    %orig;
    gPACRotationQuietUntil = CACurrentMediaTime() + 1.0;
    if (size.width > size.height) {
        UIViewController *ov = (UIViewController *)self;
        if (gEditModeActive) [[PACEditProxy shared] exitEditOn:ov];
        PACTearDownAllModules(ov);
    }
    [coordinator animateAlongsideTransition:nil
                                 completion:^(__unused id<UIViewControllerTransitionCoordinatorContext> ctx) {
        PACScheduleRotationRefresh();
    }];
}

- (void)setPresentationState:(NSInteger)state {
    %orig;
    if (state == 1) return;
    if (!gEditModeActive) return;
    if (CACurrentMediaTime() - gEditModeEnteredAt < 1.0) return;
    [[PACEditProxy shared] exitEditOn:(UIViewController *)self];
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (PACIsLandscape()) {
        PACTearDownAllModules((UIViewController *)self);
        return;
    }
    if (!PACEditAllowed()) return;
    UIViewController *ov = (UIViewController *)self;
    if (!ov.view) return;

    PACRefreshGridConstants();

    for (NSInteger i = 0; i < 8; i++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                     (int64_t)(i * 0.12 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            UIViewController *o2 = OverlayIn(UIApplication.sharedApplication.keyWindow.rootViewController);
            if (!o2) return;
            if (!PACEditAllowed()) return;
            for (UIViewController *m in ModuleControllers(o2)) {
                PACApplyRadiusToModule(m);
                PACRefreshPresentation(m, o2);
            }
        });
    }
}

%end

static void PACPostRotationRefresh(void) {
    UIViewController *ov = OverlayIn(UIApplication.sharedApplication.keyWindow.rootViewController);
    if (!ov) return;
    if (PACIsLandscape()) {
        if (gEditModeActive) [[PACEditProxy shared] exitEditOn:ov];
        PACTearDownAllModules(ov);
        return;
    }
    if (!PACEditAllowed()) return;
    PACRefreshGridConstants();
    for (UIViewController *m in ModuleControllers(ov)) {
        if (!m.view) continue;
        objc_setAssociatedObject(m.view, kPACLastPresKey,   nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(m.view, kPACLastRadiusKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        PACApplyRadiusToModule(m);
        PACRefreshPresentation(m, ov);
    }
}

static void PACScheduleRotationRefresh(void) {
    gPACRotationQuietUntil = CACurrentMediaTime() + 1.0;
    static const double delays[] = { 0.0, 0.15, 0.45, 0.90 };
    for (size_t i = 0; i < sizeof(delays) / sizeof(delays[0]); i++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delays[i] * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ PACPostRotationRefresh(); });
    }
}

static void PACEditReload(__unused CFNotificationCenterRef c,
                          __unused void *o, __unused CFStringRef n,
                          __unused const void *obj,
                          __unused CFDictionaryRef u) {
    if (!gEditModeEnabled && gEditModeActive) {
        UIViewController *ov = OverlayIn(UIApplication.sharedApplication.keyWindow.rootViewController);
        if (ov) [[PACEditProxy shared] exitEditOn:ov];
    }
}

%ctor {
    @autoreleasepool {
        PACInitCachedClasses();
        %init(_ungrouped);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL, PACEditReload,
                                        (__bridge CFStringRef)kReloadNotification,
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);

        [[NSNotificationCenter defaultCenter] addObserverForName:UIDeviceOrientationDidChangeNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(__unused NSNotification *note) {
            UIDeviceOrientation o = UIDevice.currentDevice.orientation;
            if (!UIDeviceOrientationIsPortrait(o) && !UIDeviceOrientationIsLandscape(o)) return;
            dispatch_async(dispatch_get_main_queue(), ^{
                if (PACIsLandscape() && gEditModeActive) {
                    UIViewController *ov = OverlayIn(UIApplication.sharedApplication.keyWindow.rootViewController);
                    if (ov) [[PACEditProxy shared] exitEditOn:ov];
                }
                PACScheduleRotationRefresh();
            });
        }];
    }
}
