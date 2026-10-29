#import <Cocoa/Cocoa.h>

void DrawAppIcon(CGContextRef ctx, CGFloat size) {
    // Background squircle
    CGFloat margin = size * 0.08;
    CGFloat iconSize = size - (margin * 2.0);
    NSRect rect = NSMakeRect(margin, margin, iconSize, iconSize);
    CGFloat cornerRadius = size * 0.22;
    NSBezierPath *squircle = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:cornerRadius yRadius:cornerRadius];

    // Background gradient (Midnight navy to deep indigo)
    NSColor *startColor = [NSColor colorWithRed:0.07 green:0.09 blue:0.15 alpha:1.0];
    NSColor *endColor = [NSColor colorWithRed:0.12 green:0.16 blue:0.25 alpha:1.0];
    NSGradient *gradient = [[NSGradient alloc] initWithStartingColor:startColor endingColor:endColor];
    [gradient drawInBezierPath:squircle angle:-45.0];

    // Subtle inner border
    [NSGraphicsContext saveGraphicsState];
    [squircle setLineWidth:size * 0.015];
    [[NSColor colorWithRed:0.25 green:0.45 blue:0.85 alpha:0.4] setStroke];
    [squircle stroke];
    [NSGraphicsContext restoreGraphicsState];

    // Draw Headphones Arc
    CGFloat centerX = size / 2.0;
    CGFloat centerY = size * 0.54;
    CGFloat radius = size * 0.24;

    NSBezierPath *headband = [NSBezierPath bezierPath];
    [headband appendBezierPathWithArcWithCenter:NSMakePoint(centerX, centerY)
                                         radius:radius
                                     startAngle:0
                                       endAngle:180
                                      clockwise:NO];
    headband.lineWidth = size * 0.045;
    headband.lineCapStyle = NSLineCapStyleRound;
    [[NSColor colorWithRed:0.22 green:0.74 blue:0.97 alpha:1.0] setStroke];
    [headband stroke];

    // Earcups
    CGFloat earcupWidth = size * 0.09;
    CGFloat earcupHeight = size * 0.16;
    CGFloat earcupRadius = size * 0.045;

    // Left earcup
    NSRect leftCup = NSMakeRect(centerX - radius - (earcupWidth / 2.0), centerY - (earcupHeight / 2.0), earcupWidth, earcupHeight);
    NSBezierPath *leftCupPath = [NSBezierPath bezierPathWithRoundedRect:leftCup xRadius:earcupRadius yRadius:earcupRadius];
    [[NSColor colorWithRed:0.18 green:0.55 blue:0.92 alpha:1.0] setFill];
    [leftCupPath fill];

    // Right earcup
    NSRect rightCup = NSMakeRect(centerX + radius - (earcupWidth / 2.0), centerY - (earcupHeight / 2.0), earcupWidth, earcupHeight);
    NSBezierPath *rightCupPath = [NSBezierPath bezierPathWithRoundedRect:rightCup xRadius:earcupRadius yRadius:earcupRadius];
    [rightCupPath fill];

    // Central Shield / Lock
    CGFloat shieldW = size * 0.26;
    CGFloat shieldH = size * 0.30;
    CGFloat shieldX = centerX - (shieldW / 2.0);
    CGFloat shieldY = size * 0.28;

    NSBezierPath *shield = [NSBezierPath bezierPath];
    [shield moveToPoint:NSMakePoint(centerX, shieldY)];
    [shield lineToPoint:NSMakePoint(shieldX + shieldW, shieldY + shieldH * 0.35)];
    [shield lineToPoint:NSMakePoint(shieldX + shieldW, shieldY + shieldH)];
    [shield lineToPoint:NSMakePoint(shieldX, shieldY + shieldH)];
    [shield lineToPoint:NSMakePoint(shieldX, shieldY + shieldH * 0.35)];
    [shield closePath];

    NSGradient *shieldGrad = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithRed:0.95 green:0.65 blue:0.15 alpha:1.0]
                                                            endingColor:[NSColor colorWithRed:0.98 green:0.80 blue:0.25 alpha:1.0]];
    [shieldGrad drawInBezierPath:shield angle:90.0];

    // Lock Shackle on shield
    CGFloat shackleRadius = size * 0.045;
    CGFloat shackleCenterY = shieldY + shieldH * 0.65;
    NSBezierPath *shackle = [NSBezierPath bezierPath];
    [shackle appendBezierPathWithArcWithCenter:NSMakePoint(centerX, shackleCenterY)
                                        radius:shackleRadius
                                    startAngle:0
                                      endAngle:180
                                     clockwise:NO];
    shackle.lineWidth = size * 0.025;
    [[NSColor colorWithRed:0.15 green:0.18 blue:0.25 alpha:1.0] setStroke];
    [shackle stroke];

    // Keyhole
    CGFloat keyholeY = shieldY + shieldH * 0.40;
    NSBezierPath *keyholeCircle = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(centerX - size * 0.02, keyholeY, size * 0.04, size * 0.04)];
    [[NSColor colorWithRed:0.15 green:0.18 blue:0.25 alpha:1.0] setFill];
    [keyholeCircle fill];
    
    NSBezierPath *keyholeStem = [NSBezierPath bezierPathWithRect:NSMakeRect(centerX - size * 0.012, keyholeY - size * 0.03, size * 0.024, size * 0.035)];
    [keyholeStem fill];
}

int main() {
    @autoreleasepool {
        int sizes[] = {16, 32, 64, 128, 256, 512, 1024};
        NSString *iconsetPath = @"resources/AppIcon.iconset";
        [[NSFileManager defaultManager] createDirectoryAtPath:iconsetPath withIntermediateDirectories:YES attributes:nil error:nil];

        for (int i = 0; i < 7; i++) {
            int s = sizes[i];
            NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                            pixelsWide:s
                                                                            pixelsHigh:s
                                                                         bitsPerSample:8
                                                                       samplesPerPixel:4
                                                                              hasAlpha:YES
                                                                              isPlanar:NO
                                                                        colorSpaceName:NSCalibratedRGBColorSpace
                                                                           bytesPerRow:0
                                                                          bitsPerPixel:0];

            NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
            [NSGraphicsContext setCurrentContext:context];
            DrawAppIcon(context.CGContext, (CGFloat)s);

            NSData *pngData = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
            
            NSString *filename = nil;
            if (s == 1024) {
                filename = [NSString stringWithFormat:@"%@/icon_512x512@2x.png", iconsetPath];
            } else {
                filename = [NSString stringWithFormat:@"%@/icon_%dx%d.png", iconsetPath, s, s];
            }
            [pngData writeToFile:filename atomically:YES];
            
            // Generate @2x for smaller sizes
            if (s <= 256) {
                int s2 = s * 2;
                NSBitmapImageRep *rep2 = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                                pixelsWide:s2
                                                                                pixelsHigh:s2
                                                                             bitsPerSample:8
                                                                           samplesPerPixel:4
                                                                                  hasAlpha:YES
                                                                                  isPlanar:NO
                                                                            colorSpaceName:NSCalibratedRGBColorSpace
                                                                               bytesPerRow:0
                                                                              bitsPerPixel:0];
                NSGraphicsContext *ctx2 = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep2];
                [NSGraphicsContext setCurrentContext:ctx2];
                DrawAppIcon(ctx2.CGContext, (CGFloat)s2);
                NSData *png2 = [rep2 representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
                NSString *fn2 = [NSString stringWithFormat:@"%@/icon_%dx%d@2x.png", iconsetPath, s, s];
                [png2 writeToFile:fn2 atomically:YES];
            }
        }

        NSLog(@"Iconset PNGs generated successfully!");
    }
    return 0;
}
