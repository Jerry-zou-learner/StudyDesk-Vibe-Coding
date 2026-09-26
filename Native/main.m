#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CoreGraphics.h>

static NSString * const SDSchema = @"studydesk/v1";
static NSString * const SDLaunchAgentLabel = @"io.github.studydesk.StudyDesk";

@interface SDFlippedView : NSView
@end

@implementation SDFlippedView
- (BOOL)isFlipped { return YES; }
@end

@interface SDFlippedStackView : NSStackView
@end

@implementation SDFlippedStackView
- (BOOL)isFlipped { return YES; }
@end

@interface SDRootView : NSView
@end

@implementation SDRootView
- (void)drawRect:(NSRect)dirtyRect {
    [[NSColor colorWithSRGBRed:0.961 green:0.941 blue:0.910 alpha:1.0] setFill];
    NSRectFill(dirtyRect);
}
@end

@interface SDMarkdownParser : NSObject
+ (NSDictionary *)documentAtURL:(NSURL *)url fallbackSource:(NSString *)fallback error:(NSError **)error;
@end

@implementation SDMarkdownParser

+ (NSArray<NSString *> *)splitRow:(NSString *)line {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    NSMutableString *current = [NSMutableString string];
    BOOL escaped = NO;
    for (NSUInteger i = 0; i < line.length; i++) {
        unichar character = [line characterAtIndex:i];
        if (escaped) {
            [current appendFormat:@"%C", character];
            escaped = NO;
        } else if (character == '\\') {
            escaped = YES;
        } else if (character == '|') {
            [parts addObject:[current stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet]];
            [current setString:@""];
        } else {
            [current appendFormat:@"%C", character];
        }
    }
    [parts addObject:[current stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet]];
    if (parts.count && [parts.firstObject length] == 0) [parts removeObjectAtIndex:0];
    if (parts.count && [parts.lastObject length] == 0) [parts removeLastObject];
    return parts;
}

+ (NSString *)plain:(NSString *)value {
    NSString *result = [value stringByReplacingOccurrencesOfString:@"**" withString:@""];
    result = [result stringByReplacingOccurrencesOfString:@"`" withString:@""];
    return [result stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

+ (NSString *)firstLink:(NSString *)value {
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"https?://[^\\s)>]+" options:0 error:nil];
    NSTextCheckingResult *match = [regex firstMatchInString:value options:0 range:NSMakeRange(0, value.length)];
    return match ? [value substringWithRange:match.range] : @"";
}

+ (NSDictionary *)documentAtURL:(NSURL *)url fallbackSource:(NSString *)fallback error:(NSError **)error {
    NSString *text = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:error];
    if (!text) return nil;
    NSArray<NSString *> *lines = [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];

    NSMutableDictionary *metadata = [NSMutableDictionary dictionary];
    if (lines.count && [[lines.firstObject stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet] isEqualToString:@"---"]) {
        for (NSUInteger i = 1; i < lines.count; i++) {
            NSString *line = lines[i];
            if ([[line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet] isEqualToString:@"---"]) break;
            NSRange separator = [line rangeOfString:@":"];
            if (separator.location == NSNotFound) continue;
            NSString *key = [[line substringToIndex:separator.location] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            NSString *value = [[line substringFromIndex:separator.location + 1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            metadata[key] = [value stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\"'"]];
        }
    }

    if (![metadata[@"schema"] isEqualToString:SDSchema]) {
        if (error) *error = [NSError errorWithDomain:@"StudyDesk" code:1 userInfo:@{NSLocalizedDescriptionKey: @"The file is not using studydesk/v1."}];
        return nil;
    }

    NSInteger sectionIndex = NSNotFound;
    for (NSUInteger i = 0; i < lines.count; i++) {
        if ([[lines[i] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet] isEqualToString:@"## Items"]) {
            sectionIndex = (NSInteger)i;
            break;
        }
    }
    if (sectionIndex == NSNotFound) {
        if (error) *error = [NSError errorWithDomain:@"StudyDesk" code:2 userInfo:@{NSLocalizedDescriptionKey: @"The file does not contain an ## Items table."}];
        return nil;
    }

    NSInteger headerIndex = NSNotFound;
    for (NSUInteger i = (NSUInteger)sectionIndex + 1; i < lines.count; i++) {
        NSString *line = [lines[i] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if ([line hasPrefix:@"## "]) break;
        if ([line hasPrefix:@"|"]) { headerIndex = (NSInteger)i; break; }
    }

    NSArray *required = @[@"id", @"priority", @"type", @"course / group", @"item", @"start", @"deadline", @"status", @"details", @"next action", @"link", @"last updated"];
    if (headerIndex == NSNotFound) {
        if (error) *error = [NSError errorWithDomain:@"StudyDesk" code:3 userInfo:@{NSLocalizedDescriptionKey: @"The Items table is missing."}];
        return nil;
    }
    NSMutableArray *headers = [NSMutableArray array];
    for (NSString *value in [self splitRow:lines[(NSUInteger)headerIndex]]) {
        [headers addObject:[[self plain:value] lowercaseString]];
    }
    if (![headers isEqualToArray:required]) {
        if (error) *error = [NSError errorWithDomain:@"StudyDesk" code:4 userInfo:@{NSLocalizedDescriptionKey: @"The Items table columns do not match studydesk/v1."}];
        return nil;
    }

    NSMutableArray *items = [NSMutableArray array];
    for (NSUInteger i = (NSUInteger)headerIndex + 2; i < lines.count; i++) {
        NSString *line = [lines[i] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if ([line hasPrefix:@"## "] || (line.length && ![line hasPrefix:@"|"])) break;
        if (![line hasPrefix:@"|"]) continue;
        NSArray *cells = [self splitRow:line];
        if (cells.count != required.count) continue;
        NSMutableDictionary *item = [NSMutableDictionary dictionary];
        for (NSUInteger column = 0; column < required.count; column++) {
            item[required[column]] = [self plain:cells[column]];
        }
        item[@"_openLink"] = [self firstLink:item[@"link"]];
        if ([item[@"id"] length]) [items addObject:item];
    }

    return @{
        @"source": metadata[@"source"] ?: fallback,
        @"title": metadata[@"title"] ?: @"StudyDesk",
        @"updatedAt": metadata[@"updated_at"] ?: @"",
        @"path": url,
        @"items": items
    };
}
@end

@interface SDAppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate>
@property(nonatomic, strong) NSPanel *panel;
@property(nonatomic, strong) NSStatusItem *statusItem;
@property(nonatomic, strong) NSMenuItem *launchAtLoginItem;
@property(nonatomic, strong) NSButton *weekButton;
@property(nonatomic, strong) NSButton *studyButton;
@property(nonatomic, strong) NSButton *emailButton;
@property(nonatomic, copy) NSString *selectedSourceName;
@property(nonatomic, strong) NSTextField *sourceTitleLabel;
@property(nonatomic, strong) NSTextField *sourceMetaLabel;
@property(nonatomic, strong) NSTextField *actionCountLabel;
@property(nonatomic, strong) NSStackView *itemsStack;
@property(nonatomic, strong) NSScrollView *itemsScroll;
@property(nonatomic, strong) NSArray<NSDictionary *> *renderedItems;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *documents;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *errors;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *fingerprints;
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic) BOOL editorOpen;
@property(nonatomic, strong) NSPanel *editorPanel;
@property(nonatomic, copy) NSString *editingSource;
@property(nonatomic, copy) NSString *editingIdentifier;
@property(nonatomic, strong) NSTextField *editorTitle;
@property(nonatomic, strong) NSTextField *editorCourse;
@property(nonatomic, strong) NSTextField *editorStart;
@property(nonatomic, strong) NSTextField *editorDeadline;
@property(nonatomic, strong) NSTextField *editorAction;
@property(nonatomic, strong) NSTextField *editorDetails;
@property(nonatomic, strong) NSPopUpButton *editorPriority;
@property(nonatomic, strong) NSPopUpButton *editorStatus;
@end

@implementation SDAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.documents = [NSMutableDictionary dictionary];
    self.errors = [NSMutableDictionary dictionary];
    self.fingerprints = [NSMutableDictionary dictionary];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    [self buildPanel];
    [self buildStatusItem];
    [self refresh:YES];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(timerFired:) userInfo:nil repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
    [self configureLaunchAtLoginIfNeeded];
    [self showPanelInFront];
}

- (void)showPanelInFront {
    self.panel.level = NSFloatingWindowLevel;
    [self.panel makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)applicationDidResignActive:(NSNotification *)notification {
    if (self.panel.visible) {
        self.panel.level = CGWindowLevelForKey(kCGDesktopWindowLevelKey) + 1;
        [self.panel orderFrontRegardless];
    }
}

- (void)buildPanel {
    NSRect frame = NSMakeRect(0, 0, 650, 680);
    self.panel = [[NSPanel alloc] initWithContentRect:frame
                                            styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable | NSWindowStyleMaskFullSizeContentView
                                              backing:NSBackingStoreBuffered
                                                defer:NO];
    self.panel.title = @"StudyDesk";
    self.panel.titleVisibility = NSWindowTitleHidden;
    self.panel.titlebarAppearsTransparent = YES;
    self.panel.opaque = YES;
    self.panel.backgroundColor = [NSColor colorWithSRGBRed:0.961 green:0.941 blue:0.910 alpha:1.0];
    self.panel.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    self.panel.movableByWindowBackground = YES;
    self.panel.minSize = NSMakeSize(520, 520);
    self.panel.level = CGWindowLevelForKey(kCGDesktopWindowLevelKey) + 1;
    self.panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorStationary | NSWindowCollectionBehaviorIgnoresCycle;
    self.panel.delegate = self;
    [self.panel setFrameAutosaveName:@"StudyDeskPanelFrame"];
    [self.panel center];

    NSView *root = [[SDRootView alloc] initWithFrame:frame];
    root.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    root.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.panel.contentView = root;

    NSColor *primaryText = [NSColor colorWithSRGBRed:0.184 green:0.169 blue:0.153 alpha:1.0];
    NSColor *secondaryText = [NSColor colorWithSRGBRed:0.490 green:0.459 blue:0.427 alpha:1.0];
    NSTextField *headline = [self label:@"StudyDesk" size:29 weight:NSFontWeightRegular color:primaryText];
    NSFontDescriptor *serifDescriptor = [headline.font.fontDescriptor fontDescriptorWithDesign:NSFontDescriptorSystemDesignSerif];
    if (serifDescriptor) headline.font = [NSFont fontWithDescriptor:serifDescriptor size:29];
    NSTextField *subtitle = [self label:@"Today’s academic pulse" size:13 weight:NSFontWeightRegular color:secondaryText];
    NSStackView *titles = [NSStackView stackViewWithViews:@[headline, subtitle]];
    titles.orientation = NSUserInterfaceLayoutOrientationVertical;
    titles.alignment = NSLayoutAttributeLeading;
    titles.spacing = 2;

    self.actionCountLabel = [self label:@"●  Updated just now" size:11 weight:NSFontWeightMedium color:[NSColor colorWithSRGBRed:0.390 green:0.553 blue:0.337 alpha:1.0]];
    NSButton *refreshButton = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"arrow.clockwise" accessibilityDescription:@"Refresh"] target:self action:@selector(refreshClicked:)];
    refreshButton.bordered = NO;
    refreshButton.toolTip = @"Refresh now";
    refreshButton.contentTintColor = secondaryText;

    NSStackView *header = [NSStackView stackViewWithViews:@[titles, self.actionCountLabel, refreshButton]];
    header.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    header.alignment = NSLayoutAttributeCenterY;
    header.spacing = 14;
    header.distribution = NSStackViewDistributionFill;
    [titles setHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];

    self.selectedSourceName = @"week";
    self.weekButton = [NSButton buttonWithTitle:@"This Week" target:self action:@selector(sourceChanged:)];
    self.weekButton.tag = 0;
    self.studyButton = [NSButton buttonWithTitle:@"Study Group" target:self action:@selector(sourceChanged:)];
    self.studyButton.tag = 1;
    self.emailButton = [NSButton buttonWithTitle:@"Email" target:self action:@selector(sourceChanged:)];
    self.emailButton.tag = 2;
    for (NSButton *button in @[self.weekButton, self.studyButton, self.emailButton]) {
        button.bordered = NO;
        button.wantsLayer = YES;
        button.layer.cornerRadius = 9;
        [button.heightAnchor constraintEqualToConstant:34].active = YES;
    }
    [self.weekButton.widthAnchor constraintEqualToConstant:112].active = YES;
    [self.studyButton.widthAnchor constraintEqualToConstant:128].active = YES;
    [self.emailButton.widthAnchor constraintEqualToConstant:82].active = YES;
    [self updateSourceButtonStyles];
    NSStackView *sourceButtons = [NSStackView stackViewWithViews:@[self.weekButton, self.studyButton, self.emailButton]];
    sourceButtons.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    sourceButtons.spacing = 0;
    sourceButtons.edgeInsets = NSEdgeInsetsMake(3, 3, 3, 3);
    sourceButtons.wantsLayer = YES;
    sourceButtons.layer.backgroundColor = [NSColor colorWithSRGBRed:0.925 green:0.894 blue:0.851 alpha:1.0].CGColor;
    sourceButtons.layer.cornerRadius = 11;
    NSStackView *switcher = [NSStackView stackViewWithViews:@[sourceButtons]];
    switcher.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    switcher.alignment = NSLayoutAttributeCenterY;
    switcher.spacing = 0;
    switcher.distribution = NSStackViewDistributionFill;

    self.sourceTitleLabel = [self label:@"UPCOMING" size:10 weight:NSFontWeightSemibold color:secondaryText];
    self.sourceTitleLabel.font = [NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightSemibold];
    self.sourceMetaLabel = [self label:@"" size:11 weight:NSFontWeightRegular color:secondaryText];
    self.sourceMetaLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    NSStackView *sourceInfo = [NSStackView stackViewWithViews:@[self.sourceTitleLabel, self.sourceMetaLabel]];
    sourceInfo.orientation = NSUserInterfaceLayoutOrientationVertical;
    sourceInfo.alignment = NSLayoutAttributeLeading;
    sourceInfo.spacing = 3;

    self.itemsStack = [[SDFlippedStackView alloc] init];
    self.itemsStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.itemsStack.alignment = NSLayoutAttributeLeading;
    self.itemsStack.spacing = 10;
    self.itemsStack.translatesAutoresizingMaskIntoConstraints = NO;

    NSView *documentView = [[SDFlippedView alloc] init];
    documentView.translatesAutoresizingMaskIntoConstraints = NO;
    [documentView addSubview:self.itemsStack];
    [NSLayoutConstraint activateConstraints:@[
        [self.itemsStack.leadingAnchor constraintEqualToAnchor:documentView.leadingAnchor constant:2],
        [self.itemsStack.trailingAnchor constraintEqualToAnchor:documentView.trailingAnchor constant:-2],
        [self.itemsStack.topAnchor constraintEqualToAnchor:documentView.topAnchor constant:2],
        [self.itemsStack.bottomAnchor constraintEqualToAnchor:documentView.bottomAnchor constant:-12]
    ]];

    NSScrollView *scroll = [[NSScrollView alloc] init];
    scroll.drawsBackground = NO;
    scroll.hasVerticalScroller = YES;
    scroll.autohidesScrollers = YES;
    scroll.documentView = documentView;
    self.itemsScroll = scroll;
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [documentView.widthAnchor constraintEqualToAnchor:scroll.contentView.widthAnchor].active = YES;

    NSStackView *layout = [NSStackView stackViewWithViews:@[header, switcher, sourceInfo, scroll]];
    layout.orientation = NSUserInterfaceLayoutOrientationVertical;
    layout.alignment = NSLayoutAttributeLeading;
    layout.spacing = 16;
    layout.distribution = NSStackViewDistributionFill;
    layout.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:layout];
    [NSLayoutConstraint activateConstraints:@[
        [layout.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:22],
        [layout.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-22],
        [layout.topAnchor constraintEqualToAnchor:root.topAnchor constant:22],
        [layout.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-18],
        [header.widthAnchor constraintEqualToAnchor:layout.widthAnchor],
        [switcher.widthAnchor constraintEqualToAnchor:layout.widthAnchor],
        [sourceInfo.widthAnchor constraintEqualToAnchor:layout.widthAnchor],
        [scroll.widthAnchor constraintEqualToAnchor:layout.widthAnchor]
    ]];
    [scroll setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationVertical];
}

- (NSTextField *)label:(NSString *)text size:(CGFloat)size weight:(NSFontWeight)weight color:(NSColor *)color {
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = [NSFont systemFontOfSize:size weight:weight];
    label.textColor = color;
    label.selectable = YES;
    return label;
}

- (void)buildStatusItem {
    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSSquareStatusItemLength];
    self.statusItem.button.image = [NSImage imageWithSystemSymbolName:@"checklist" accessibilityDescription:@"StudyDesk"];
    self.statusItem.button.toolTip = @"StudyDesk — click for controls";

    NSMenu *menu = [[NSMenu alloc] init];
    [menu addItemWithTitle:@"Show / Hide StudyDesk" action:@selector(togglePanel:) keyEquivalent:@"s"].target = self;
    [menu addItemWithTitle:@"Refresh Now" action:@selector(refreshClicked:) keyEquivalent:@"r"].target = self;
    [menu addItemWithTitle:@"Open Source Files" action:@selector(openSources:) keyEquivalent:@"o"].target = self;
    [menu addItem:NSMenuItem.separatorItem];
    self.launchAtLoginItem = [[NSMenuItem alloc] initWithTitle:@"Launch at Login" action:@selector(toggleLaunchAtLogin:) keyEquivalent:@""];
    self.launchAtLoginItem.target = self;
    self.launchAtLoginItem.state = [self launchAtLoginEnabled] ? NSControlStateValueOn : NSControlStateValueOff;
    [menu addItem:self.launchAtLoginItem];
    [menu addItem:NSMenuItem.separatorItem];
    [menu addItemWithTitle:@"Quit StudyDesk" action:@selector(quit:) keyEquivalent:@"q"].target = self;
    self.statusItem.menu = menu;
}

- (NSURL *)desktopURL {
    return [NSFileManager.defaultManager.homeDirectoryForCurrentUser URLByAppendingPathComponent:@"Desktop" isDirectory:YES];
}

- (NSURL *)resolvePathForSource:(NSString *)source {
    NSArray<NSURL *> *files = [NSFileManager.defaultManager contentsOfDirectoryAtURL:self.desktopURL includingPropertiesForKeys:@[NSURLContentModificationDateKey] options:NSDirectoryEnumerationSkipsHiddenFiles error:nil];
    NSMutableArray<NSURL *> *matches = [NSMutableArray array];
    for (NSURL *url in files) {
        NSString *name = url.lastPathComponent.lowercaseString;
        if (![@[@"md", @"markdown"] containsObject:url.pathExtension.lowercaseString]) continue;
        if ([source isEqualToString:@"study_group"]) {
            if ([name isEqualToString:@"studydesk-study-group.md"]) [matches addObject:url];
        } else {
            if ([name isEqualToString:@"studydesk-email.md"]) [matches addObject:url];
        }
    }
    return [matches sortedArrayUsingComparator:^NSComparisonResult(NSURL *left, NSURL *right) {
        NSDate *leftDate = nil, *rightDate = nil;
        [left getResourceValue:&leftDate forKey:NSURLContentModificationDateKey error:nil];
        [right getResourceValue:&rightDate forKey:NSURLContentModificationDateKey error:nil];
        return [rightDate ?: NSDate.distantPast compare:leftDate ?: NSDate.distantPast];
    }].firstObject;
}

- (NSString *)fingerprintForURL:(NSURL *)url {
    NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:url.path error:nil];
    return [NSString stringWithFormat:@"%@|%@|%@", url.path, attributes[NSFileModificationDate] ?: @0, attributes[NSFileSize] ?: @0];
}

- (void)timerFired:(NSTimer *)timer {
    if (!self.editorOpen) [self refresh:NO];
}
- (void)refreshClicked:(id)sender { [self refresh:YES]; }

- (void)refresh:(BOOL)force {
    if (self.editorOpen) return;
    BOOL changed = force;
    for (NSString *source in @[@"study_group", @"email"]) {
        NSURL *url = [self resolvePathForSource:source];
        if (!url) {
            self.errors[source] = @"Source file not found on the Desktop.";
            continue;
        }
        NSString *fingerprint = [self fingerprintForURL:url];
        if (!force && [self.fingerprints[source] isEqualToString:fingerprint]) continue;
        NSError *error = nil;
        NSDictionary *document = [SDMarkdownParser documentAtURL:url fallbackSource:source error:&error];
        if (document) {
            self.documents[source] = document;
            self.fingerprints[source] = fingerprint;
            [self.errors removeObjectForKey:source];
            changed = YES;
        } else {
            self.errors[source] = error.localizedDescription ?: @"Unable to read the source file.";
            changed = YES;
        }
    }
    if (changed) [self renderSelectedSource];
}

- (NSString *)selectedSource { return self.selectedSourceName ?: @"week"; }

- (void)updateSourceButtonStyles {
    NSColor *terracotta = [NSColor colorWithSRGBRed:0.776 green:0.416 blue:0.271 alpha:1.0];
    NSColor *ink = [NSColor colorWithSRGBRed:0.184 green:0.169 blue:0.153 alpha:1.0];
    for (NSButton *button in @[self.weekButton, self.studyButton, self.emailButton]) {
        BOOL selected = (button.tag == 0 && [self.selectedSourceName isEqualToString:@"week"]) ||
                        (button.tag == 1 && [self.selectedSourceName isEqualToString:@"study_group"]) ||
                        (button.tag == 2 && [self.selectedSourceName isEqualToString:@"email"]);
        button.layer.backgroundColor = selected ? terracotta.CGColor : NSColor.clearColor.CGColor;
        NSColor *textColor = selected ? NSColor.whiteColor : ink;
        button.attributedTitle = [[NSAttributedString alloc] initWithString:button.title attributes:@{
            NSForegroundColorAttributeName: textColor,
            NSFontAttributeName: [NSFont systemFontOfSize:12 weight:NSFontWeightMedium]
        }];
    }
}

- (void)sourceChanged:(NSButton *)sender {
    self.selectedSourceName = sender.tag == 0 ? @"week" : (sender.tag == 1 ? @"study_group" : @"email");
    [self updateSourceButtonStyles];
    [self renderSelectedSource];
}

- (NSColor *)colorForPriority:(NSString *)priority {
    if ([priority.uppercaseString isEqualToString:@"P0"]) return [NSColor colorWithSRGBRed:0.824 green:0.365 blue:0.200 alpha:1.0];
    if ([priority.uppercaseString isEqualToString:@"P1"]) return [NSColor colorWithSRGBRed:0.776 green:0.416 blue:0.271 alpha:0.82];
    if ([priority.uppercaseString isEqualToString:@"P2"]) return [NSColor colorWithSRGBRed:0.529 green:0.471 blue:0.400 alpha:0.72];
    return [NSColor colorWithSRGBRed:0.529 green:0.471 blue:0.400 alpha:0.45];
}

- (NSDate *)dateFromValue:(NSString *)value {
    if (!value.length) return nil;
    for (NSString *format in @[@"yyyy-MM-dd HH:mm", @"yyyy-MM-dd"]) {
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.timeZone = [NSTimeZone timeZoneWithName:@"Europe/Paris"];
        formatter.dateFormat = format;
        NSDate *date = [formatter dateFromString:value];
        if (date) return date;
    }
    return nil;
}

- (NSArray<NSDictionary *> *)itemsForSource:(NSString *)source {
    NSDictionary *document = self.documents[source];
    NSMutableArray *items = [NSMutableArray array];
    for (NSDictionary *raw in document[@"items"] ?: @[]) {
        NSMutableDictionary *item = [raw mutableCopy];
        item[@"_source"] = source;
        [items addObject:item];
    }
    return items;
}

- (NSArray<NSDictionary *> *)applyManualOrder:(NSArray<NSDictionary *> *)items {
    NSArray<NSString *> *order = [NSUserDefaults.standardUserDefaults arrayForKey:@"StudyDeskManualOrder"] ?: @[];
    if (!order.count) return items;
    NSMutableDictionary<NSString *, NSNumber *> *positions = [NSMutableDictionary dictionary];
    [order enumerateObjectsUsingBlock:^(NSString *identifier, NSUInteger index, BOOL *stop) { positions[identifier] = @(index); }];
    return [items sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
        NSNumber *leftPosition = positions[left[@"id"]];
        NSNumber *rightPosition = positions[right[@"id"]];
        if (leftPosition && rightPosition) return [leftPosition compare:rightPosition];
        if (leftPosition) return NSOrderedAscending;
        if (rightPosition) return NSOrderedDescending;
        return NSOrderedSame;
    }];
}

- (NSArray<NSDictionary *> *)thisWeekItems {
    NSMutableArray *combined = [NSMutableArray array];
    [combined addObjectsFromArray:[self itemsForSource:@"study_group"]];
    [combined addObjectsFromArray:[self itemsForSource:@"email"]];

    NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    calendar.timeZone = [NSTimeZone timeZoneWithName:@"Europe/Paris"];
    calendar.firstWeekday = 2;
    NSDate *weekStart = nil;
    NSTimeInterval weekLength = 0;
    [calendar rangeOfUnit:NSCalendarUnitWeekOfYear startDate:&weekStart interval:&weekLength forDate:NSDate.date];
    NSDate *today = [calendar startOfDayForDate:NSDate.date];
    NSDate *weekEnd = [weekStart dateByAddingTimeInterval:weekLength];

    NSMutableArray *filtered = [NSMutableArray array];
    for (NSDictionary *item in combined) {
        NSDate *deadline = [self dateFromValue:item[@"deadline"]];
        if (deadline && [deadline compare:today] != NSOrderedAscending && [deadline compare:weekEnd] == NSOrderedAscending) {
            [filtered addObject:item];
        }
    }
    [filtered sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
        return [[self dateFromValue:left[@"deadline"]] compare:[self dateFromValue:right[@"deadline"]]];
    }];
    return [self applyManualOrder:filtered];
}

- (void)renderSelectedSource {
    for (NSView *view in self.itemsStack.arrangedSubviews.copy) {
        [self.itemsStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }

    NSString *source = self.selectedSource;
    NSArray<NSDictionary *> *items = nil;
    self.sourceTitleLabel.stringValue = [source isEqualToString:@"week"] ? @"THIS WEEK" : @"UPCOMING";
    if ([source isEqualToString:@"week"]) {
        items = [self thisWeekItems];
        self.sourceMetaLabel.stringValue = [NSString stringWithFormat:@"%lu upcoming deadline%@ before Monday", (unsigned long)items.count, items.count == 1 ? @"" : @"s"];
    } else {
        NSString *error = self.errors[source];
        NSDictionary *document = self.documents[source];
        if (error) {
            self.sourceTitleLabel.stringValue = @"Unable to read this source";
            self.sourceMetaLabel.stringValue = error;
            return;
        }
        if (!document) return;
        NSURL *path = document[@"path"];
        NSString *updatedAt = document[@"updatedAt"] ?: @"";
        self.sourceMetaLabel.stringValue = updatedAt.length ? [NSString stringWithFormat:@"%@  •  %@", path.lastPathComponent, updatedAt] : path.lastPathComponent;
        items = [self applyManualOrder:[self itemsForSource:source]];
    }
    self.renderedItems = items;

    self.actionCountLabel.stringValue = @"●  Updated just now";

    if (!items.count) {
        NSTextField *empty = [self label:@"No remaining deadlines this week." size:13 weight:NSFontWeightRegular color:[NSColor colorWithSRGBRed:0.490 green:0.459 blue:0.427 alpha:1.0]];
        [self.itemsStack addArrangedSubview:empty];
    }
    for (NSDictionary *item in items) {
        NSView *card = [self cardForItem:item];
        [self.itemsStack addArrangedSubview:card];
        [card.widthAnchor constraintEqualToAnchor:self.itemsStack.widthAnchor].active = YES;
    }
    [self.itemsStack layoutSubtreeIfNeeded];
    [self.itemsScroll.contentView scrollToPoint:NSMakePoint(0, 0)];
    [self.itemsScroll reflectScrolledClipView:self.itemsScroll.contentView];
}

- (NSView *)cardForItem:(NSDictionary *)item {
    NSColor *accent = [self colorForPriority:item[@"priority"] ?: @"P3"];
    NSBox *box = [[NSBox alloc] init];
    box.boxType = NSBoxCustom;
    box.borderWidth = 1;
    box.borderColor = [NSColor colorWithSRGBRed:0.855 green:0.816 blue:0.765 alpha:0.72];
    box.fillColor = [NSColor colorWithSRGBRed:0.933 green:0.910 blue:0.875 alpha:1.0];
    box.cornerRadius = 12;
    box.contentViewMargins = NSMakeSize(16, 14);

    NSColor *ink = [NSColor colorWithSRGBRed:0.184 green:0.169 blue:0.153 alpha:1.0];
    NSColor *muted = [NSColor colorWithSRGBRed:0.490 green:0.459 blue:0.427 alpha:1.0];
    NSTextField *course = [self label:[item[@"course / group"] uppercaseString] ?: @"" size:9.5 weight:NSFontWeightSemibold color:muted];
    course.font = [NSFont monospacedSystemFontOfSize:9.5 weight:NSFontWeightSemibold];
    NSTextField *title = [self label:item[@"item"] ?: @"" size:16 weight:NSFontWeightRegular color:ink];
    NSFontDescriptor *titleSerif = [title.font.fontDescriptor fontDescriptorWithDesign:NSFontDescriptorSystemDesignSerif];
    if (titleSerif) title.font = [NSFont fontWithDescriptor:titleSerif size:16];
    title.maximumNumberOfLines = 2;
    title.lineBreakMode = NSLineBreakByWordWrapping;
    NSStackView *titleStack = [NSStackView stackViewWithViews:@[course, title]];
    titleStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    titleStack.alignment = NSLayoutAttributeLeading;
    titleStack.spacing = 3;

    NSTextField *priority = [self label:@"●" size:11 weight:NSFontWeightRegular color:accent];
    priority.toolTip = item[@"priority"] ?: @"";
    NSStackView *top = [NSStackView stackViewWithViews:@[priority, titleStack]];
    top.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    top.alignment = NSLayoutAttributeTop;
    top.spacing = 10;
    [titleStack setHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSString *date = [item[@"deadline"] length] ? [NSString stringWithFormat:@"Due %@", item[@"deadline"]] : ([item[@"start"] length] ? item[@"start"] : @"No fixed date");
    NSTextField *dateLabel = [self label:date size:11.5 weight:NSFontWeightMedium color:muted];

    NSString *bodyText = [item[@"next action"] length] ? item[@"next action"] : item[@"details"];
    NSTextField *body = [self label:bodyText ?: @"" size:12.5 weight:NSFontWeightRegular color:[NSColor colorWithSRGBRed:0.310 green:0.286 blue:0.263 alpha:1.0]];
    body.maximumNumberOfLines = 0;
    body.lineBreakMode = NSLineBreakByWordWrapping;

    NSString *statusText = [item[@"status"] stringByReplacingOccurrencesOfString:@"_" withString:@" "] ?: @"";
    NSTextField *footer = [self label:[NSString stringWithFormat:@"%@  ·  Updated %@", statusText.capitalizedString, item[@"last updated"] ?: @""] size:9.5 weight:NSFontWeightRegular color:[NSColor colorWithSRGBRed:0.565 green:0.529 blue:0.490 alpha:1.0]];
    footer.lineBreakMode = NSLineBreakByTruncatingTail;

    NSButton *edit = [NSButton buttonWithTitle:@"Edit" target:self action:@selector(editItem:)];
    edit.bezelStyle = NSBezelStyleInline;
    edit.font = [NSFont systemFontOfSize:10.5 weight:NSFontWeightSemibold];
    edit.contentTintColor = [NSColor colorWithSRGBRed:0.776 green:0.416 blue:0.271 alpha:1.0];
    edit.identifier = [NSString stringWithFormat:@"%@\t%@", item[@"_source"] ?: @"", item[@"id"] ?: @""];
    NSButton *moveUp = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"chevron.up" accessibilityDescription:@"Move up"] target:self action:@selector(moveItem:)];
    moveUp.tag = -1;
    moveUp.identifier = item[@"id"];
    moveUp.bordered = NO;
    moveUp.toolTip = @"Move up";
    moveUp.contentTintColor = muted;
    NSButton *moveDown = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"chevron.down" accessibilityDescription:@"Move down"] target:self action:@selector(moveItem:)];
    moveDown.tag = 1;
    moveDown.identifier = item[@"id"];
    moveDown.bordered = NO;
    moveDown.toolTip = @"Move down";
    moveDown.contentTintColor = muted;
    NSStackView *controls = [NSStackView stackViewWithViews:@[edit, moveUp, moveDown]];
    controls.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    controls.spacing = 7;

    NSMutableArray *views = [NSMutableArray arrayWithObjects:top, dateLabel, nil];
    if (bodyText.length) [views addObject:body];
    [views addObject:footer];
    if ([item[@"_openLink"] length]) {
        NSButton *link = [NSButton buttonWithTitle:@"Open link ↗" target:self action:@selector(openItemLink:)];
        link.bezelStyle = NSBezelStyleInline;
        link.font = [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold];
        link.contentTintColor = [NSColor colorWithSRGBRed:0.776 green:0.416 blue:0.271 alpha:1.0];
        link.identifier = item[@"_openLink"];
        [views addObject:link];
    }
    [views addObject:controls];

    NSStackView *stack = [NSStackView stackViewWithViews:views];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 8;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [box.contentView addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:box.contentView.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:box.contentView.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:box.contentView.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:box.contentView.bottomAnchor]
    ]];
    return box;
}

- (void)moveItem:(NSButton *)sender {
    NSMutableArray<NSDictionary *> *items = [self.renderedItems mutableCopy];
    NSUInteger index = [items indexOfObjectPassingTest:^BOOL(NSDictionary *item, NSUInteger idx, BOOL *stop) {
        return [item[@"id"] isEqualToString:sender.identifier];
    }];
    if (index == NSNotFound) return;
    NSInteger destination = (NSInteger)index + sender.tag;
    if (destination < 0 || destination >= (NSInteger)items.count) return;
    [items exchangeObjectAtIndex:index withObjectAtIndex:(NSUInteger)destination];

    NSMutableArray<NSString *> *visibleIDs = [NSMutableArray array];
    for (NSDictionary *item in items) if ([item[@"id"] length]) [visibleIDs addObject:item[@"id"]];
    NSMutableArray<NSString *> *order = [[NSUserDefaults.standardUserDefaults arrayForKey:@"StudyDeskManualOrder"] mutableCopy] ?: [NSMutableArray array];
    [order removeObjectsInArray:visibleIDs];
    NSIndexSet *indexes = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, visibleIDs.count)];
    [order insertObjects:visibleIDs atIndexes:indexes];
    [NSUserDefaults.standardUserDefaults setObject:order forKey:@"StudyDeskManualOrder"];
    [self renderSelectedSource];
}

- (NSTextField *)editorField:(NSString *)value {
    NSTextField *field = [NSTextField textFieldWithString:value ?: @""];
    field.font = [NSFont systemFontOfSize:12];
    [field.widthAnchor constraintEqualToConstant:390].active = YES;
    return field;
}

- (NSDictionary *)rawItemWithID:(NSString *)identifier source:(NSString *)source {
    for (NSDictionary *item in self.documents[source][@"items"] ?: @[]) {
        if ([item[@"id"] isEqualToString:identifier]) return item;
    }
    return nil;
}

- (NSString *)escapedCell:(NSString *)value {
    NSString *result = value ?: @"";
    result = [result stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
    result = [result stringByReplacingOccurrencesOfString:@"|" withString:@"\\|"];
    result = [result stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    return [result stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

- (BOOL)writeItem:(NSDictionary *)item source:(NSString *)source error:(NSError **)error {
    NSDictionary *document = self.documents[source];
    NSURL *url = document[@"path"];
    if (!url) return NO;
    NSString *original = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:error];
    if (!original) return NO;

    NSURL *backupDirectory = [[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject URLByAppendingPathComponent:@"StudyDesk/Backups" isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:backupDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    NSDateFormatter *stamp = [[NSDateFormatter alloc] init];
    stamp.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    stamp.dateFormat = @"yyyyMMdd-HHmmss";
    NSURL *backup = [backupDirectory URLByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@.md", url.lastPathComponent.stringByDeletingPathExtension, [stamp stringFromDate:NSDate.date]]];
    [NSFileManager.defaultManager copyItemAtURL:url toURL:backup error:nil];

    NSArray *keys = @[@"id", @"priority", @"type", @"course / group", @"item", @"start", @"deadline", @"status", @"details", @"next action", @"link", @"last updated"];
    NSMutableArray *cells = [NSMutableArray array];
    for (NSString *key in keys) {
        NSString *value = [self escapedCell:item[key]];
        [cells addObject:value];
    }
    NSString *replacement = [NSString stringWithFormat:@"| %@ |", [cells componentsJoinedByString:@" | "]];
    NSMutableArray<NSString *> *lines = [[original componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet] mutableCopy];
    NSString *prefix = [NSString stringWithFormat:@"| %@ |", item[@"id"]];
    BOOL replaced = NO;
    NSDateFormatter *updated = [[NSDateFormatter alloc] init];
    updated.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    updated.timeZone = [NSTimeZone timeZoneWithName:@"Europe/Paris"];
    updated.dateFormat = @"yyyy-MM-dd HH:mm";
    NSString *updatedValue = [updated stringFromDate:NSDate.date];
    for (NSUInteger index = 0; index < lines.count; index++) {
        if ([lines[index] hasPrefix:prefix]) { lines[index] = replacement; replaced = YES; }
        if ([lines[index] hasPrefix:@"updated_at:"]) lines[index] = [NSString stringWithFormat:@"updated_at: %@", updatedValue];
    }
    if (!replaced) return NO;
    return [[lines componentsJoinedByString:@"\n"] writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:error];
}

- (void)editItem:(NSButton *)sender {
    NSArray<NSString *> *parts = [sender.identifier componentsSeparatedByString:@"\t"];
    if (parts.count != 2) return;
    NSString *source = [parts[0] copy];
    NSString *identifier = [parts[1] copy];
    // Present after the initiating mouse event has fully completed. Otherwise the
    // mouse-up can land on the alert's default Save button and save immediately.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self presentEditorForSource:source identifier:identifier];
    });
}

- (void)presentEditorForSource:(NSString *)source identifier:(NSString *)identifier {
    NSDictionary *item = [self rawItemWithID:identifier source:source];
    if (!item) return;
    if (self.editorPanel) [self.editorPanel close];

    self.editingSource = source;
    self.editingIdentifier = identifier;
    self.editorTitle = [self editorField:item[@"item"]];
    self.editorCourse = [self editorField:item[@"course / group"]];
    self.editorStart = [self editorField:item[@"start"]];
    self.editorDeadline = [self editorField:item[@"deadline"]];
    self.editorAction = [self editorField:item[@"next action"]];
    self.editorDetails = [self editorField:item[@"details"]];
    self.editorPriority = [[NSPopUpButton alloc] init];
    [self.editorPriority addItemsWithTitles:@[@"P0", @"P1", @"P2", @"P3"]];
    [self.editorPriority selectItemWithTitle:item[@"priority"] ?: @"P3"];
    self.editorStatus = [[NSPopUpButton alloc] init];
    [self.editorStatus addItemsWithTitles:@[@"action_required", @"confirmed", @"tentative", @"registered", @"optional", @"reference", @"completed"]];
    [self.editorStatus selectItemWithTitle:item[@"status"] ?: @"confirmed"];

    NSGridView *grid = [NSGridView gridViewWithViews:@[
        @[[self label:@"Item" size:11 weight:NSFontWeightMedium color:NSColor.secondaryLabelColor], self.editorTitle],
        @[[self label:@"Course / Group" size:11 weight:NSFontWeightMedium color:NSColor.secondaryLabelColor], self.editorCourse],
        @[[self label:@"Start" size:11 weight:NSFontWeightMedium color:NSColor.secondaryLabelColor], self.editorStart],
        @[[self label:@"Deadline" size:11 weight:NSFontWeightMedium color:NSColor.secondaryLabelColor], self.editorDeadline],
        @[[self label:@"Priority" size:11 weight:NSFontWeightMedium color:NSColor.secondaryLabelColor], self.editorPriority],
        @[[self label:@"Status" size:11 weight:NSFontWeightMedium color:NSColor.secondaryLabelColor], self.editorStatus],
        @[[self label:@"Next Action" size:11 weight:NSFontWeightMedium color:NSColor.secondaryLabelColor], self.editorAction],
        @[[self label:@"Details" size:11 weight:NSFontWeightMedium color:NSColor.secondaryLabelColor], self.editorDetails]
    ]];
    grid.rowSpacing = 8;
    grid.columnSpacing = 12;
    grid.xPlacement = NSGridCellPlacementFill;
    grid.yPlacement = NSGridCellPlacementCenter;

    NSTextField *heading = [self label:@"Edit item" size:22 weight:NSFontWeightSemibold color:[NSColor colorWithSRGBRed:0.184 green:0.169 blue:0.153 alpha:1.0]];
    NSTextField *hint = [self label:@"Dates use YYYY-MM-DD or YYYY-MM-DD HH:MM. Saving updates the source Markdown file." size:11 weight:NSFontWeightRegular color:NSColor.secondaryLabelColor];
    NSButton *cancel = [NSButton buttonWithTitle:@"Cancel" target:self action:@selector(cancelEditor:)];
    cancel.bezelStyle = NSBezelStyleRounded;
    NSButton *save = [NSButton buttonWithTitle:@"Save Changes" target:self action:@selector(saveEditor:)];
    save.bezelStyle = NSBezelStyleRounded;
    save.keyEquivalent = @"\r";
    NSStackView *buttons = [NSStackView stackViewWithViews:@[cancel, save]];
    buttons.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    buttons.alignment = NSLayoutAttributeCenterY;
    buttons.spacing = 10;
    NSStackView *content = [NSStackView stackViewWithViews:@[heading, hint, grid, buttons]];
    content.orientation = NSUserInterfaceLayoutOrientationVertical;
    content.alignment = NSLayoutAttributeLeading;
    content.spacing = 14;
    content.edgeInsets = NSEdgeInsetsMake(24, 24, 24, 24);

    self.editorPanel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 590, 500)
                                                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];
    self.editorPanel.title = @"Edit StudyDesk Item";
    self.editorPanel.backgroundColor = [NSColor colorWithSRGBRed:0.961 green:0.941 blue:0.910 alpha:1.0];
    self.editorPanel.level = NSFloatingWindowLevel;
    self.editorPanel.delegate = self;
    self.editorPanel.contentView = content;
    [self.editorPanel center];
    self.editorOpen = YES;
    [self.editorPanel makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    [self.editorTitle becomeFirstResponder];
}

- (void)cancelEditor:(id)sender {
    self.editorOpen = NO;
    [self.editorPanel close];
    self.editorPanel = nil;
}

- (void)saveEditor:(id)sender {
    NSMutableDictionary *item = [[self rawItemWithID:self.editingIdentifier source:self.editingSource] mutableCopy];
    if (!item) return;

    item[@"item"] = self.editorTitle.stringValue;
    item[@"course / group"] = self.editorCourse.stringValue;
    item[@"start"] = self.editorStart.stringValue;
    item[@"deadline"] = self.editorDeadline.stringValue;
    item[@"priority"] = self.editorPriority.titleOfSelectedItem ?: @"P3";
    item[@"status"] = self.editorStatus.titleOfSelectedItem ?: @"confirmed";
    item[@"next action"] = self.editorAction.stringValue;
    item[@"details"] = self.editorDetails.stringValue;
    NSDateFormatter *updated = [[NSDateFormatter alloc] init];
    updated.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    updated.timeZone = [NSTimeZone timeZoneWithName:@"Europe/Paris"];
    updated.dateFormat = @"yyyy-MM-dd HH:mm";
    item[@"last updated"] = [updated stringFromDate:NSDate.date];
    NSError *writeError = nil;
    if (![self writeItem:item source:self.editingSource error:&writeError]) {
        NSAlert *failure = [NSAlert alertWithError:writeError ?: [NSError errorWithDomain:@"StudyDesk" code:8 userInfo:@{NSLocalizedDescriptionKey: @"The item could not be saved."}]];
        [failure runModal];
        return;
    }
    [self cancelEditor:nil];
    [self refresh:YES];
}

- (void)openItemLink:(NSButton *)sender {
    if (sender.identifier.length) [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:sender.identifier]];
}

- (void)togglePanel:(id)sender {
    if (self.panel.visible) [self.panel orderOut:nil];
    else [self showPanelInFront];
}
- (void)openSources:(id)sender { [NSWorkspace.sharedWorkspace openURL:self.desktopURL]; }
- (void)quit:(id)sender { [NSApp terminate:nil]; }
- (BOOL)windowShouldClose:(NSWindow *)sender {
    if (sender == self.panel) {
        [self.panel orderOut:nil];
        return NO;
    }
    if (sender == self.editorPanel) {
        self.editorOpen = NO;
        self.editorPanel = nil;
    }
    return YES;
}

- (NSURL *)launchAgentURL {
    NSURL *directory = [NSFileManager.defaultManager.homeDirectoryForCurrentUser URLByAppendingPathComponent:@"Library/LaunchAgents" isDirectory:YES];
    return [directory URLByAppendingPathComponent:[SDLaunchAgentLabel stringByAppendingString:@".plist"]];
}

- (BOOL)launchAtLoginEnabled {
    if ([NSUserDefaults.standardUserDefaults objectForKey:@"StudyDeskLaunchAtLogin"] == nil) return YES;
    return [NSUserDefaults.standardUserDefaults boolForKey:@"StudyDeskLaunchAtLogin"];
}

- (void)configureLaunchAtLoginIfNeeded {
    if ([self launchAtLoginEnabled]) [self installLaunchAgent];
}

- (void)toggleLaunchAtLogin:(id)sender {
    BOOL enabled = ![self launchAtLoginEnabled];
    [NSUserDefaults.standardUserDefaults setBool:enabled forKey:@"StudyDeskLaunchAtLogin"];
    if (enabled) [self installLaunchAgent]; else [NSFileManager.defaultManager removeItemAtURL:self.launchAgentURL error:nil];
    self.launchAtLoginItem.state = enabled ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)installLaunchAgent {
    if (![[NSBundle.mainBundle.bundleURL pathExtension] isEqualToString:@"app"]) return;
    NSURL *url = self.launchAgentURL;
    [NSFileManager.defaultManager createDirectoryAtURL:url.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    NSDictionary *plist = @{
        @"Label": SDLaunchAgentLabel,
        @"ProgramArguments": @[@"/usr/bin/open", NSBundle.mainBundle.bundleURL.path],
        @"RunAtLoad": @YES,
        @"ProcessType": @"Interactive"
    };
    [plist writeToURL:url atomically:YES];
}
@end

static NSURL *SDResolveValidationFile(NSString *source, NSURL *directory) {
    NSArray<NSURL *> *files = [NSFileManager.defaultManager contentsOfDirectoryAtURL:directory includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles error:nil];
    for (NSURL *url in files) {
        NSString *name = url.lastPathComponent.lowercaseString;
        if ([source isEqualToString:@"study_group"] && [name isEqualToString:@"studydesk-study-group.md"]) return url;
        if ([source isEqualToString:@"email"] && [name isEqualToString:@"studydesk-email.md"]) return url;
    }
    return nil;
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        if (argc > 1 && strcmp(argv[1], "--validate") == 0) {
            int failures = 0;
            NSURL *directory = argc > 2
                ? [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[2]] isDirectory:YES]
                : [NSFileManager.defaultManager.homeDirectoryForCurrentUser URLByAppendingPathComponent:@"Desktop" isDirectory:YES];
            for (NSString *source in @[@"study_group", @"email"]) {
                NSURL *url = SDResolveValidationFile(source, directory);
                NSError *error = nil;
                NSDictionary *document = url ? [SDMarkdownParser documentAtURL:url fallbackSource:source error:&error] : nil;
                if (document) {
                    printf("%s: %lu items\n", source.UTF8String, (unsigned long)[document[@"items"] count]);
                } else {
                    fprintf(stderr, "%s: %s\n", source.UTF8String, (error.localizedDescription ?: @"file not found").UTF8String);
                    failures++;
                }
            }
            return failures;
        }

        NSApplication *application = NSApplication.sharedApplication;
        SDAppDelegate *delegate = [[SDAppDelegate alloc] init];
        application.delegate = delegate;
        @try {
            [application run];
        } @catch (NSException *exception) {
            fprintf(stderr, "StudyDesk exception: %s — %s\n", exception.name.UTF8String, exception.reason.UTF8String);
            return 2;
        }
    }
    return 0;
}
