//
//  main.m
//  HowManyHoursCLI
//
//  Created by Rasmus Sten on 18-07-2017.
//  Copyright © 2017 Rasmus Sten. All rights reserved.
//

#import <Foundation/Foundation.h>
#include <libical/ical.h>

BOOL useAnsi() {
    static dispatch_once_t onceToken;
    static BOOL ansiCapableTerminal;
    dispatch_once(&onceToken, ^{
        // Xcode allocates a tty but does not set $TERM. Good enough.
        ansiCapableTerminal = isatty(fileno(stdin)) && getenv("TERM");
    });
    return ansiCapableTerminal;
}


void doTheThing(NSString* calendarData) {
    icalcomponent* root = icalparser_parse_string([calendarData cStringUsingEncoding:NSUTF8StringEncoding]);
    icalcomponent *c;
    NSMutableArray* events = [NSMutableArray new];
    // Iterate over all iCal events, create dicts with "time" and "summary" keys
    // containing the start time, and summary text, respectively (as they're the
    // only fields we're interested in)
    for(c = icalcomponent_get_first_component(root, ICAL_ANY_COMPONENT);
        c != 0;
        c = icalcomponent_get_next_component(root, ICAL_ANY_COMPONENT))
    {
        const char* summary = icalcomponent_get_summary(c);
        icaltimetype starttime = icalcomponent_get_dtstart(c);
        time_t starttime_timet = icaltime_as_timet(starttime);
        NSDate* starttime_date = [NSDate dateWithTimeIntervalSince1970:starttime_timet];
        // I don't know why, but the time I get from libical appears to be offset by
        // 3 hours (the events in the iCal feed are in EET = GMT+3). Subtracting three
        // hours gives me the correct local time.
        starttime_date = [starttime_date dateByAddingTimeInterval:-(3*60*60)];
        if (summary) {
            NSString* summaryStr = [NSString stringWithUTF8String:summary];
            [events addObject:@{ @"time" : starttime_date,
                                 @"summary" : summaryStr }];
        }
    }
    // Sort the events
    NSArray* sortedEvents = [events sortedArrayUsingComparator:^NSComparisonResult(NSDictionary*  _Nonnull obj1, NSDictionary*  _Nonnull obj2) {
        NSDate* date1 = obj1[@"time"];
        NSDate* date2 = obj2[@"time"];
        return [date1 compare:date2];
    }];

    if (useAnsi()) printf("\033[1K\r");
    else printf("\n");

    NSCalendar* cal = [NSCalendar currentCalendar];
    __block NSDate* lastDate = nil;
    __block NSDate* lastEntered = nil;
    __block NSTimeInterval timeThisDay = 0;
    __block int dayCount = 0;
    __block double totalHours = 0;
    __block double weekTotal = 0;
    __block int dayCountThisWeek = 0;
    __block int exitsThisDay = 0;
    __block BOOL pyjama = NO;
    // Put the summarizer function in a block that we can call both in the
    // iterator and once after the last processed event
    void (^summarizer)(BOOL, BOOL) = ^void(BOOL weekSummary, BOOL totalSummary) {
        NSDateFormatter* formatter = [[NSDateFormatter alloc] init];
        formatter.dateStyle = NSDateFormatterFullStyle;
        formatter.timeStyle = NSDateFormatterNoStyle;
        double hours = timeThisDay/60.0/60.0;
        if (exitsThisDay == 1 && hours > 4) { // Did not leave office for lunch, deducting 0.5 hours
            hours -= .5;
        }
        totalHours += hours;
        weekTotal += hours;
        dayCount++;
        dayCountThisWeek++;
        if (pyjama) {
            if (useAnsi()) printf("\033[34;1m");
        }
        pyjama = !pyjama;
        NSString* formattedString = [formatter stringFromDate:lastDate];
        NSMutableString* padding = [NSMutableString new];
        for (int i=0; i < 25 - formattedString.length; i++) [padding appendString:@" "];

        printf("%s%s --> %.2f hours%s\n", padding.UTF8String, formattedString.UTF8String, hours, useAnsi() ? "\033[0m" : "");

        if (weekSummary) {
            printf("%s**** WEEK TOTAL: %s%d%s days, %.2f hours, %.2f hours per day%s\n", useAnsi() ? "\033[37;36m" : "", useAnsi() ? "\033[1m" : "", dayCountThisWeek, useAnsi() ? "\033[0;37;36m" : "", weekTotal, weekTotal/dayCountThisWeek, useAnsi() ? "\033[0m" : "");
            weekTotal = 0;
            dayCountThisWeek = 0;
        }
        
        BOOL isYesterday = [cal isDateInYesterday:lastDate];
        if (isYesterday || totalSummary) {
            NSUserNotificationCenter* nc = [NSUserNotificationCenter defaultUserNotificationCenter];
            NSUserNotification* notification = [[NSUserNotification alloc] init];
            notification.title = [NSString stringWithFormat:@"Hours for %@", formattedString];
            notification.informativeText = [NSString stringWithFormat:@"%.f hours", hours];
            [nc deliverNotification:notification];
            //sleep(1);
        }
        
    };
    
    [sortedEvents enumerateObjectsUsingBlock:^(NSDictionary*  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        NSDate* eventTime = obj[@"time"];
        BOOL weekChange = NO;
        if (lastDate && [cal compareDate:eventTime toDate:lastDate toUnitGranularity:NSCalendarUnitWeekOfYear] != NSOrderedSame) {
            weekChange = YES;
        }
        if (lastDate && [cal compareDate:eventTime toDate:lastDate toUnitGranularity:NSCalendarUnitDay] != NSOrderedSame) {
            if (timeThisDay) {
                summarizer(weekChange, NO);
                timeThisDay = 0;
                exitsThisDay = 0;
            }
        }
        NSString* eventTitle = obj[@"summary"];
        if ([eventTitle isEqualToString:@"You entered work"]) {

            lastEntered = eventTime;
        } else if ([eventTitle isEqualToString:@"You exited work"]) {
            NSTimeInterval duration = [eventTime timeIntervalSinceDate:lastDate];
            timeThisDay += duration;
            exitsThisDay++;
#if defined(DEBUG) && 0
            NSLog(@"Left work after %d hours, %d minutes at %@", (int) floor(duration/60/60), (int)((duration-floor(duration/60/60))/60), eventTime);
#endif
        } else {
            NSLog(@"****** Unknown event summary %@", eventTitle);
        }
        lastDate = eventTime;
    }];
    summarizer(YES, YES);
    printf("**** Total %d days, %.2f hours, %.2f hours per day\n", dayCount, totalHours, totalHours / dayCount);
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        if (argc < 2) {
            NSLog(@"Supply ics URL, please");
            exit(1);
        }
        NSString* urlString = [NSString stringWithUTF8String:argv[1]];
        urlString = [urlString stringByReplacingOccurrencesOfString:@"webcal:" withString:@"https:"];
        NSURL* url = [NSURL URLWithString:urlString];
        NSURLSession* session = [NSURLSession sharedSession];
        __block BOOL didTheThing = NO;
        NSURLSessionDataTask* task = [session dataTaskWithURL:url completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
            if (!error) {
                doTheThing([NSString stringWithUTF8String:data.bytes]);
                didTheThing = YES;
            } else {
                NSLog(@"%@", error);
            }
        }];
        printf("Downloading…");
        fflush(stdout);
        [task resume];
        NSRunLoop* rl = [NSRunLoop mainRunLoop];
        while (!didTheThing) {
            [rl runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.1]];
        }
    }
    return 0;
}
