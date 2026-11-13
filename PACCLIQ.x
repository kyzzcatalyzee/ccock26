#import "PACC.h"
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <objc/runtime.h>
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include <notify.h>
#include <mach-o/dyld.h>

static NSString * const kPACCLIQPrefsDomain       = @"dylv.liquidassprefs";
static NSString * const kPACCLIQReloadNote        = @"dylv.liquidassprefs/Reload";
static NSString * const kPACCLIQGroupName         = @"dylv.liquidglass.sharedGroup";
static NSString * const kPACCLIQControlCenterType = @"dylv.liquidglass.cc.r2";
static const NSInteger  kPACCLIQGlassTag          = 190001;

static NSString *sPACCLIQActiveFilterType = nil;
static BOOL      sPACCLIQLiquidassFound = NO;
static BOOL      sPACCLIQLoggedProbe = NO;

#ifdef __cplusplus
extern "C" {
#endif
BOOL PACCLIQIsActive(void);
BOOL PACCLIQGlassOn(void);
id PACCLIQBuildGlassFilter(void);
#ifdef __cplusplus
}
#endif

typedef id (*PACCLIQFilterFactoryFn)(Class, SEL, NSString *);

static void PACCLIQLog(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
static void PACCLIQLog(const char *fmt, ...) {
    FILE *f = fopen("/var/mobile/Library/Accessibility/liquidglass.log", "a");
    if (!f) return;
    fputs("[PACCLIQ] ", f);
    va_list ap;
    va_start(ap, fmt);
    vfprintf(f, fmt, ap);
    va_end(ap);
    fputc('\n', f);
    fclose(f);
}

static BOOL PACCLIQControlCenterEnabled(void) {
    CFPreferencesAppSynchronize((__bridge CFStringRef)kPACCLIQPrefsDomain);
    Boolean valid = false;
    Boolean value = CFPreferencesGetAppBooleanValue(
        CFSTR("ControlCenter.Enabled"),
        (__bridge CFStringRef)kPACCLIQPrefsDomain,
        &valid);
    return valid ? (BOOL)value : YES;
}

static BOOL PACCLIQContainsCI(const char *haystack, const char *needle) {
    if (!haystack || !needle) return NO;
    size_t hn = strlen(haystack);
    size_t nn = strlen(needle);
    if (nn == 0 || nn > hn) return NO;
    for (size_t i = 0; i + nn <= hn; i++) {
        size_t j = 0;
        for (; j < nn; j++) {
            char a = haystack[i + j];
            char b = needle[j];
            if (a >= 'A' && a <= 'Z') a += 32;
            if (b >= 'A' && b <= 'Z') b += 32;
            if (a != b) break;
        }
        if (j == nn) return YES;
    }
    return NO;
}

static BOOL PACCLIQProbeLiquidass(void) {
    if (sPACCLIQLiquidassFound) return YES;

    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (!name) continue;
        if (PACCLIQContainsCI(name, "liquid") || PACCLIQContainsCI(name, "dylv")) {
            sPACCLIQLiquidassFound = YES;
            if (!sPACCLIQLoggedProbe) {
                sPACCLIQLoggedProbe = YES;
                PACCLIQLog("Liquidass found (dyld): %s", name);
            }
            return YES;
        }
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *roots = @[
        @"/var/jb/Library/MobileSubstrate/DynamicLibraries",
        @"/Library/MobileSubstrate/DynamicLibraries",
    ];
    for (NSString *root in roots) {
        NSArray<NSString *> *files = [fm contentsOfDirectoryAtPath:root error:nil];
        for (NSString *file in files) {
            const char *n = file.UTF8String;
            if (PACCLIQContainsCI(n, "liquid") || PACCLIQContainsCI(n, "dylv")) {
                sPACCLIQLiquidassFound = YES;
                if (!sPACCLIQLoggedProbe) {
                    sPACCLIQLoggedProbe = YES;
                    PACCLIQLog("Liquidass found (disk): %s", n);
                }
                return YES;
            }
        }
    }
    return NO;
}

static BOOL PACCLIQLiquidassLive(void) {
    static CFTimeInterval lastCheck = 0;
    static BOOL lastResult = NO;
    CFTimeInterval now = CACurrentMediaTime();
    if (lastCheck > 0 && now - lastCheck < 0.5) return lastResult;
    lastCheck = now;
    lastResult = PACCLIQProbeLiquidass() && PACCLIQControlCenterEnabled();
    return lastResult;
}

static BOOL PACCLIQShouldGlass(void) {
    return YES;
}

static id PACCLIQMakeFilter(NSString *typeName) {
    Class filterCls = NSClassFromString(@"CAFilter");
    if (!filterCls) return nil;
    SEL factorySel = NSSelectorFromString(@"filterWithType:");
    if (![filterCls respondsToSelector:factorySel]) return nil;
    PACCLIQFilterFactoryFn factory = (PACCLIQFilterFactoryFn)objc_msgSend;
    return factory(filterCls, factorySel, typeName);
}

#ifdef __cplusplus
extern "C" {
#endif

BOOL PACCLIQIsActive(void) {
    return PACCLIQLiquidassLive();
}

BOOL PACCLIQGlassOn(void) {
    return PACCLIQShouldGlass();
}

id PACCLIQBuildGlassFilter(void) {
    if (!PACCLIQLiquidassLive()) return nil;
    return PACCLIQMakeFilter(kPACCLIQControlCenterType);
}

#ifdef __cplusplus
}
#endif

static id PACCLIQPref(NSString *key) {
    static NSMutableDictionary *cache;
    static CFTimeInterval stamp = 0;
    CFTimeInterval now = CACurrentMediaTime();
    if (!cache || now - stamp > 1.0) {
        cache = [NSMutableDictionary dictionary];
        stamp = now;
        CFPreferencesAppSynchronize((__bridge CFStringRef)kPACCLIQPrefsDomain);
    }
    id cached = cache[key];
    if (cached) return [cached isKindOfClass:NSNull.class] ? nil : cached;
    id v = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)kPACCLIQPrefsDomain));
    cache[key] = v ?: NSNull.null;
    return v;
}

static int PACCLIQSpecularMode(void) {
    id m = PACCLIQPref(@"ControlCenter.SpecularMode");
    if ([m isKindOfClass:NSString.class]) {
        if ([m isEqualToString:@"none"]) return 0;
        if ([m isEqualToString:@"border"]) return 1;
        if ([m isEqualToString:@"glass"]) return 2;
    }
    id legacy = PACCLIQPref(@"ControlCenter.Specular.Mode");
    if ([legacy isKindOfClass:NSString.class]) {
        if ([legacy isEqualToString:@"none"]) return 0;
        if ([legacy isEqualToString:@"border"]) return 1;
        if ([legacy isEqualToString:@"glass"]) return 2;
    }
    id en = PACCLIQPref(@"ControlCenter.Specular.Enabled") ?: PACCLIQPref(@"ControlCenter.SpecularEnabled");
    if ([en respondsToSelector:@selector(boolValue)]) return [en boolValue] ? 2 : 0;
    return 2;
}

static BOOL PACCLIQSpecularIOS27(void) {
    id v = PACCLIQPref(@"Renderer.SpecularType");
    return [v isKindOfClass:NSString.class] && [v isEqualToString:@"ios27"];
}

static CGFloat PACCLIQNumPref(NSString *key, CGFloat fallback) {
    id v = PACCLIQPref(key);
    return [v respondsToSelector:@selector(doubleValue)] ? [v doubleValue] : fallback;
}

@interface PACCLIQGlassView : UIView {
    CAGradientLayer *_specLayer, *_darkLayer, *_fresnelLayer;
    CAShapeLayer *_specMask, *_darkMask, *_edgeLayer;
    NSString *_appliedType;
    CGFloat _appliedScale, _appliedBlur;
    int _appliedMode;
    BOOL _appliedIOS27;
    CGFloat _appliedOpacity, _appliedFresnel;
}
@property (nonatomic, assign) CGFloat glassCornerRadius;
- (instancetype)initWithFrame:(CGRect)frame cornerRadius:(CGFloat)radius;
- (void)applyGlassFilter;
- (void)forceReapply;
@end

@interface PACCLIQGlassView ()
- (BOOL)filterIsLive;
- (void)updateSpecularLayers;
@end

@implementation PACCLIQGlassView

+ (Class)layerClass {
    Class backdropCls = NSClassFromString(@"CABackdropLayer");
    return backdropCls ?: [CALayer class];
}

- (instancetype)initWithFrame:(CGRect)frame cornerRadius:(CGFloat)radius {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    _glassCornerRadius = radius;
    self.userInteractionEnabled = NO;
    self.backgroundColor = UIColor.clearColor;
    self.opaque = NO;
    self.layer.cornerRadius = radius;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.masksToBounds = YES;
    [self applyGlassFilter];
    return self;
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self applyGlassFilter];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.layer.cornerRadius = self.glassCornerRadius;
    [self applyGlassFilter];
    [self updateSpecularLayers];
}

- (NSString *)wantedType {
    CGSize b = self.bounds.size;
    CGFloat shortest = MIN(b.width, b.height);
    CGFloat ratio = shortest > 0 ? self.glassCornerRadius / shortest : 0;
    NSInteger step = (NSInteger)llround(MAX(0.0, MIN(0.5, ratio)) * 32.0);
    NSString *t = [NSString stringWithFormat:@"dylv.liquidglass.cc.r%ld", (long)step];
    if (self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) t = [t stringByAppendingString:@".dark"];
    return t;
}

- (BOOL)filterIsLive {
    NSArray *filters = self.layer.filters;
    if (!filters.count || !_appliedType.length) return NO;
    if ([_appliedType isEqualToString:@"pacc.fallback"]) return !PACCLIQLiquidassLive();
    NSString *type = nil;
    @try { type = [filters[0] valueForKey:@"type"]; } @catch (...) {}
    return type.length && [type isEqualToString:_appliedType];
}

- (void)applyGlassFilter {
    CALayer *layer = self.layer;
    Class backdropCls = NSClassFromString(@"CABackdropLayer");
    if (!backdropCls || ![layer isKindOfClass:backdropCls]) return;

    if (!PACCLIQShouldGlass()) {
        if (layer.filters.count) layer.filters = nil;
        _appliedType = nil;
        sPACCLIQActiveFilterType = nil;
        return;
    }

    @try {
        [layer setValue:@NO  forKey:@"layerUsesCoreImageFilters"];
        [layer setValue:@NO forKey:@"windowServerAware"];
        if (![layer valueForKey:@"groupName"]) {
            [layer setValue:[NSString stringWithFormat:@"dylv.liquidglass.pacc.%p", self] forKey:@"groupName"];
        }
        [layer setValue:@"dylv.liquidglass" forKey:@"groupNamespace"];
        [layer setValue:@YES forKey:@"ignoresScreenClip"];

        CGFloat area = self.bounds.size.width * self.bounds.size.height;
        CGFloat budget = PACCLIQNumPref(@"Global.ScaleBudget", 8000.0);
        if (!isfinite(budget)) budget = 8000.0;
        budget = MIN(32000.0, MAX(1000.0, budget));
        CGFloat scale = area <= 1.0 ? 0.75 : MIN(0.75, MAX(0.25, sqrt(budget / area)));
        if (fabs(scale - _appliedScale) > 0.02) {
            [layer setValue:@(scale) forKey:@"scale"];
            _appliedScale = scale;
        }

        if (!PACCLIQLiquidassLive()) {
            if ([_appliedType isEqualToString:@"pacc.fallback"] && layer.filters.count) return;
            id gb = PACCLIQMakeFilter(@"gaussianBlur");
            id sat = PACCLIQMakeFilter(@"colorSaturate");
            NSMutableArray *chain = [NSMutableArray array];
            if (gb) { [gb setValue:@(16.0) forKey:@"inputRadius"]; [chain addObject:gb]; }
            if (sat) { [sat setValue:@(1.8) forKey:@"inputAmount"]; [chain addObject:sat]; }
            if (chain.count) {
                layer.filters = chain;
                layer.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.07].CGColor;
                _appliedType = @"pacc.fallback";
                if (!sPACCLIQActiveFilterType) PACCLIQLog("LiquidAss is off: using the built-in glass");
                sPACCLIQActiveFilterType = @"pacc.fallback";
                return;
            }
        }
        layer.backgroundColor = NULL;

        CGFloat blur = MAX(0.0, PACCLIQNumPref(@"ControlCenter.Blur", 1.0));
        NSString *want = [self wantedType];
        if ([self filterIsLive] && [_appliedType isEqualToString:want] && fabs(blur - _appliedBlur) < 0.01) return;

        id glassFilter = PACCLIQMakeFilter(want);
        if (glassFilter) {
            NSMutableArray *chain = [NSMutableArray arrayWithObject:glassFilter];
            if (blur > 0.01) {
                id gb = PACCLIQMakeFilter(@"gaussianBlur");
                if (gb) { [gb setValue:@(blur) forKey:@"inputRadius"]; [chain addObject:gb]; }
            }
            NSString *previous = sPACCLIQActiveFilterType;
            sPACCLIQActiveFilterType = @"dylv.liquidglass.cc";
            if (!previous) PACCLIQLog("active filter = %s", want.UTF8String);
            layer.filters = chain;
            _appliedType = want;
            _appliedBlur = blur;
            return;
        }
        if (sPACCLIQActiveFilterType) PACCLIQLog("ControlCenter filter unavailable");
        sPACCLIQActiveFilterType = nil;
        _appliedType = nil;
    } @catch (NSException *e) {
        PACCLIQLog("applyGlassFilter exception: %s", e.reason.UTF8String);
    }
}

- (void)updateSpecularLayers {
    if (CGRectIsEmpty(self.bounds)) return;
    int mode = PACCLIQSpecularMode();
    CGRect rect = self.bounds;
    CGFloat shortest = MIN(rect.size.width, rect.size.height);
    CGFloat radius = MIN(self.glassCornerRadius, shortest * 0.5);
    BOOL circle = radius >= shortest * 0.5 - 1.5;
    NSString *curve = circle ? kCACornerCurveCircular : kCACornerCurveContinuous;

    if (mode == 0 || !PACCLIQShouldGlass()) {
        _specLayer.hidden = _darkLayer.hidden = _fresnelLayer.hidden = YES;
        _edgeLayer.hidden = YES;
        return;
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (mode == 1) {
        _specLayer.hidden = _darkLayer.hidden = _fresnelLayer.hidden = YES;
        if (!_edgeLayer) { _edgeLayer = [CAShapeLayer layer]; [self.layer addSublayer:_edgeLayer]; }
        _edgeLayer.hidden = NO;
        _edgeLayer.frame = rect;
        _edgeLayer.cornerRadius = radius;
        _edgeLayer.cornerCurve = curve;
        CGFloat sc = self.window.screen.scale ?: UIScreen.mainScreen.scale;
        _edgeLayer.borderWidth = 1.0 / MAX(sc, 1.0);
        _edgeLayer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.42].CGColor;
        [CATransaction commit];
        return;
    }
    _edgeLayer.hidden = YES;

    CGFloat maxAlpha = MAX(0.0, MIN(1.0, PACCLIQNumPref(@"ControlCenter.SpecularOpacity", 0.85)));
    CGFloat fres = MAX(0.0, MIN(1.0, PACCLIQNumPref(@"Renderer.FresnelGlareStrength", 0.5)));
    CGFloat glare = fres * 0.312 * maxAlpha;
    id clear = (id)UIColor.clearColor.CGColor;
    const CGFloat edgeW = 0.604, specW = 0.575, inset = 0.90;

    if (!_fresnelLayer) {
        _fresnelLayer = [CAGradientLayer layer];
        _fresnelLayer.locations = @[@0.0, @0.035, @0.09, @0.18, @0.28, @0.72, @0.82, @0.91, @0.965, @1.0];
        [self.layer insertSublayer:_fresnelLayer atIndex:0];
    }
    if (!_darkLayer) {
        _darkLayer = [CAGradientLayer layer];
        _darkLayer.locations = @[@0.0, @0.15, @0.30, @0.70, @0.85, @1.0];
        _darkMask = [CAShapeLayer layer];
        _darkMask.backgroundColor = UIColor.clearColor.CGColor;
        _darkMask.borderColor = UIColor.whiteColor.CGColor;
        _darkMask.borderWidth = edgeW;
        _darkLayer.mask = _darkMask;
        [self.layer addSublayer:_darkLayer];
    }
    if (!_specLayer) {
        _specLayer = [CAGradientLayer layer];
        _specLayer.locations = @[@0.0, @0.055, @0.12, @0.88, @0.945, @1.0];
        _specMask = [CAShapeLayer layer];
        _specMask.backgroundColor = UIColor.clearColor.CGColor;
        _specMask.borderColor = UIColor.whiteColor.CGColor;
        _specMask.borderWidth = specW;
        _specLayer.mask = _specMask;
        [self.layer addSublayer:_specLayer];
    }
    [self.layer insertSublayer:_darkLayer below:_specLayer];

    BOOL ios27 = PACCLIQSpecularIOS27();
    if (_appliedMode != 2 || _appliedIOS27 != ios27 || fabs(_appliedOpacity - maxAlpha) > 0.001 || fabs(_appliedFresnel - fres) > 0.001) {
        _appliedIOS27 = ios27;
        _fresnelLayer.colors = @[
            (id)[UIColor colorWithWhite:1 alpha:glare].CGColor,
            (id)[UIColor colorWithWhite:1 alpha:glare * 0.55].CGColor,
            (id)[UIColor colorWithWhite:1 alpha:glare * 0.22].CGColor,
            (id)[UIColor colorWithWhite:1 alpha:glare * 0.06].CGColor,
            clear, clear,
            (id)[UIColor colorWithWhite:1 alpha:glare * 0.06].CGColor,
            (id)[UIColor colorWithWhite:1 alpha:glare * 0.22].CGColor,
            (id)[UIColor colorWithWhite:1 alpha:glare * 0.55].CGColor,
            (id)[UIColor colorWithWhite:1 alpha:glare].CGColor];
        _darkLayer.colors = @[
            (id)[UIColor colorWithWhite:0 alpha:0.24].CGColor,
            (id)[UIColor colorWithWhite:0 alpha:0.36].CGColor,
            (id)[UIColor colorWithWhite:0 alpha:0.48].CGColor,
            (id)[UIColor colorWithWhite:0 alpha:0.48].CGColor,
            (id)[UIColor colorWithWhite:0 alpha:0.36].CGColor,
            (id)[UIColor colorWithWhite:0 alpha:0.28].CGColor];
        if (ios27) {
            static const CGFloat stops[12] = {0.12, 0.25, 0.42, 0.62, 0.82, 0.95, 0.95, 0.82, 0.62, 0.42, 0.25, 0.12};
            NSMutableArray *cols = [NSMutableArray array], *locs = [NSMutableArray array];
            for (int k = 0; k < 12; k++) {
                [cols addObject:(id)[UIColor colorWithWhite:1 alpha:stops[k] * maxAlpha].CGColor];
                [locs addObject:@(k / 11.0)];
            }
            _specLayer.colors = cols;
            _specLayer.locations = locs;
        } else {
            _specLayer.locations = @[@0.0, @0.055, @0.12, @0.88, @0.945, @1.0];
            _specLayer.colors = @[
                (id)[UIColor colorWithWhite:1 alpha:maxAlpha * 0.45].CGColor,
                (id)[UIColor colorWithWhite:1 alpha:maxAlpha * 0.20].CGColor,
                clear, clear,
                (id)[UIColor colorWithWhite:1 alpha:maxAlpha * 0.20].CGColor,
                (id)[UIColor colorWithWhite:1 alpha:maxAlpha * 0.45].CGColor];
        }
        _appliedMode = 2; _appliedOpacity = maxAlpha; _appliedFresnel = fres;
    }
    CGRect sr = CGRectInset(rect, inset, inset);
    if (sr.size.width <= 0 || sr.size.height <= 0) sr = rect;
    CGFloat srad = MAX(0.0, radius - inset);
    _fresnelLayer.hidden = fres <= 0.001;
    _fresnelLayer.frame = rect; _fresnelLayer.cornerRadius = radius; _fresnelLayer.cornerCurve = curve; _fresnelLayer.masksToBounds = YES;
    _darkLayer.hidden = NO;
    _darkLayer.frame = rect;
    _darkMask.frame = CGRectMake(0, 0, rect.size.width, rect.size.height);
    _darkMask.cornerRadius = radius; _darkMask.cornerCurve = curve;
    _specLayer.hidden = NO;
    _specLayer.frame = sr;
    _specMask.frame = CGRectMake(0, 0, sr.size.width, sr.size.height);
    _specMask.cornerRadius = srad; _specMask.cornerCurve = curve;
    CGFloat dx = ios27 ? 0.0 : cos(-3.0 * M_PI / 4.0) * 0.25;
    _darkLayer.startPoint = CGPointMake(0.5 + dx, 0.0); _darkLayer.endPoint = CGPointMake(0.5 - dx, 1.0);
    _fresnelLayer.startPoint = CGPointMake(0.5 + dx * 0.4, 0.0); _fresnelLayer.endPoint = CGPointMake(0.5 - dx * 0.4, 1.0);
    if (ios27) { _specLayer.startPoint = CGPointMake(0.0, 0.5); _specLayer.endPoint = CGPointMake(1.0, 0.5); _fresnelLayer.hidden = YES; }
    else { _specLayer.startPoint = CGPointMake(0.5 + dx, 0.0); _specLayer.endPoint = CGPointMake(0.5 - dx, 1.0); }
    [CATransaction commit];
}

- (void)forceReapply {
    self.layer.filters = nil;
    _appliedType = nil;
    _appliedScale = 0;
    [self applyGlassFilter];
    _appliedMode = -1;
    [self updateSpecularLayers];
}

@end

static void PACCLIQRestoreBlur(UIView *mediaPlayer) {
    if (!mediaPlayer) return;
    @try {
        UIView *blur = [mediaPlayer valueForKey:@"blurView"];
        if ([blur isKindOfClass:UIView.class]) blur.hidden = NO;
    } @catch (...) {}
}

static BOOL PACCLIQModuleHasLG(UIView *host) {
    UIView *module = nil;
    int up = 0;
    for (UIView *p = host.superview; p && up < 16; p = p.superview, up++) {
        if ([NSStringFromClass(p.class) isEqualToString:@"CCUIContentModuleContainerView"]) { module = p; break; }
    }
    if (!module) return NO;
    CGFloat mw = module.bounds.size.width;
    NSMutableArray *queue = [NSMutableArray arrayWithObject:module];
    NSUInteger seen = 0;
    while (queue.count && seen++ < 160) {
        UIView *v = queue.firstObject; [queue removeObjectAtIndex:0];
        if (v == host) continue;
        if ([NSStringFromClass(v.class) isEqualToString:@"LGLiveBackdropView"] && !v.hidden && v.alpha > 0.01 && v.bounds.size.width >= mw * 0.5) return YES;
        [queue addObjectsFromArray:v.subviews];
    }
    return NO;
}

static PACCLIQGlassView *PACCLIQInstallGlass(UIView *host, CGFloat radius) {
    if (!host) return nil;
    if (PACCLIQShouldGlass() && PACCLIQModuleHasLG(host)) {
        UIView *own = [host viewWithTag:kPACCLIQGlassTag];
        if (own) { own.layer.filters = nil; [own removeFromSuperview]; }
        return nil;
    }

    PACCLIQGlassView *glass = (PACCLIQGlassView *)[host viewWithTag:kPACCLIQGlassTag];

    if (!PACCLIQShouldGlass()) {
        if (glass) {
            glass.layer.filters = nil;
            glass.hidden = YES;
        }
        return nil;
    }

    if (!glass) {
        glass = [[PACCLIQGlassView alloc] initWithFrame:host.bounds cornerRadius:radius];
        glass.tag = kPACCLIQGlassTag;
        glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [host insertSubview:glass atIndex:0];
    }
    glass.hidden = NO;
    glass.frame = host.bounds;
    glass.glassCornerRadius = radius;
    if (![glass filterIsLive]) [glass forceReapply];
    [host sendSubviewToBack:glass];
    return glass;
}

BOOL PACCLIQApplyGlass(UIView *host, CGFloat radius) {
    if (!host) return NO;
    PACCLIQGlassView *glass = PACCLIQInstallGlass(host, radius);
    if (!glass && PACCLIQShouldGlass() && PACCLIQModuleHasLG(host)) return YES;
    return glass && [glass filterIsLive];
}

static void PACCLIQRemoveAllGlass(void) {
    UIViewController *overlay =
        OverlayIn(UIApplication.sharedApplication.keyWindow.rootViewController);
    if (!overlay) return;

    NSMutableArray<UIView *> *all = [NSMutableArray arrayWithObject:overlay.view];
    while (all.count) {
        UIView *v = all.firstObject;
        [all removeObjectAtIndex:0];
        PACCLIQGlassView *g = (PACCLIQGlassView *)[v viewWithTag:kPACCLIQGlassTag];
        if (g) {
            g.layer.filters = nil;
            [g removeFromSuperview];
        }
        [all addObjectsFromArray:v.subviews];
    }

    PACCLIQRestoreBlur([overlay.view viewWithTag:kMediaPlayerTag]);
    sPACCLIQActiveFilterType = nil;
}

%hook CCAMediaPlayerView
- (void)layoutSubviews {
    %orig;

    if (!PACCLIQShouldGlass()) {
        PACCLIQRestoreBlur(self);
        PACCLIQGlassView *stale = (PACCLIQGlassView *)[self viewWithTag:kPACCLIQGlassTag];
        if (stale) {
            stale.layer.filters = nil;
            [stale removeFromSuperview];
        }
        return;
    }

    PACCLIQGlassView *glass = PACCLIQInstallGlass(self, self.layer.cornerRadius);
    if (!glass) {
        if (PACCLIQModuleHasLG(self)) {
            @try { UIView *blur = [self valueForKey:@"blurView"]; if ([blur isKindOfClass:UIView.class]) blur.hidden = YES; } @catch (...) {}
        }
        return;
    }
    if ([glass filterIsLive]) {
        @try {
            UIView *blur = [self valueForKey:@"blurView"];
            if ([blur isKindOfClass:UIView.class]) blur.hidden = YES;
        } @catch (...) {}
    }
}
%end

static void PACCLIQReapplyAll(void) {
    UIViewController *overlay =
        OverlayIn(UIApplication.sharedApplication.keyWindow.rootViewController);
    if (!overlay) return;

    UIView *mediaPlayer = [overlay.view viewWithTag:kMediaPlayerTag];
    if (!mediaPlayer) return;

    PACCLIQGlassView *glass = (PACCLIQGlassView *)[mediaPlayer viewWithTag:kPACCLIQGlassTag];
    if (glass) [glass forceReapply];

    [mediaPlayer setNeedsLayout];
}

static void PACCLIQScheduleReapply(void) {
    for (NSNumber *delay in @[ @1.5, @3.0, @5.0, @8.0, @12.0 ]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                     (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (PACCLIQProbeLiquidass()) {
                PACCLIQReapplyAll();
            } else {
                PACCLIQRemoveAllGlass();
            }
        });
    }
}

static void PACCLIQPrefsReloadCallback(CFNotificationCenterRef center,
                                       void *observer,
                                       CFStringRef name,
                                       const void *object,
                                       CFDictionaryRef userInfo) {
    (void)center; (void)observer; (void)name; (void)object; (void)userInfo;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!PACCLIQProbeLiquidass()) {
            PACCLIQRemoveAllGlass();
            return;
        }
        PACCLIQReapplyAll();
    });
}

%ctor {
    @autoreleasepool {
        PACCLIQLog("PACCLIQ loaded");

        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            PACCLIQPrefsReloadCallback,
            (__bridge CFStringRef)kPACCLIQReloadNote,
            NULL,
            CFNotificationSuspensionBehaviorCoalesce);

        PACCLIQScheduleReapply();
    }
}

BOOL PACCLIQStyleRim(CAGradientLayer *g) {
    if (!g || !PACCLIQShouldGlass()) return NO;
    int mode = PACCLIQSpecularMode();
    g.hidden = (mode == 0);
    if (mode == 0) return YES;
    CGFloat maxAlpha = MAX(0.0, MIN(1.0, PACCLIQNumPref(@"ControlCenter.SpecularOpacity", 0.85)));
    id clear = (id)UIColor.clearColor.CGColor;
    if (mode == 1) {
        id c = (id)[UIColor colorWithWhite:1.0 alpha:0.42].CGColor;
        g.colors = @[c, c]; g.locations = @[@0.0, @1.0];
        g.startPoint = CGPointMake(0.5, 0.0); g.endPoint = CGPointMake(0.5, 1.0);
        return YES;
    }
    if (PACCLIQSpecularIOS27()) {
        static const CGFloat stops[12] = {0.12, 0.25, 0.42, 0.62, 0.82, 0.95, 0.95, 0.82, 0.62, 0.42, 0.25, 0.12};
        NSMutableArray *cols = [NSMutableArray array], *locs = [NSMutableArray array];
        for (int k = 0; k < 12; k++) {
            [cols addObject:(id)[UIColor colorWithWhite:1 alpha:stops[k] * maxAlpha].CGColor];
            [locs addObject:@(k / 11.0)];
        }
        g.colors = cols; g.locations = locs;
        g.startPoint = CGPointMake(0.0, 0.5); g.endPoint = CGPointMake(1.0, 0.5);
    } else {
        CGFloat dx = cos(-3.0 * M_PI / 4.0) * 0.25;
        g.colors = @[(id)[UIColor colorWithWhite:1 alpha:maxAlpha * 0.9].CGColor,
                     (id)[UIColor colorWithWhite:1 alpha:maxAlpha * 0.4].CGColor,
                     clear, clear,
                     (id)[UIColor colorWithWhite:1 alpha:maxAlpha * 0.4].CGColor,
                     (id)[UIColor colorWithWhite:1 alpha:maxAlpha * 0.9].CGColor];
        g.locations = @[@0.0, @0.055, @0.12, @0.88, @0.945, @1.0];
        g.startPoint = CGPointMake(0.5 + dx, 0.0); g.endPoint = CGPointMake(0.5 - dx, 1.0);
    }
    return YES;
}


BOOL PACCLIQStyleDarkEdge(CAGradientLayer *g) {
    if (!g || !PACCLIQShouldGlass()) return NO;
    int mode = PACCLIQSpecularMode();
    g.hidden = (mode != 2);
    if (mode != 2) return YES;
    g.colors = @[(id)[UIColor colorWithWhite:0 alpha:0.24].CGColor,
                 (id)[UIColor colorWithWhite:0 alpha:0.36].CGColor,
                 (id)[UIColor colorWithWhite:0 alpha:0.48].CGColor,
                 (id)[UIColor colorWithWhite:0 alpha:0.48].CGColor,
                 (id)[UIColor colorWithWhite:0 alpha:0.36].CGColor,
                 (id)[UIColor colorWithWhite:0 alpha:0.28].CGColor];
    g.locations = @[@0.0, @0.15, @0.30, @0.70, @0.85, @1.0];
    CGFloat dx = PACCLIQSpecularIOS27() ? 0.0 : cos(-3.0 * M_PI / 4.0) * 0.25;
    g.startPoint = CGPointMake(0.5 + dx, 0.0); g.endPoint = CGPointMake(0.5 - dx, 1.0);
    return YES;
}
