/*
 Copyright 2014 OpenMarket Ltd

 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at

 http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */

#import "MXFileRoomStore.h"

@implementation MXFileRoomStore

#pragma mark - NSCoding
- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [self init];
    if (self)
    {
        messages = [aDecoder decodeObjectForKey:@"messages"];

        self.paginationToken = [aDecoder decodeObjectForKey:@"paginationToken"];
        
        self.notificationCount = [((NSNumber*)[aDecoder decodeObjectForKey:@"notificationCount"]) unsignedIntegerValue];
        self.highlightCount = [((NSNumber*)[aDecoder decodeObjectForKey:@"highlightCount"]) unsignedIntegerValue];

        self.hasReachedHomeServerPaginationEnd = [aDecoder decodeBoolForKey:@"hasReachedHomeServerPaginationEnd"];

        self.partialTextMessage = [aDecoder decodeObjectForKey:@"partialTextMessage"];

        outgoingMessages = [aDecoder decodeObjectForKey:@"outgoingMessages"];

        // Rebuild the messagesByEventIds cache
        for (MXEvent *event in messages)
        {
            if (event.eventId)
            {
                messagesByEventIds[event.eventId] = event;
            }
        }
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    // The goal of the NSCoding implementation here is to store room data to the file system during a [MXFileStore commit].

    // Note this operation is  called from another thread.
    // As the messages array continously grows, if some messages come while looping, they will not
    // be serialised this time but they will be on the next [MXFileStore commit] that will be called for them.
    // If messages come between [MXFileStore commit] and this method, more messages will be serialised. This is
    // not a problem.
    [aCoder encodeObject:[messages mutableCopy] forKey:@"messages"];

    if (self.paginationToken)
    {
        [aCoder encodeObject:self.paginationToken forKey:@"paginationToken"];
    }
    
    if (self.notificationCount)
    {
        [aCoder encodeObject:@(self.notificationCount) forKey:@"notificationCount"];
    }
    if (self.highlightCount)
    {
        [aCoder encodeObject:@(self.highlightCount) forKey:@"highlightCount"];
    }
    
    [aCoder encodeBool:self.hasReachedHomeServerPaginationEnd forKey:@"hasReachedHomeServerPaginationEnd"];

    if (self.partialTextMessage)
    {
        [aCoder encodeObject:self.partialTextMessage forKey:@"partialTextMessage"];
    }

    [aCoder encodeObject:[outgoingMessages mutableCopy] forKey:@"outgoingMessages"];
}

@end
