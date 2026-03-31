#import <AppKit/AppKit.h>

static NSColor *HexColor(NSUInteger hex, CGFloat alpha) {
    CGFloat red = ((hex >> 16) & 0xFF) / 255.0;
    CGFloat green = ((hex >> 8) & 0xFF) / 255.0;
    CGFloat blue = (hex & 0xFF) / 255.0;
    return [NSColor colorWithSRGBRed:red green:green blue:blue alpha:alpha];
}

static NSBezierPath *RoundedRectPath(CGRect rect, CGFloat radius) {
    return [NSBezierPath bezierPathWithRoundedRect:rect xRadius:radius yRadius:radius];
}

static void FillFourPointSpark(CGPoint center, CGFloat radius, NSColor *color) {
    NSBezierPath *path = [NSBezierPath bezierPath];
    [path moveToPoint:NSMakePoint(center.x, center.y + radius)];
    [path lineToPoint:NSMakePoint(center.x + radius * 0.36, center.y + radius * 0.36)];
    [path lineToPoint:NSMakePoint(center.x + radius, center.y)];
    [path lineToPoint:NSMakePoint(center.x + radius * 0.36, center.y - radius * 0.36)];
    [path lineToPoint:NSMakePoint(center.x, center.y - radius)];
    [path lineToPoint:NSMakePoint(center.x - radius * 0.36, center.y - radius * 0.36)];
    [path lineToPoint:NSMakePoint(center.x - radius, center.y)];
    [path lineToPoint:NSMakePoint(center.x - radius * 0.36, center.y + radius * 0.36)];
    [path closePath];
    [color setFill];
    [path fill];
}

static NSBezierPath *BellBodyPath(CGRect rect) {
    CGFloat minX = NSMinX(rect);
    CGFloat maxX = NSMaxX(rect);
    CGFloat minY = NSMinY(rect);
    CGFloat maxY = NSMaxY(rect);
    CGFloat midX = NSMidX(rect);

    NSBezierPath *path = [NSBezierPath bezierPath];
    [path moveToPoint:NSMakePoint(minX + rect.size.width * 0.14, minY + rect.size.height * 0.08)];
    [path curveToPoint:NSMakePoint(minX + rect.size.width * 0.24, maxY - rect.size.height * 0.04)
          controlPoint1:NSMakePoint(minX + rect.size.width * 0.12, minY + rect.size.height * 0.44)
          controlPoint2:NSMakePoint(minX + rect.size.width * 0.16, maxY - rect.size.height * 0.16)];
    [path curveToPoint:NSMakePoint(maxX - rect.size.width * 0.24, maxY - rect.size.height * 0.04)
          controlPoint1:NSMakePoint(minX + rect.size.width * 0.32, maxY + rect.size.height * 0.06)
          controlPoint2:NSMakePoint(maxX - rect.size.width * 0.32, maxY + rect.size.height * 0.06)];
    [path curveToPoint:NSMakePoint(maxX - rect.size.width * 0.14, minY + rect.size.height * 0.08)
          controlPoint1:NSMakePoint(maxX - rect.size.width * 0.16, maxY - rect.size.height * 0.16)
          controlPoint2:NSMakePoint(maxX - rect.size.width * 0.12, minY + rect.size.height * 0.44)];
    [path lineToPoint:NSMakePoint(maxX - rect.size.width * 0.07, minY)];
    [path curveToPoint:NSMakePoint(minX + rect.size.width * 0.07, minY)
          controlPoint1:NSMakePoint(maxX - rect.size.width * 0.05, minY - rect.size.height * 0.03)
          controlPoint2:NSMakePoint(minX + rect.size.width * 0.05, minY - rect.size.height * 0.03)];
    [path closePath];

    NSBezierPath *handle = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(midX - rect.size.width * 0.12,
                                                                              maxY - rect.size.height * 0.04,
                                                                              rect.size.width * 0.24,
                                                                              rect.size.height * 0.13)
                                                           xRadius:rect.size.width * 0.08
                                                           yRadius:rect.size.width * 0.08];
    [path appendBezierPath:handle];

    return path;
}

static void DrawIcon(CGFloat size) {
    [[NSColor clearColor] setFill];
    NSRectFill(NSMakeRect(0, 0, size, size));

    CGFloat inset = size * 0.055;
    CGRect canvas = CGRectInset(CGRectMake(0, 0, size, size), inset, inset);
    CGFloat radius = size * 0.225;

    NSBezierPath *base = RoundedRectPath(canvas, radius);
    [NSGraphicsContext saveGraphicsState];
    [base addClip];

    NSGradient *backgroundGradient = [[NSGradient alloc] initWithColorsAndLocations:
                                      HexColor(0x0E6B77, 1.0), 0.0,
                                      HexColor(0x0B5168, 1.0), 0.52,
                                      HexColor(0x083A54, 1.0), 1.0,
                                      nil];
    [backgroundGradient drawInRect:canvas angle:90.0];

    NSGradient *glowGradient = [[NSGradient alloc] initWithColorsAndLocations:
                                [HexColor(0x7DE3D5, 0.95) colorWithAlphaComponent:0.95], 0.0,
                                [HexColor(0x7DE3D5, 0.0) colorWithAlphaComponent:0.0], 1.0,
                                nil];
    [glowGradient drawInBezierPath:[NSBezierPath bezierPathWithOvalInRect:CGRectMake(size * 0.10, size * 0.50, size * 0.62, size * 0.52)] relativeCenterPosition:NSMakePoint(-0.2, 0.15)];

    NSBezierPath *highlight = [NSBezierPath bezierPathWithOvalInRect:CGRectMake(size * 0.18, size * 0.62, size * 0.42, size * 0.22)];
    [[HexColor(0xEFFFFB, 0.22) colorWithAlphaComponent:0.22] setFill];
    [highlight fill];
    [NSGraphicsContext restoreGraphicsState];

    [[HexColor(0x062E45, 0.18) colorWithAlphaComponent:0.18] setFill];
    [[NSBezierPath bezierPathWithOvalInRect:CGRectMake(size * 0.26, size * 0.11, size * 0.48, size * 0.12)] fill];

    NSShadow *shadow = [[NSShadow alloc] init];
    shadow.shadowOffset = NSMakeSize(0, -size * 0.012);
    shadow.shadowBlurRadius = size * 0.04;
    shadow.shadowColor = [HexColor(0x042B3A, 0.28) colorWithAlphaComponent:0.28];

    CGRect bellRect = CGRectMake(size * 0.25, size * 0.25, size * 0.50, size * 0.46);
    NSBezierPath *bellBody = BellBodyPath(bellRect);
    [NSGraphicsContext saveGraphicsState];
    [shadow set];
    [HexColor(0xF7FBFF, 1.0) setFill];
    [bellBody fill];
    [NSGraphicsContext restoreGraphicsState];

    [[HexColor(0xDCEBFA, 0.95) colorWithAlphaComponent:0.95] setFill];
    [[NSBezierPath bezierPathWithOvalInRect:CGRectMake(size * 0.44, size * 0.18, size * 0.12, size * 0.12)] fill];

    NSBezierPath *sweep = [NSBezierPath bezierPath];
    [sweep moveToPoint:NSMakePoint(size * 0.22, size * 0.31)];
    [sweep curveToPoint:NSMakePoint(size * 0.78, size * 0.43)
          controlPoint1:NSMakePoint(size * 0.34, size * 0.18)
          controlPoint2:NSMakePoint(size * 0.65, size * 0.50)];
    sweep.lineWidth = MAX(size * 0.045, 6.0);
    sweep.lineCapStyle = NSLineCapStyleRound;
    [HexColor(0x7DE3D5, 1.0) setStroke];
    [sweep stroke];

    NSBezierPath *accent = [NSBezierPath bezierPath];
    [accent moveToPoint:NSMakePoint(size * 0.28, size * 0.24)];
    [accent curveToPoint:NSMakePoint(size * 0.69, size * 0.34)
           controlPoint1:NSMakePoint(size * 0.37, size * 0.16)
           controlPoint2:NSMakePoint(size * 0.59, size * 0.39)];
    accent.lineWidth = MAX(size * 0.016, 2.0);
    accent.lineCapStyle = NSLineCapStyleRound;
    [[HexColor(0xC2FFF1, 0.82) colorWithAlphaComponent:0.82] setStroke];
    [accent stroke];

    FillFourPointSpark(CGPointMake(size * 0.73, size * 0.70), size * 0.09, HexColor(0xFFD36E, 1.0));
    FillFourPointSpark(CGPointMake(size * 0.82, size * 0.56), size * 0.045, HexColor(0xFFF2C8, 1.0));
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 3) {
            fprintf(stderr, "usage: %s OUTPUT SIZE\n", argv[0]);
            return 1;
        }

        NSString *outputPath = [NSString stringWithUTF8String:argv[1]];
        CGFloat size = [[NSString stringWithUTF8String:argv[2]] doubleValue];
        if (size <= 0) {
            fprintf(stderr, "size must be positive\n");
            return 1;
        }

        NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(size, size)];
        [image lockFocus];
        DrawIcon(size);
        [image unlockFocus];

        NSBitmapImageRep *representation = [[NSBitmapImageRep alloc] initWithData:[image TIFFRepresentation]];
        NSData *pngData = [representation representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        if (pngData == nil || ![pngData writeToFile:outputPath atomically:YES]) {
            fprintf(stderr, "failed to write %s\n", argv[1]);
            return 1;
        }
    }

    return 0;
}
