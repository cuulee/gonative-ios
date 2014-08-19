//
//  LEANAppConfig.m
//  LeanIOS
//
//  Created by Weiyin He on 2/10/14.
// Copyright (c) 2014 GoNative.io LLC. All rights reserved.
//

#import "LEANAppConfig.h"
#import "LEANUtilities.h"
#import <CommonCrypto/CommonCrypto.h>

@interface LEANAppConfig ()
@property id json;
@end

@implementation LEANAppConfig

+ (LEANAppConfig *)sharedAppConfig
{
    static LEANAppConfig *sharedAppConfig;
    
    @synchronized(self)
    {
        if (!sharedAppConfig){
            sharedAppConfig = [[LEANAppConfig alloc] init];
            
            // read json
            NSURL *otaJson = [LEANAppConfig urlForOtaConfig];
            NSURL *packageJson = [[NSBundle mainBundle] URLForResource:@"appConfig" withExtension:@"json"];
            
            for (NSURL *url in @[otaJson, packageJson]) {
                if (![[NSFileManager defaultManager] fileExistsAtPath:[url path] isDirectory:NO]) {
                    continue;
                }
                
                NSError *jsonError;
                NSInputStream *inputStream = [NSInputStream inputStreamWithURL:url];
                [inputStream open];
                sharedAppConfig.json = [NSJSONSerialization JSONObjectWithStream:inputStream options:0 error:&jsonError];
                [inputStream close];
                if (!jsonError) {
                    // success!
                    break;
                } else {
                    NSLog(@"Error parsing json: %@", jsonError);
                }
            }
            
            ////////////////////////////////////////////////////////////
            // General
            ////////////////////////////////////////////////////////////
            NSDictionary *general = sharedAppConfig.json[@"general"];
            
            sharedAppConfig.userAgentAdd = general[@"userAgentAdd"];
            sharedAppConfig.forceUserAgent = general[@"forceUserAgent"];
            sharedAppConfig.initialURL = [NSURL URLWithString:general[@"initialUrl"]];
            sharedAppConfig.initialHost = [sharedAppConfig.initialURL host];
            sharedAppConfig.appName = general[@"appName"];
            sharedAppConfig.publicKey = general[@"publicKey"];
            sharedAppConfig.deviceRegKey = general[@"deviceRegKey"];
            
            if ([sharedAppConfig.initialHost hasPrefix:@"www."]) {
                sharedAppConfig.initialHost = [sharedAppConfig.initialHost stringByReplacingCharactersInRange:NSMakeRange(0, [@"www." length]) withString:@""];
            }
            
            
            ////////////////////////////////////////////////////////////
            // Forms
            ////////////////////////////////////////////////////////////
            NSDictionary *forms = sharedAppConfig.json[@"forms"];
            
            // search
            NSDictionary *search = forms[@"search"];
            if (search && [search[@"active"] boolValue]) {
                sharedAppConfig.searchTemplateURL = search[@"searchTemplateURL"];
            }
            
            // login
            NSDictionary *loginConfig = forms[@"loginConfig"];
            if (loginConfig && [loginConfig[@"active"] boolValue]) {
                sharedAppConfig.loginConfig = loginConfig;
                sharedAppConfig.loginURL = [NSURL URLWithString:loginConfig[@"interceptUrl"]];
                sharedAppConfig.loginIsFirstPage = [loginConfig[@"loginIsFirstPage"] boolValue];
            }
            
            sharedAppConfig.loginLaunchBackground = [forms[@"loginLaunchBackground"] boolValue];
            if ([forms[@"loginIconImage"] isKindOfClass:[NSNumber class]]) {
                sharedAppConfig.loginIconImage = [forms[@"loginIconImage"] boolValue];
            } else sharedAppConfig.loginIconImage = YES;
            
            // signup
            NSDictionary *signupConfig = forms[@"signupConfig"];
            if (signupConfig && [signupConfig[@"active"] boolValue]) {
                sharedAppConfig.signupConfig = signupConfig;
                sharedAppConfig.signupURL = [NSURL URLWithString:signupConfig[@"interceptUrl"]];
            }
            
            // other forms to be intercepted
            NSDictionary *interceptForms = forms[@"interceptForms"];
            if (interceptForms && [interceptForms[@"active"] boolValue]) {
                sharedAppConfig.interceptForms = interceptForms[@"forms"];
            }
            
            
            ////////////////////////////////////////////////////////////
            // Navigation
            ////////////////////////////////////////////////////////////
            NSDictionary *navigation = sharedAppConfig.json[@"navigation"];
            NSDictionary *sidebarNav = navigation[@"sidebarNavigation"];
            
            // menus
            id menus = sidebarNav[@"menus"];
            NSUInteger numActiveMenus = 0;
            if ([menus isKindOfClass:[NSArray class]]) {
                sharedAppConfig.menus = [NSMutableDictionary dictionary];
                for (id menu in menus) {
                    // skip if not active
                    if (![menu[@"active"] boolValue]) {
                        continue;
                    }
                    
                    numActiveMenus++;
                    
                    NSString *name = menu[@"name"];
                    if (name && [menu[@"items"] isKindOfClass:[NSArray class]]) {
                        sharedAppConfig.menus[name] = menu[@"items"];
                        
                        // show menu if the menu named "default" is active
                        if ([name isEqualToString:@"default"]) {
                            sharedAppConfig.showNavigationMenu = YES;
                        }
                    }
                }
            }
            
            if ([sidebarNav[@"userIdRegex"] isKindOfClass:[NSString class]]) {
                sharedAppConfig.userIdRegex = sidebarNav[@"userIdRegex"];
            }
            
            // menu selection config
            id menuSelectionConfig = sidebarNav[@"menuSelectionConfig"];
            if ((numActiveMenus > 1 || sharedAppConfig.loginIsFirstPage) && [menuSelectionConfig isKindOfClass:[NSDictionary class]]) {
                id testUrl = menuSelectionConfig[@"testURL"];
                if ([testUrl isKindOfClass:[NSString class]]) {
                    sharedAppConfig.loginDetectionURL = [NSURL URLWithString:testUrl];
                }
                
                id redirectLocations = menuSelectionConfig[@"redirectLocations"];
                if ([redirectLocations isKindOfClass:[NSArray class]]) {
                    sharedAppConfig.loginDetectRegexes = [NSMutableArray array];
                    sharedAppConfig.loginDetectLocations = [NSMutableArray array];
                    for (id entry in redirectLocations) {
                        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", entry[@"regex"]];
                        if (predicate) {
                            [sharedAppConfig.loginDetectRegexes addObject:predicate];
                            [sharedAppConfig.loginDetectLocations addObject:entry];
                        }
                    }
                }
            }
            
            // navigation levels
            if ([navigation[@"navigationLevels"][@"active"] boolValue]) {
                id urlLevels = navigation[@"navigationLevels"][@"levels"];
                sharedAppConfig.navStructureLevels = [[NSMutableArray alloc] initWithCapacity:[urlLevels count]];
                for (id entry in urlLevels) {
                    if ([entry isKindOfClass:[NSDictionary class]] && entry[@"regex"] && entry[@"level"]) {
                        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", entry[@"regex"]];
                        NSNumber *level = entry[@"level"];
                        [sharedAppConfig.navStructureLevels addObject:@{@"predicate": predicate, @"level": level}];
                    }
                }
            }
            
            // navigation titles
            if ([navigation[@"navigationTitles"][@"active"] boolValue]) {
                id titles = navigation[@"navigationTitles"][@"titles"];
                sharedAppConfig.navTitles = [[NSMutableArray alloc] initWithCapacity:[titles count]];
                for (id entry in titles) {
                    if ([entry isKindOfClass:[NSDictionary class]] && entry[@"regex"]) {
                        NSMutableDictionary *toAdd = [[NSMutableDictionary alloc] init];
                        
                        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", entry[@"regex"]];
                        [toAdd setObject:predicate forKey:@"predicate"];
                        
                        if (entry[@"title"]) {
                            [toAdd setObject:entry[@"title"] forKey:@"title"];
                        }
                        if (entry[@"urlRegex"]) {
                            [toAdd setObject:[NSRegularExpression regularExpressionWithPattern:entry[@"urlRegex"] options:0 error:nil] forKey:@"urlRegex"];
                        }
                        if (entry[@"urlChompWords"]) {
                            [toAdd setObject:entry[@"urlChompWords"] forKey:@"urlChompWords"];
                        }
                        
                        [sharedAppConfig.navTitles addObject:toAdd];
                    }
                }
                
            }
            
            if ([navigation[@"redirects"] isKindOfClass:[NSArray class]]) {
                NSUInteger len = [navigation[@"redirects"] count];
                sharedAppConfig.redirects = [[NSMutableDictionary alloc] initWithCapacity:len];
                for (id redirect in navigation[@"redirects"]) {
                    [sharedAppConfig.redirects setValue:redirect[@"to"] forKey:redirect[@"from"]];
                }
            }
            
            if ([navigation[@"profilePickerJS"] isKindOfClass:[NSString class]]) {
                sharedAppConfig.profilePickerJS = navigation[@"profilePickerJS"];
            }
            
            // regex for internal vs external links
            // note that we ignore "active" here.
            if (navigation[@"regexInternalExternal"]) {
                id temp = navigation[@"regexInternalExternal"][@"rules"];
                
                NSUInteger num = [temp count];
                sharedAppConfig.regexInternalEternal = [[NSMutableArray alloc] initWithCapacity:num];
                sharedAppConfig.regexIsInternal = [[NSMutableArray alloc] initWithCapacity:num];
                for (id entry in temp) {
                    if ([entry isKindOfClass:[NSDictionary class]] && entry[@"regex"] && entry[@"internal"]) {
                        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", entry[@"regex"]];
                        NSNumber *internal = entry[@"internal"];
                        if (predicate) {
                            [sharedAppConfig.regexInternalEternal addObject:predicate];
                            [sharedAppConfig.regexIsInternal addObject:internal];
                        }
                    }
                    
                }
            }
            
            // tab menus
            id tabNavigation = navigation[@"tabNavigation"];
            [sharedAppConfig processTabNavigation:tabNavigation];
            
            ////////////////////////////////////////////////////////////
            // Styling
            ////////////////////////////////////////////////////////////
            NSDictionary *styling = sharedAppConfig.json[@"styling"];
            
            if ([styling[@"customCSS"] isKindOfClass:[NSString class]]) {
                sharedAppConfig.customCss = styling[@"customCSS"];
            }
            
            if ([styling[@"forceViewportWidth"] isKindOfClass:[NSNumber class]]) {
                sharedAppConfig.forceViewportWidth = styling[@"forceViewportWidth"];
            }
            
            
            if ([styling[@"showNavigationBar"] isKindOfClass:[NSNumber class]])
                sharedAppConfig.showNavigationBar = [styling[@"showNavigationBar"] boolValue];
            else sharedAppConfig.showNavigationBar = YES;
            sharedAppConfig.tintColor = [LEANUtilities colorFromHexString:styling[@"iosTintColor"]];
            sharedAppConfig.titleTextColor = [LEANUtilities colorFromHexString:styling[@"iosTitleColor"]];
            sharedAppConfig.menuAnimationDuration = styling[@"menuAnimationDuration"];
            sharedAppConfig.interactiveDelay = styling[@"transitionInteractiveDelayMax"];
            
            if ([styling[@"showToolbar"] isKindOfClass:[NSNumber class]])
                sharedAppConfig.showToolbar = [styling[@"showToolbar"] boolValue];
            else sharedAppConfig.showToolbar = NO;
            
            
            
            ////////////////////////////////////////////////////////////
            // Services
            ////////////////////////////////////////////////////////////
            NSDictionary *services = sharedAppConfig.json[@"services"];
            
            NSDictionary *push = services[@"push"];
            sharedAppConfig.pushNotifications = [push[@"active"] boolValue];
            
            NSDictionary *analytics = services[@"analytics"];
            sharedAppConfig.analytics = [analytics[@"active"] boolValue];
            if (sharedAppConfig.analytics) {
                id idsite_test = analytics[@"idsite_test"];
                id idsite_prod = analytics[@"idsite_prod"];

                if ([idsite_test isKindOfClass:[NSNumber class]] &&
                    [idsite_prod isKindOfClass:[NSNumber class]]) {
                    sharedAppConfig.idsite_test = [idsite_test integerValue];
                    sharedAppConfig.idsite_prod = [idsite_prod integerValue];
                } else {
                    NSLog(@"Analytics requires idsite_test and idsite_prod");
                    sharedAppConfig.analytics = NO;
                }
            }
            
            ////////////////////////////////////////////////////////////
            // Performance
            ////////////////////////////////////////////////////////////
            NSDictionary *performance = sharedAppConfig.json[@"performance"];
            
            // webview pool urls
            if ([performance[@"webviewPools"] isKindOfClass:[NSArray class]]) {
                sharedAppConfig.webviewPools = performance[@"webviewPools"];
            }
            
            
            ////////////////////////////////////////////////////////////
            // Miscellaneous stuff
            ////////////////////////////////////////////////////////////
            sharedAppConfig.showShareButton = [sharedAppConfig.json[@"showShareButton"] boolValue];
            sharedAppConfig.enableChromecast = [sharedAppConfig.json[@"enableChromecast"] boolValue];
            
            if (sharedAppConfig.json[@"forceLandscapeRegex"]) {
                sharedAppConfig.forceLandscapeMatch = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", sharedAppConfig.json[@"forceLandscapeRegex"]];
            }
            
            if (sharedAppConfig.json[@"allowZoom"]) {
                sharedAppConfig.allowZoom = [sharedAppConfig.json[@"allowZoom"] boolValue];
            }
            else
                sharedAppConfig.allowZoom = YES;
            
            sharedAppConfig.updateConfigJS = sharedAppConfig.json[@"updateConfigJS"];

        }
        
        
        return sharedAppConfig;
    }
}

+ (NSURL*)urlForOtaConfig
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *library = [fileManager URLsForDirectory:NSLibraryDirectory inDomains:NSUserDomainMask][0];
    return [library URLByAppendingPathComponent:@"appConfig.json"];
}

- (void)processConfigUpdate:(NSString *)json
{
    if (!json || [json length] == 0) {
        return;
    }
    
    NSError *error;
    id parsedJson = [NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:&error];
    if (error) {
        NSLog(@"Error processing config update: %@", error);
        return;
    }
    
    if (![parsedJson isKindOfClass:[NSDictionary class]]) {
        return;
    }
    
    id tabNavigation = parsedJson[@"tabNavigation"];
    if (tabNavigation && [tabNavigation isKindOfClass:[NSDictionary class]]) {
        [self processTabNavigation:tabNavigation];
    }
}

- (void)processTabNavigation:(NSDictionary*)tabNavigation
{
    // tab menus
    id tabMenus = tabNavigation[@"tabMenus"];
    if ([tabMenus isKindOfClass:[NSArray class]]) {
        self.tabMenus = [NSMutableDictionary dictionary];
        for (id menu in tabMenus) {
            NSString *tabMenuId = menu[@"id"];
            if (tabMenuId && [menu[@"items"] isKindOfClass:[NSArray class]]) {
                self.tabMenus[tabMenuId] = menu[@"items"];
            }
        }
    }
    
    id tabSelection = tabNavigation[@"tabSelectionConfig"];
    if (tabSelection && [tabSelection isKindOfClass:[NSArray class]]) {
        self.tabMenuRegexes = [NSMutableArray array];
        self.tabMenuIDs = [NSMutableArray array];
        
        for (id entry in tabSelection) {
            if ([entry isKindOfClass:[NSDictionary class]] &&
                entry[@"regex"] && entry[@"id"]) {
                NSPredicate *predicate = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", entry[@"regex"]];
                NSString *menuId = entry[@"id"];
                
                [self.tabMenuRegexes addObject:predicate];
                [self.tabMenuIDs addObject:menuId];
            }
        }
    }
}

@end
