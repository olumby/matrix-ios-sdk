/*
 Copyright 2016 OpenMarket Ltd

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

#import "MXSDKOptions.h"

#ifdef MX_CRYPTO

#import "MXOlmDevice.h"

#import <OLMKit/OLMKit.h>

#import "NSObject+sortedKeys.h"

@interface MXOlmDevice ()
{
    // The OLMKit account instance.
    OLMAccount *olmAccount;

    // The OLMKit utility instance.
    OLMUtility *olmUtility;

    // The outbound group session.
    // They are not stored in 'store' to avoid to remember to which devices we sent the session key.
    // Plus, in cryptography, it is good to refresh sessions from time to time.
    // The key is the session id, the value the outbound group session.
    NSMutableDictionary<NSString*, OLMOutboundGroupSession*> *outboundGroupSessionStore;

    // Store a set of decrypted message indexes for each group session.
    // This partially mitigates a replay attack where a MITM resends a group
    // message into the room.
    //
    // The Matrix SDK exposes events through MXEventTimelines. A developer can open several
    // timelines from a same room so that a message can be decrypted several times but from
    // a different timeline.
    // So, store these message indexes per timeline id.
    //
    // The first level keys are timeline ids.
    // The second level keys are strings of form "<senderKey>|<session_id>|<message_index>"
    // Values are @(YES).
    NSMutableDictionary<NSString*,
        NSMutableDictionary<NSString*, NSNumber*> *> *inboundGroupSessionMessageIndexes;
}

// The store where crypto data is saved.
@property (nonatomic, readonly) id<MXCryptoStore> store;

@end


@implementation MXOlmDevice
@synthesize store;

- (instancetype)initWithStore:(id<MXCryptoStore>)theStore
{
    self = [super init];
    if (self)
    {
        store = theStore;

        // Retrieve the account from the store
        olmAccount = [store account];
        if (!olmAccount)
        {
            NSLog(@"[MXOlmDevice] initWithStore: Create new OLMAccount");

            // Else, create it
            olmAccount = [[OLMAccount alloc] initNewAccount];

            [store storeAccount:olmAccount];
        }
        else
        {
            NSLog(@"[MXOlmDevice] initWithStore: Reuse OLMAccount from store");
        }

        olmUtility = [[OLMUtility alloc] init];

        outboundGroupSessionStore = [NSMutableDictionary dictionary];
        inboundGroupSessionMessageIndexes = [NSMutableDictionary dictionary];

        _deviceCurve25519Key = olmAccount.identityKeys[@"curve25519"];
        _deviceEd25519Key = olmAccount.identityKeys[@"ed25519"];
    }
    return self;
}

- (NSString *)olmVersion
{
    return [OLMKit versionString];
}

- (NSString *)signMessage:(NSData*)message
{
    return [olmAccount signMessage:message];
}

- (NSString *)signJSON:(NSDictionary *)JSONDictinary
{
    return [self signMessage:[self canonicalJSONForJSON:JSONDictinary]];
}

- (NSDictionary *)oneTimeKeys
{
    return olmAccount.oneTimeKeys;
}

- (NSUInteger)maxNumberOfOneTimeKeys
{
    return olmAccount.maxOneTimeKeys;
}

- (void)markOneTimeKeysAsPublished
{
    [olmAccount markOneTimeKeysAsPublished];

    [store storeAccount:olmAccount];
}

- (void)generateOneTimeKeys:(NSUInteger)numKeys
{
    [olmAccount generateOneTimeKeys:numKeys];

    [store storeAccount:olmAccount];
}

- (NSString *)createOutboundSession:(NSString *)theirIdentityKey theirOneTimeKey:(NSString *)theirOneTimeKey
{
    NSError *error;

    NSLog(@">>>> createOutboundSession: theirIdentityKey: %@ theirOneTimeKey: %@", theirIdentityKey, theirOneTimeKey);

    OLMSession *olmSession = [[OLMSession alloc] initOutboundSessionWithAccount:olmAccount theirIdentityKey:theirIdentityKey theirOneTimeKey:theirOneTimeKey error:&error];

    NSLog(@">>>> olmSession.sessionIdentifier: %@", olmSession.sessionIdentifier);

    if (olmSession)
    {
        [store storeSession:olmSession forDevice:theirIdentityKey];
        return olmSession.sessionIdentifier;
    }
    else if (error)
    {
        NSLog(@"[MXOlmDevice] createOutboundSession. Error: %@", error);
    }

    return nil;
}

- (NSString*)createInboundSession:(NSString*)theirDeviceIdentityKey messageType:(NSUInteger)messageType cipherText:(NSString*)ciphertext payload:(NSString**)payload
{
    NSError *error;

    NSLog(@"<<< createInboundSession: theirIdentityKey: %@", theirDeviceIdentityKey);

    OLMSession *olmSession = [[OLMSession alloc] initInboundSessionWithAccount:olmAccount theirIdentityKey:theirDeviceIdentityKey oneTimeKeyMessage:ciphertext error:&error];

    NSLog(@"<<< olmSession.sessionIdentifier: %@", olmSession.sessionIdentifier);

    if (olmSession)
    {
        [olmAccount removeOneTimeKeysForSession:olmSession];
        [store storeAccount:olmAccount];

        NSLog(@"<<< ciphertext: %@", ciphertext);
        NSLog(@"<<< ciphertext: SHA256: %@", [olmUtility sha256:[ciphertext dataUsingEncoding:NSUTF8StringEncoding]]);

        *payload = [olmSession decryptMessage:[[OLMMessage alloc] initWithCiphertext:ciphertext type:messageType] error:&error];

        if (error)
        {
            NSLog(@"[MXOlmDevice] createInboundSession. decryptMessage error: %@", error);
        }

        [store storeSession:olmSession forDevice:theirDeviceIdentityKey];

        return olmSession.sessionIdentifier;
    }
    else if (error)
    {
        NSLog(@"[MXOlmDevice] createInboundSession. Error: %@", error);
    }

    return nil;
}

- (NSArray<NSString *> *)sessionIdsForDevice:(NSString *)theirDeviceIdentityKey
{
    NSDictionary *sessions = [store sessionsWithDevice:theirDeviceIdentityKey];

    return sessions.allKeys;
}

- (NSString *)sessionIdForDevice:(NSString *)theirDeviceIdentityKey
{
    NSString *sessionId;

    NSArray<NSString *> *sessionIds = [self sessionIdsForDevice:theirDeviceIdentityKey];
    if (sessionIds.count)
    {
        // Use the session with the lowest ID.
        NSArray *sortedSessionIds = [sessionIds sortedArrayUsingSelector:@selector(compare:)];
        sessionId = sortedSessionIds[0];
    }

    return sessionId;
}

- (NSDictionary *)encryptMessage:(NSString *)theirDeviceIdentityKey sessionId:(NSString *)sessionId payloadString:(NSString *)payloadString
{
    NSError *error;
    OLMMessage *olmMessage;

    OLMSession *olmSession = [self sessionForDevice:theirDeviceIdentityKey andSessionId:sessionId];

    NSLog(@">>>> encryptMessage: olmSession.sessionIdentifier: %@", olmSession.sessionIdentifier);
    //NSLog(@">>>> payloadString: %@", payloadString);

    if (olmSession)
    {
        olmMessage = [olmSession encryptMessage:payloadString error:&error];

        if (error)
        {
            NSLog(@"[MXOlmDevice] encryptMessage failed: %@", error);
        }

        [store storeSession:olmSession forDevice:theirDeviceIdentityKey];
    }

    //NSLog(@">>>> ciphertext: %@", olmMessage.ciphertext);
    //NSLog(@">>>> ciphertext: SHA256: %@", [olmUtility sha256:[olmMessage.ciphertext dataUsingEncoding:NSUTF8StringEncoding]]);

    return @{
             @"body": olmMessage.ciphertext,
             @"type": @(olmMessage.type)
             };
}

- (NSString*)decryptMessage:(NSString*)ciphertext withType:(NSUInteger)messageType sessionId:(NSString*)sessionId theirDeviceIdentityKey:(NSString*)theirDeviceIdentityKey
{
    NSError *error;
    NSString *payloadString;

    OLMSession *olmSession = [self sessionForDevice:theirDeviceIdentityKey andSessionId:sessionId];
    if (olmSession)
    {
        payloadString = [olmSession decryptMessage:[[OLMMessage alloc] initWithCiphertext:ciphertext type:messageType] error:&error];

        if (error)
        {
            NSLog(@"[MXOlmDevice] decryptMessage failed: %@", error);
        }

        [store storeSession:olmSession forDevice:theirDeviceIdentityKey];
    }

    return payloadString;
}

- (BOOL)matchesSession:(NSString *)theirDeviceIdentityKey sessionId:(NSString *)sessionId messageType:(NSUInteger)messageType ciphertext:(NSString *)ciphertext
{
    if (messageType != 0)
    {
        return NO;
    }

    OLMSession *olmSession = [self sessionForDevice:theirDeviceIdentityKey andSessionId:sessionId];
    return [olmSession matchesInboundSession:ciphertext];
}


#pragma mark - Outbound group session
- (NSString *)createOutboundGroupSession
{
    OLMOutboundGroupSession *session = [[OLMOutboundGroupSession alloc] initOutboundGroupSession];
    outboundGroupSessionStore[session.sessionIdentifier] = session;

    return session.sessionIdentifier;
}

- (NSString *)sessionKeyForOutboundGroupSession:(NSString *)sessionId
{
    return outboundGroupSessionStore[sessionId].sessionKey;
}

- (NSUInteger)messageIndexForOutboundGroupSession:(NSString *)sessionId
{
    return outboundGroupSessionStore[sessionId].messageIndex;
}

- (NSString *)encryptGroupMessage:(NSString *)sessionId payloadString:(NSString *)payloadString
{
    return [outboundGroupSessionStore[sessionId] encryptMessage:payloadString error:nil];
}


#pragma mark - Inbound group session
- (BOOL)addInboundGroupSession:(NSString *)sessionId sessionKey:(NSString *)sessionKey roomId:(NSString *)roomId senderKey:(NSString *)senderKey keysClaimed:(NSDictionary<NSString *,NSString *> *)keysClaimed
{
    NSError *error;
    if ([self inboundGroupSessionWithId:sessionId senderKey:senderKey roomId:roomId error:&error])
    {
        // If we already have this session, consider updating it
        NSLog(@"[MXOlmDevice] addInboundGroupSession: Update for megolm session %@/%@", senderKey, sessionId);

        // For now we just ignore updates. TODO: implement something here
        return NO;
    }

    MXOlmInboundGroupSession *session = [[MXOlmInboundGroupSession alloc] initWithSessionKey:sessionKey];

    if (![session.session.sessionIdentifier isEqualToString:sessionId])
    {
        NSLog(@"[MXOlmDevice] addInboundGroupSession: ERROR: Mismatched group session ID from senderKey: %@", senderKey);
        return NO;
    }

    session.senderKey = senderKey;
    session.roomId = roomId;
    session.keysClaimed = keysClaimed;

    [store storeInboundGroupSession:session];

    return YES;
}

- (MXDecryptionResult *)decryptGroupMessage:(NSString *)body roomId:(NSString *)roomId
                                 inTimeline:(NSString *)timeline
                                  sessionId:(NSString *)sessionId senderKey:(NSString *)senderKey
                                      error:(NSError *__autoreleasing *)error
{
    MXDecryptionResult *result;

    MXOlmInboundGroupSession *session = [self inboundGroupSessionWithId:sessionId senderKey:senderKey roomId:roomId error:error];
    if (session)
    {
        NSUInteger messageIndex;
        NSString *payloadString = [session.session decryptMessage:body messageIndex:&messageIndex error:error];

        [store storeInboundGroupSession:session];

        if (payloadString)
        {
            // Check if we have seen this message index before to detect replay attacks.
            if (timeline)
            {
                if (!inboundGroupSessionMessageIndexes[timeline])
                {
                    inboundGroupSessionMessageIndexes[timeline] = [NSMutableDictionary dictionary];
                }

                NSString *messageIndexKey = [NSString stringWithFormat:@"%@|%@|%tu", senderKey, sessionId, messageIndex];
                if (inboundGroupSessionMessageIndexes[timeline][messageIndexKey])
                {
                    NSLog(@"[MXOlmDevice] decryptGroupMessage: Warning: Possible replay attack %@", messageIndexKey);

                    if (error)
                    {
                        *error = [NSError errorWithDomain:MXDecryptingErrorDomain
                                                     code:MXDecryptingErrorDuplicateMessageIndexCode
                                                 userInfo:@{
                                                            NSLocalizedDescriptionKey: [NSString stringWithFormat:MXDecryptingErrorDuplicateMessageIndexReason, messageIndexKey]
                                                            }];
                    }

                    return nil;
                }

                inboundGroupSessionMessageIndexes[timeline][messageIndexKey] = @(YES);
            }

            result = [[MXDecryptionResult alloc] init];
            result.payload = [NSJSONSerialization JSONObjectWithData:[payloadString dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
            result.keysClaimed = session.keysClaimed;

            // The sender must have had the senderKey to persuade us to save the
            // session.
            result.keysProved = @{
                                  @"curve25519": senderKey
                                  };
        }
    }

    if (*error)
    {
        NSLog(@"[MXOlmDevice] decryptGroupMessage: Error: %@", *error);
    }

    return result;
}

- (void)resetReplayAttackCheckInTimeline:(NSString*)timeline
{
    [inboundGroupSessionMessageIndexes removeObjectForKey:timeline];
}

/**
 Extract an InboundGroupSession from the session store and do some check.

 @param roomId the room where the sesion is used.
 @param sessionId the session identifier.
 @param senderKey the base64-encoded curve25519 key of the sender.
 @param the result error if there is an issue.
 @return the inbound group session.
 */
- (MXOlmInboundGroupSession *)inboundGroupSessionWithId:(NSString *)sessionId senderKey:(NSString *)senderKey
                                                 roomId:(NSString *)roomId
                                                  error:(NSError *__autoreleasing *)error
{
    MXOlmInboundGroupSession *session = [store inboundGroupSessionWithId:sessionId andSenderKey:senderKey];

    if (session)
    {
        // Check that the room id matches the original one for the session. This stops
        // the HS pretending a message was targeting a different room.
        if (![roomId isEqualToString:session.roomId])
        {
            NSLog(@"[MXOlmDevice] inboundGroupSessionWithId: ERROR: Mismatched room_id for inbound group session (expected %@, was %@)", roomId, session.roomId);

            NSString *errorDescription = [NSString stringWithFormat:MXDecryptingErrorInboundSessionMismatchRoomIdReason, roomId, session.roomId];

            if (error)
            {
                *error = [NSError errorWithDomain:MXDecryptingErrorDomain
                                             code:MXDecryptingErrorUnknownInboundSessionIdCode
                                         userInfo:@{
                                                    NSLocalizedDescriptionKey: errorDescription
                                                    }];
            }
        }
    }
    else
    {
        NSLog(@"[MXOlmDevice] inboundGroupSessionWithId: Cannot retrieve inbound group session %@", sessionId);

        if (error)
        {
            *error = [NSError errorWithDomain:MXDecryptingErrorDomain
                                         code:MXDecryptingErrorUnknownInboundSessionIdCode
                                     userInfo:@{
                                                NSLocalizedDescriptionKey: MXDecryptingErrorUnknownInboundSessionIdReason
                                                }];
        }
    }
    return session;
}


#pragma mark - Utilities
- (BOOL)verifySignature:(NSString *)key message:(NSString *)message signature:(NSString *)signature error:(NSError *__autoreleasing *)error
{
    return [olmUtility verifyEd25519Signature:signature key:key message:[message dataUsingEncoding:NSUTF8StringEncoding] error:error];
}

- (BOOL)verifySignature:(NSString *)key JSON:(NSDictionary *)JSONDictinary signature:(NSString *)signature error:(NSError *__autoreleasing *)error
{
    return [olmUtility verifyEd25519Signature:signature key:key message:[self canonicalJSONForJSON:JSONDictinary] error:error];
}

- (NSString *)sha256:(NSString *)message
{
    return [olmUtility sha256:[message dataUsingEncoding:NSUTF8StringEncoding]];
}


#pragma mark - Private methods
- (OLMSession*)sessionForDevice:(NSString *)theirDeviceIdentityKey andSessionId:(NSString*)sessionId
{
    return [store sessionsWithDevice:theirDeviceIdentityKey][sessionId];
}

/**
 Get the canonical version of a JSON dictionary.
 
 This ensures that a JSON has the same string representation cross platforms.

 @param JSONDictinary the JSON to convert.
 @return the canonical version of the JSON.
 */
- (NSData*)canonicalJSONForJSON:(NSDictionary*)JSONDictinary
{
    NSData *canonicalJSONData = [NSJSONSerialization dataWithJSONObject:[JSONDictinary objectWithSortedKeys] options:0 error:nil];

    // NSJSONSerialization escapes the '/' character in base64 strings which is useless in our case
    // and does not match with other platforms.
    // Remove this escaping
    NSString *unescapedCanonicalJSON = [[NSString alloc] initWithData:canonicalJSONData encoding:NSUTF8StringEncoding];
    unescapedCanonicalJSON = [unescapedCanonicalJSON stringByReplacingOccurrencesOfString:@"\\/" withString:@"/"];

    return [unescapedCanonicalJSON dataUsingEncoding:NSUTF8StringEncoding];
}

@end

#endif
