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

#import "MXMyUser.h"

#import "MXSession.h"

@interface MXMyUser ()
@end

@implementation MXMyUser

- (instancetype)initWithUserId:(NSString *)userId andDisplayname:(NSString *)displayname andAvatarUrl:(NSString *)avatarUrl
{
    self = [super initWithUserId:userId];
    if (self)
    {
        self.displayname = [displayname copy];
        self.avatarUrl = [avatarUrl copy];
    }
    return self;
}

- (void)setDisplayName:(NSString *)displayname success:(void (^)())success failure:(void (^)(NSError *))failure
{
    [_mxSession.matrixRestClient setDisplayName:displayname success:^{

        // Update the information right now
        self.displayname = [displayname copy];

        [_mxSession.store storeUser:self];
        if ([_mxSession.store respondsToSelector:@selector(commit)])
        {
            [_mxSession.store commit];
        }

        if (success)
        {
            success();
        }

    } failure:^(NSError *error) {
        if (failure)
        {
            failure(error);
        }
    }];
}

- (void)setAvatarUrl:(NSString *)avatarUrl success:(void (^)())success failure:(void (^)(NSError *))failure
{
    [_mxSession.matrixRestClient setAvatarUrl:avatarUrl success:^{

        // Update the information right now
        self.avatarUrl = [avatarUrl copy];

        [_mxSession.store storeUser:self];
        if ([_mxSession.store respondsToSelector:@selector(commit)])
        {
            [_mxSession.store commit];
        }

        if (success)
        {
            success();
        }

    } failure:^(NSError *error) {
        if (failure)
        {
            failure(error);
        }
    }];
}

- (void)setPresence:(MXPresence)presence andStatusMessage:(NSString *)statusMessage success:(void (^)())success failure:(void (^)(NSError *))failure
{
    [_mxSession.matrixRestClient setPresence:presence andStatusMessage:statusMessage success:^{

        // Update the information right now
        _presence = presence;
        _statusMsg = [statusMessage copy];

        [_mxSession.store storeUser:self];
        if ([_mxSession.store respondsToSelector:@selector(commit)])
        {
            [_mxSession.store commit];
        }

        if (success)
        {
            success();
        }

    } failure:^(NSError *error) {
        if (failure)
        {
            failure(error);
        }
    }];
}

- (void)setDisplayname:(NSString *)displayname
{
    if (_mxSession.store.isPermanent && _displayname != displayname && NO == [_displayname isEqualToString:displayname])
    {
        [_mxSession.store storeUser:self];
        if ([_mxSession.store respondsToSelector:@selector(commit)])
        {
            [_mxSession.store commit];
        }
    }
    _displayname = displayname;
}

-(void)setAvatarUrl:(NSString *)avatarUrl
{
    if (_mxSession.store.isPermanent && _avatarUrl != avatarUrl && NO == [_avatarUrl isEqualToString:avatarUrl])
    {
        [_mxSession.store storeUser:self];
        if ([_mxSession.store respondsToSelector:@selector(commit)])
        {
            [_mxSession.store commit];
        }
    }
    _avatarUrl = avatarUrl;
}

@end
