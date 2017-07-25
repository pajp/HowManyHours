//
//  main.m
//  HowManyHoursCLI
//
//  Created by Rasmus Sten on 18-07-2017.
//  Copyright © 2017 Rasmus Sten. All rights reserved.
//

#import <Foundation/Foundation.h>
#include <libical/ical.h>


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
    printf("\033[1K\r");
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
    void (^summarizer)(BOOL) = ^void(BOOL weekSummary) {
        NSDateFormatter* formatter = [[NSDateFormatter alloc] init];
        formatter.dateStyle = NSDateFormatterFullStyle;
        formatter.timeStyle = NSDateFormatterNoStyle;
        double hours = timeThisDay/60.0/60.0;
        if (exitsThisDay == 1) { // Did not leave office for lunch, deducting 0.5 hours
            hours -= .5;
        }
        totalHours += hours;
        weekTotal += hours;
        dayCount++;
        dayCountThisWeek++;
        if (pyjama) {
            printf("\033[34;1m");
        }
        pyjama = !pyjama;
        NSString* formattedString = [formatter stringFromDate:lastDate];
        NSMutableString* padding = [NSMutableString new];
        for (int i=0; i < 25 - formattedString.length; i++) [padding appendString:@" "];

        printf("%s%s --> %.2f hours\033[0m\n", padding.UTF8String, formattedString.UTF8String, hours);

        if (weekSummary) {
            printf("\033[37;36m**** WEEK TOTAL: \033[1m%d\033[0;37;36m days, %.2f hours, %.2f hours per day\033[0m\n", dayCountThisWeek, weekTotal, weekTotal/dayCountThisWeek);
            weekTotal = 0;
            dayCountThisWeek = 0;
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
                summarizer(weekChange);
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
//            NSLog(@"Left work after %f hours at %@", duration/60/60, eventTime);
        } else {
            NSLog(@"****** Unknown event summary %@", eventTitle);
        }
        lastDate = eventTime;
    }];
    summarizer(YES);
    printf("**** Total %d days, %.2f hours, %.2f hours per day\n", dayCount, totalHours, totalHours / dayCount);
    exit(0);
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
        NSURLSessionDataTask* task = [session dataTaskWithURL:url completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
            if (!error) {
                doTheThing([NSString stringWithUTF8String:data.bytes]);
            } else {
                NSLog(@"%@", error);
            }
        }];
        printf("Downloading…");
        fflush(stdout);
        [task resume];
        NSRunLoop* rl = [NSRunLoop mainRunLoop];
        [rl run];
    }
    return 0;
}
