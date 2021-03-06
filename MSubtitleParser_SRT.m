//
//  Movist
//
//  Copyright 2006 ~ 2008 Yong-Hoe Kim. All rights reserved.
//      Yong-Hoe Kim  <cocoable@gmail.com>
//
//  This file is part of Movist.
//
//  Movist is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation; either version 3 of the License, or
//  (at your option) any later version.
//
//  Movist is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

#import "MSubtitleParser_SRT.h"

enum {
    TAG_NONE            = -1,
    TAG_UNKNOWN         = 0,
    
    // contents tags
    TAG_FONT_OPEN,      TAG_FONT_CLOSE,
    TAG_I_OPEN,         TAG_I_CLOSE,
    TAG_B_OPEN,         TAG_B_CLOSE,
};

typedef struct _SRTTag {
    int type;          // TAG_*
    NSString* attr;
    NSRange range;
} SRTTag;

////////////////////////////////////////////////////////////////////////////////
#pragma mark -

@interface NSString (MSubtitleParser_SRT)

- (SRTTag)srtTagWithRangePtr:(NSRange*)range delimSet:(NSCharacterSet*)delimSet;

@end

////////////////////////////////////////////////////////////////////////////////
#pragma mark -

@interface NSColor (MSubtitleParser_SMI)

+ (NSColor*)colorFromSMIString:(NSString*)string;

@end

////////////////////////////////////////////////////////////////////////////////
#pragma mark -

@implementation MSubtitleParser_SRT

- (BOOL)isIndexString:(NSString*)s
{
    int i;
    unichar c;
    for (i = 0; i < [s length]; i++) {
        c = [s characterAtIndex:i];
        if (c < '0' || '9' < c) {
            return FALSE;
        }
    }
    return TRUE;
}

- (void)parse_TIMES:(NSString*)s
          beginTime:(float*)beginTime endTime:(float*)endTime
{
    if ([s length] < 29 ||
        [s characterAtIndex:2] != ':' ||
        [s characterAtIndex:5] != ':' ||
        [s characterAtIndex:8] != ',') {
        return;
    }

    //TRACE(@"%s \"%@\"", __PRETTY_FUNCTION__, s);
    NSCharacterSet* set = [NSCharacterSet characterSetWithCharactersInString:@":, "];
    NSRange cr = NSMakeRange(0, [s length]);

    // begin time
    NSRange r = [s tokenRangeForDelimiterSet:set rangePtr:&cr];
    int hour = [[s substringWithRange:r] intValue];
    r = [s tokenRangeForDelimiterSet:set rangePtr:&cr];
    int min = [[s substringWithRange:r] intValue];
    r = [s tokenRangeForDelimiterSet:set rangePtr:&cr];
    int sec = [[s substringWithRange:r] intValue];
    r = [s tokenRangeForDelimiterSet:set rangePtr:&cr];
    int msec = [[s substringWithRange:r] intValue];
    *beginTime = (hour * 60 * 60) + (min * 60) + (sec) + (msec / 1000.0);

    // "-->"
    r = [s tokenRangeForDelimiterSet:set rangePtr:&cr];

    // end time
    r = [s tokenRangeForDelimiterSet:set rangePtr:&cr];
    hour = [[s substringWithRange:r] intValue];
    r = [s tokenRangeForDelimiterSet:set rangePtr:&cr];
    min = [[s substringWithRange:r] intValue];
    r = [s tokenRangeForDelimiterSet:set rangePtr:&cr];
    sec = [[s substringWithRange:r] intValue];
    r = [s tokenRangeForDelimiterSet:set rangePtr:&cr];
    msec = [[s substringWithRange:r] intValue];
    *endTime = (hour * 60 * 60) + (min * 60) + (sec) + (msec / 1000.0);
}

- (NSColor*)parse_FONT:(NSString*)attr
{
    //TRACE(@"%s \"%@\"", __PRETTY_FUNCTION__, attr);
    NSRange ar = NSMakeRange(0, [attr length]);
    NSRange tr = [attr tokenRangeForDelimiterSet:_fontDelimSet rangePtr:&ar];
    if (![attr compare:@"COLOR" options:NSCaseInsensitiveSearch range:tr]) {
        tr = [attr tokenRangeForDelimiterSet:_fontDelimSet rangePtr:&ar];
        return [NSColor colorFromSMIString:[attr substringWithRange:tr]];
    }
    return nil;
}

- (NSMutableAttributedString*)parseSubtitleString:(NSString*)string
{
    //TRACE(@"%s \"%@\")", __PRETTY_FUNCTION__, string);

    // this method can be called independently for parsing embedded subtitle.

    NSMutableString* ms = [NSMutableString stringWithString:string];
    [ms removeRightWhitespaces];

    // apply text-attributes : italic, bold, ...
    NSMutableAttributedString* mas = [[[NSMutableAttributedString alloc]
                                initWithString:@"" attributes:nil] autorelease];
    if (0 < [ms length]) {
        NSCharacterSet* set = [NSCharacterSet whitespaceAndNewlineCharacterSet];
        SRTTag tag;
        NSColor* color = nil;
        BOOL italic = FALSE, bold = FALSE;
        NSRange r, range = NSMakeRange(0, [ms length]);
        while (0 < range.length) {
            r.location = range.location;
            tag = [ms srtTagWithRangePtr:&range delimSet:set];
            if (TAG_UNKNOWN < tag.type) {
                r.length = tag.range.location - r.location;
                if (0 < r.length) {
                    [self mutableAttributedString:mas
                                     appendString:[ms substringWithRange:r]
                                        withColor:color italic:italic bold:bold];
                }
                r.location = NSMaxRange(tag.range);
                switch (tag.type) {
                    case TAG_FONT_OPEN  : color = [self parse_FONT:tag.attr];   break;
                    case TAG_FONT_CLOSE : color = nil;                          break;
                    case TAG_I_OPEN     : italic = TRUE;                        break;
                    case TAG_I_CLOSE    : italic = FALSE;                       break;
                    case TAG_B_OPEN     : bold = TRUE;                          break;
                    case TAG_B_CLOSE    : bold = FALSE;                         break;
                }
            }
        }
        r.length = [ms length] - r.location;
        if (0 < r.length) {
            [self mutableAttributedString:mas
                             appendString:[ms substringWithRange:r]
                                withColor:color italic:italic bold:bold];
        }
        [mas fixAttributesInRange:NSMakeRange(0, [mas length])];
    }
    return mas;
}

- (void)parseSubtitleString:(NSString*)string
                  beginTime:(float)beginTime endTime:(float)endTime
{
    MSubtitle* subtitle = [_subtitles objectAtIndex:0];
    [subtitle addString:[self parseSubtitleString:string]
              beginTime:beginTime endTime:endTime];
}

- (void)readyWithOptions:(NSDictionary*)options
{
    //TRACE(@"%s", __PRETTY_FUNCTION__);
    NSMutableCharacterSet* mset;
    mset = [[NSCharacterSet whitespaceAndNewlineCharacterSet] mutableCopy];
    [mset addCharactersInString:@"{}:;='\""];
    _fontDelimSet = [mset autorelease];
}

- (NSArray*)parseString:(NSString*)string options:(NSDictionary*)options
                  error:(NSError**)error
{
    //TRACE(@"%s", __PRETTY_FUNCTION__);
    _source = [[string retain] autorelease];
    _sourceRange = NSMakeRange(0, [_source length]);
    _subtitles = [NSMutableArray arrayWithCapacity:1];
    [self readyWithOptions:options];

    MSubtitle* subtitle = [[[MSubtitle alloc] initWithURL:_subtitleURL] autorelease];
    [subtitle setType:@"SRT"];
    [subtitle setTrackName:NSLocalizedString(@"External Subtitle", nil)];
    [subtitle setEmbedded:FALSE];
    [_subtitles addObject:subtitle];

    NSCharacterSet* set = [NSCharacterSet characterSetWithCharactersInString:@"\r\n"];

    NSRange r;
    NSString* s;
    NSMutableString* ms = nil;
    float beginTime = -1, endTime;
    while (0 < _sourceRange.length) {
        r = [_source tokenRangeForDelimiterSet:set rangePtr:&_sourceRange];
        if (r.length != 0) {
            s = [_source substringWithRange:r];
            // ignore index...
            if (beginTime < 0) {
                [self parse_TIMES:s beginTime:&beginTime endTime:&endTime];
            }
            else {
                if (![self isIndexString:s]) {
                    if (!ms) {
                        ms = [NSMutableString stringWithString:s];
                    }
                    else {
                        [ms appendString:@"\n"];
                        [ms appendString:s];
                    }
                }
                else {
                    if (ms) {
                        [self parseSubtitleString:ms beginTime:beginTime endTime:endTime];
                        ms = nil;
                    }
                    beginTime = -1;
                }
            }
        }
    }
    if (0 <= beginTime && ms) {
        [self parseSubtitleString:ms beginTime:beginTime endTime:endTime];
    }

    // remove empty subtitle if exist and
    // make complete not-ended-string if exist.
    int i;
    for (i = [_subtitles count] - 1; 0 <= i; i--) {
        subtitle = [_subtitles objectAtIndex:i];
        if ([subtitle isEmpty]) {
            [_subtitles removeObjectAtIndex:i];
        }
        else {
            [subtitle checkEndTimes];
        }
    }

    return _subtitles;
}

@end

////////////////////////////////////////////////////////////////////////////////
#pragma mark -

@implementation NSString (MSubtitleParser_SRT)

SRTTag MMakeSRTTag(int type, int location, int length, NSString* attr)
{
    SRTTag tag;
    tag.type = type;
    tag.range.location = location;
    tag.range.length = length;
    tag.attr = attr;
    return tag;
}

- (SRTTag)srtTagWithRangePtr:(NSRange*)range delimSet:(NSCharacterSet*)delimSet
{
    //TRACE(@"%s %@ (%@)", __PRETTY_FUNCTION__, NSStringFromRange(*range), delimSet);
    NSRange or = [self rangeOfString:@"<" rangePtr:range];
    if (or.location == NSNotFound) {
        range->location = [self length];
        range->length = 0;
        return MMakeSRTTag(TAG_NONE, NSNotFound, 0, nil);
    }

    NSRange cr = [self rangeOfString:@">" rangePtr:range];
    if (cr.location == NSNotFound) {
        range->location = [self length];
        range->length = 0;
        return MMakeSRTTag(TAG_NONE, NSNotFound, 0, nil);
    }

    // find tag name
    int i, c = ([self characterAtIndex:or.location + 1] == '/') ? 1 : 0;
    NSRange ar;
    ar.location = or.location + 1 + c;
    ar.length = NSMaxRange(cr) - ar.location - 1;
    NSRange nr = [self tokenRangeForDelimiterSet:delimSet rangePtr:&ar];

    static const struct {
        NSString* name;
        int type[2];
    } nameType[] = {
        { @"FONT",  TAG_FONT_OPEN,  TAG_FONT_CLOSE },
        { @"I",     TAG_I_OPEN,     TAG_I_CLOSE },
        { @"B",     TAG_B_OPEN,     TAG_B_CLOSE },
    };
    for (i = 0; i < sizeof(nameType) / sizeof(nameType[0]); i++) {
        if (![self compare:nameType[i].name options:NSCaseInsensitiveSearch range:nr]) {
            return MMakeSRTTag(nameType[i].type[c],
                               or.location, NSMaxRange(cr) - or.location,
                               (0 < ar.length) ? [self substringWithRange:ar] : nil);
        }
    }
    return MMakeSRTTag(TAG_UNKNOWN, NSNotFound, 0, nil);
}

@end
