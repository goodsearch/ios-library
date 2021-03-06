/*
 Copyright 2009-2014 Urban Airship Inc. All rights reserved.

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:

 1. Redistributions of source code must retain the above copyright notice, this
 list of conditions and the following disclaimer.

 2. Redistributions in binaryform must reproduce the above copyright notice,
 this list of conditions and the following disclaimer in the documentation
 and/or other materials provided withthe distribution.

 THIS SOFTWARE IS PROVIDED BY THE URBAN AIRSHIP INC``AS IS'' AND ANY EXPRESS OR
 IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
 MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO
 EVENT SHALL URBAN AIRSHIP INC OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
 INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
 BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
 OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
 ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import <XCTest/XCTest.h>
#import <OCMOCK/OCMock.h>
#import <Foundation/Foundation.h>
#import "UAHTTPRequestEngine.h"
#import "UAChannelRegistrationPayload.h"
#import "UAChannelAPIClient.h"
#import "UAirship.h"
#import "UAHTTPRequest+Internal.h"
#import "UAConfig.h"
@interface UAChannelAPIClientTest : XCTestCase

@end

@implementation UAChannelAPIClientTest
id mockRequestEngine;
id mockAirship;
UAConfig *config;
UAChannelAPIClient *client;


- (void)setUp {
    [super setUp];

    config = [UAConfig config];

    mockAirship = [OCMockObject niceMockForClass:[UAirship class]];
    [[[mockAirship stub] andReturnValue:OCMOCK_VALUE(YES)] ready];
    [[[mockAirship stub] andReturn:mockAirship] shared];
    [[[mockAirship stub] andReturn:config] config];

    mockRequestEngine = [OCMockObject niceMockForClass:[UAHTTPRequestEngine class]];
    client = [UAChannelAPIClient clientWithRequestEngine:mockRequestEngine];
}

- (void)tearDown {
    [mockRequestEngine stopMocking];
    [mockAirship stopMocking];

    [super tearDown];
}

/**
 * Test create channel retries on 500 status codes other than 501
 */
- (void)testCreateChannelRetriesFailedRequests {

    // Check that the retry block returns YES for any 5xx request other than 501
    BOOL (^retryBlockCheck)(id obj) = ^(id obj) {
        UAHTTPRequestEngineWhereBlock retryBlock = obj;

        for (NSInteger i = 500; i < 600; i++) {
            UAHTTPRequest *request = [[UAHTTPRequest alloc] init];
            request.response = [[NSHTTPURLResponse alloc] initWithURL:nil statusCode:i HTTPVersion:nil headerFields:nil];

            // If shouldRetryOnConnection is NO, never retry
            client.shouldRetryOnConnectionError = NO;
            if (retryBlock(request)) {
                return NO;
            }

            // Allow it to retry on 5xx and error results
            client.shouldRetryOnConnectionError = YES;
            BOOL retryResult = retryBlock(request);

            // Only retry if its not 501
            if ((retryResult && i != 501) || (!retryResult && i == 501)) {
                continue;
            }

            return NO;
        }

        // Check that it returns NO for 400 status codes
        UAHTTPRequest *request = [[UAHTTPRequest alloc] init];
        request.response = [[NSHTTPURLResponse alloc] initWithURL:nil statusCode:400 HTTPVersion:nil headerFields:nil];
        if (retryBlock(request)) {
            return NO;
        }

        return YES;
    };

    [[mockRequestEngine expect] runRequest:OCMOCK_ANY
                              succeedWhere:OCMOCK_ANY
                                retryWhere:[OCMArg checkWithBlock:retryBlockCheck]
                                 onSuccess:OCMOCK_ANY
                                 onFailure:OCMOCK_ANY];

    [client createChannelWithPayload:nil onSuccess:nil onFailure:nil];
    XCTAssertNoThrow([mockRequestEngine verify], @"Create channel should call retry on 500 status codes other than 501.");
}

/**
 * Test create channel succeeds requests if the status is 200 or 201
 */
- (void)testCreateChannelSucceedsRequest {
    // Check that the retry block returns YES for any 5xx request other than 501
    BOOL (^whereBlockCheck)(id obj) = ^(id obj) {
        UAHTTPRequestEngineWhereBlock whereBlock = obj;
        UAHTTPRequest *request = [[UAHTTPRequest alloc] init];

        request.response = [[NSHTTPURLResponse alloc] initWithURL:nil statusCode:200 HTTPVersion:nil headerFields:nil];
        if (!whereBlock(request)) {
            return NO;
        }

        request.response = [[NSHTTPURLResponse alloc] initWithURL:nil statusCode:201 HTTPVersion:nil headerFields:nil];
        if (!whereBlock(request)) {
            return NO;
        }

        request.response = [[NSHTTPURLResponse alloc] initWithURL:nil statusCode:400 HTTPVersion:nil headerFields:nil];
        if (whereBlock(request)) {
            return NO;
        }

        return YES;
    };

    [[mockRequestEngine expect] runRequest:OCMOCK_ANY
                              succeedWhere:[OCMArg checkWithBlock:whereBlockCheck]
                                retryWhere:OCMOCK_ANY
                                 onSuccess:OCMOCK_ANY
                                 onFailure:OCMOCK_ANY];

    [client createChannelWithPayload:nil onSuccess:nil onFailure:nil];
    XCTAssertNoThrow([mockRequestEngine verify], @"Create channel should succeed on 201 status code.");
}

/**
 * Test create channel calls the onSuccessBlock with the response channel id
 * when the request is successful.
 */
- (void)testCreateChannelOnSuccess {
    __block NSString *channelID;
    __block NSString *channelLocation;

    // Set up a request with a valid response body
    UAHTTPRequest *request = [[UAHTTPRequest alloc] init];
    NSString *response = @"{ \"ok\":true, \"channel_id\": \"someChannelId\"}";
    request.responseData = [response dataUsingEncoding:NSUTF8StringEncoding];

    request.response = [[NSHTTPURLResponse alloc] initWithURL:nil statusCode:200 HTTPVersion:nil headerFields:@{@"Location":@"someChannelLocation"}];

    // Expect the run request and call the success block
    [[[mockRequestEngine stub] andDo:^(NSInvocation *invocation) {
        void *arg;
        [invocation getArgument:&arg atIndex:5];
        UAHTTPRequestEngineSuccessBlock successBlock = (__bridge UAHTTPRequestEngineSuccessBlock)arg;

        successBlock(request, 0);
    }] runRequest:OCMOCK_ANY succeedWhere:OCMOCK_ANY retryWhere:OCMOCK_ANY onSuccess:OCMOCK_ANY onFailure:OCMOCK_ANY];

    [client createChannelWithPayload:nil onSuccess:^(NSString *cId, NSString *location) {
        channelID = cId;
        channelLocation = location;
    } onFailure:nil];

    XCTAssertEqualObjects(@"someChannelId", channelID, @"Channel id should match someChannelId from the response");
    XCTAssertEqualObjects(@"someChannelLocation", channelLocation, @"Channel location should match location header from the response");
}

/**
 * Test create channel calls the onFailureBlock with the failed request when
 * the request fails.
 */
- (void)testCreateChannelOnFailure {
    __block UAHTTPRequest *failedRequest;

    UAHTTPRequest *request = [[UAHTTPRequest alloc] init];

    // Expect the run request and call the success block
    [[[mockRequestEngine stub] andDo:^(NSInvocation *invocation) {
        void *arg;
        [invocation getArgument:&arg atIndex:6];
        UAHTTPRequestEngineFailureBlock failureBlock = (__bridge UAHTTPRequestEngineFailureBlock)arg;
        failureBlock(request, 0);
    }] runRequest:OCMOCK_ANY succeedWhere:OCMOCK_ANY retryWhere:OCMOCK_ANY onSuccess:OCMOCK_ANY onFailure:OCMOCK_ANY];

    [client createChannelWithPayload:nil onSuccess:nil onFailure:^(UAHTTPRequest *request) {
        failedRequest = request;
    }];

    XCTAssertEqualObjects(request, failedRequest, @"Failure block should return the failed request");
}

/**
 * Test the request headers and body for a create channel request
 */
- (void)testCreateChannelRequest {

    UAChannelRegistrationPayload *payload = [[UAChannelRegistrationPayload alloc] init];

    BOOL (^checkRequestBlock)(id obj) = ^(id obj) {
        UAHTTPRequest *request = obj;

        // check the url
        if (![[request.url absoluteString] isEqualToString:@"https://device-api.urbanairship.com/api/channels/"]) {
            return NO;
        }

        // check that its a POST
        if (![request.HTTPMethod isEqualToString:@"POST"]) {
            return NO;
        }

        // Check that it contains an accept header
        if (![[request.headers valueForKey:@"Accept"] isEqualToString:@"application/vnd.urbanairship+json; version=3;"]) {
            return NO;
        }

        // Check that it contains an content type header
        if (![[request.headers valueForKey:@"Content-Type"] isEqualToString:@"application/json"]) {
            return NO;
        }

        if (![request.body isEqualToData:[payload asJSONData]]) {
            return NO;
        }

        // Check the body contains the payload
        return YES;
    };

    [[mockRequestEngine expect] runRequest:[OCMArg checkWithBlock:checkRequestBlock]
                              succeedWhere:OCMOCK_ANY
                                retryWhere:OCMOCK_ANY
                                 onSuccess:OCMOCK_ANY
                                 onFailure:OCMOCK_ANY];

    [client createChannelWithPayload:payload onSuccess:nil onFailure:nil];

    XCTAssertNoThrow([mockRequestEngine verify], @"Create channel should run with the a valid POST request.");
}


/**
 * Test update channel retries on any 500 status code
 */
- (void)testUpdateChannelRetriesFailedRequests {

    // Check that the retry block returns YES for any 5xx request
    BOOL (^retryBlockCheck)(id obj) = ^(id obj) {
        UAHTTPRequestEngineWhereBlock retryBlock = obj;

        for (NSInteger i = 500; i < 600; i++) {
            UAHTTPRequest *request = [[UAHTTPRequest alloc] init];
            request.response = [[NSHTTPURLResponse alloc] initWithURL:nil statusCode:i HTTPVersion:nil headerFields:nil];

            // If shouldRetryOnConnection is NO, never retry
            client.shouldRetryOnConnectionError = NO;
            if (retryBlock(request)) {
                return NO;
            }

            // Allow it to retry on 5xx and error results
            client.shouldRetryOnConnectionError = YES;
            if (!retryBlock(request)) {
                return NO;
            }
        }

        // Check that it returns NO for 400 status codes
        UAHTTPRequest *request = [[UAHTTPRequest alloc] init];
        request.response = [[NSHTTPURLResponse alloc] initWithURL:nil statusCode:400 HTTPVersion:nil headerFields:nil];
        if (retryBlock(request)) {
            return NO;
        }

        return YES;
    };

    [[mockRequestEngine expect] runRequest:OCMOCK_ANY
                              succeedWhere:OCMOCK_ANY
                                retryWhere:[OCMArg checkWithBlock:retryBlockCheck]
                                 onSuccess:OCMOCK_ANY
                                 onFailure:OCMOCK_ANY];

    [client updateChannelWithLocation:@"someLocation" withPayload:nil onSuccess:nil onFailure:nil];
    XCTAssertNoThrow([mockRequestEngine verify], @"Update channel should call retry on 500 status codes other than 501.");
}

/**
 * Test update channel succeeds requests if the status is 200 or 201
 */
- (void)testUpdateChannelSucceedsRequest {
    // Check that the retry block returns YES for any 5xx request other than 501
    BOOL (^whereBlockCheck)(id obj) = ^(id obj) {
        UAHTTPRequestEngineWhereBlock whereBlock = obj;
        UAHTTPRequest *request = [[UAHTTPRequest alloc] init];

        request.response = [[NSHTTPURLResponse alloc] initWithURL:nil statusCode:200 HTTPVersion:nil headerFields:nil];
        if (!whereBlock(request)) {
            return NO;
        }

        request.response = [[NSHTTPURLResponse alloc] initWithURL:nil statusCode:201 HTTPVersion:nil headerFields:nil];
        if (!whereBlock(request)) {
            return NO;
        }

        request.response = [[NSHTTPURLResponse alloc] initWithURL:nil statusCode:400 HTTPVersion:nil headerFields:nil];
        if (whereBlock(request)) {
            return NO;
        }

        return YES;
    };

    [[mockRequestEngine expect] runRequest:OCMOCK_ANY
                              succeedWhere:[OCMArg checkWithBlock:whereBlockCheck]
                                retryWhere:OCMOCK_ANY
                                 onSuccess:OCMOCK_ANY
                                 onFailure:OCMOCK_ANY];

    [client updateChannelWithLocation:@"someLocation" withPayload:nil onSuccess:nil onFailure:nil];
    XCTAssertNoThrow([mockRequestEngine verify], @"Update channel should succeed on 200 status code.");
}

/**
 * Test update channel calls the onSuccessBlock when the request is successful.
 */
- (void)testUpdateChannelOnSuccess {
    __block BOOL  onSuccessCalled = NO;

    // Set up a request with a valid response body
    UAHTTPRequest *request = [[UAHTTPRequest alloc] init];
    NSString *response = @"{ \"ok\":true, \"channel_id\": \"someChannelId\"}";
    request.responseData = [response dataUsingEncoding:NSUTF8StringEncoding];

    // Expect the run request and call the success block
    [[[mockRequestEngine stub] andDo:^(NSInvocation *invocation) {
        void *arg;
        [invocation getArgument:&arg atIndex:5];
        UAHTTPRequestEngineSuccessBlock successBlock = (__bridge UAHTTPRequestEngineSuccessBlock)arg;

        successBlock(request, 0);
    }] runRequest:OCMOCK_ANY succeedWhere:OCMOCK_ANY retryWhere:OCMOCK_ANY onSuccess:OCMOCK_ANY onFailure:OCMOCK_ANY];

    [client updateChannelWithLocation:@"someLocation" withPayload:nil onSuccess:^{
        onSuccessCalled = YES;
    } onFailure:nil];

    XCTAssertTrue(onSuccessCalled, @"Update should call the onSuccess block when its successful");
}

/**
 * Test update channel calls the onFailureBlock with the failed request when
 * the request fails.
 */
- (void)testUpdateChannelOnFailure {
    __block UAHTTPRequest *failedRequest;

    UAHTTPRequest *request = [[UAHTTPRequest alloc] init];

    // Expect the run request and call the failure block
    [[[mockRequestEngine stub] andDo:^(NSInvocation *invocation) {
        void *arg;
        [invocation getArgument:&arg atIndex:6];
        UAHTTPRequestEngineFailureBlock failureBlock = (__bridge UAHTTPRequestEngineFailureBlock)arg;
        failureBlock(request, 0);
    }] runRequest:OCMOCK_ANY succeedWhere:OCMOCK_ANY retryWhere:OCMOCK_ANY onSuccess:OCMOCK_ANY onFailure:OCMOCK_ANY];

    [client updateChannelWithLocation:@"someLocation" withPayload:nil onSuccess:nil onFailure:^(UAHTTPRequest *request) {
        failedRequest = request;
    }];

    XCTAssertEqualObjects(request, failedRequest, @"Failure block should return the failed request");
}

/**
 * Test the request headers and body for an update channel request
 */
- (void)testUpdateChannelRequest {

    UAChannelRegistrationPayload *payload = [[UAChannelRegistrationPayload alloc] init];

    BOOL (^checkRequestBlock)(id obj) = ^(id obj) {
        UAHTTPRequest *request = obj;

        // check the url
        if (![[request.url absoluteString] isEqualToString:@"https://device-api.urbanairship.com/someLocation"]) {
            return NO;
        }

        // check that its a POST
        if (![request.HTTPMethod isEqualToString:@"PUT"]) {
            return NO;
        }

        // Check that it contains an accept header
        if (![[request.headers valueForKey:@"Accept"] isEqualToString:@"application/vnd.urbanairship+json; version=3;"]) {
            return NO;
        }

        // Check that it contains an content type header
        if (![[request.headers valueForKey:@"Content-Type"] isEqualToString:@"application/json"]) {
            return NO;
        }

        if (![request.body isEqualToData:[payload asJSONData]]) {
            return NO;
        }

        // Check the body contains the payload
        return YES;
    };

    [[mockRequestEngine expect] runRequest:[OCMArg checkWithBlock:checkRequestBlock]
                              succeedWhere:OCMOCK_ANY
                                retryWhere:OCMOCK_ANY
                                 onSuccess:OCMOCK_ANY
                                 onFailure:OCMOCK_ANY];
    
    [client updateChannelWithLocation:@"https://device-api.urbanairship.com/someLocation" withPayload:payload onSuccess:nil onFailure:nil];
    
    XCTAssertNoThrow([mockRequestEngine verify], @"Update channel should run with the a valid PUT request.");
}

/**
 * Test update channel with a nil channel id does not run
 */
- (void)testUpdateChannelNilID {
    [[mockRequestEngine reject] runRequest:OCMOCK_ANY
                              succeedWhere:OCMOCK_ANY
                                retryWhere:OCMOCK_ANY
                                 onSuccess:OCMOCK_ANY
                                 onFailure:OCMOCK_ANY];

    [client updateChannelWithLocation:nil withPayload:nil onSuccess:nil onFailure:nil];
    XCTAssertNoThrow([mockRequestEngine verify], @"Update channel should not make a request with an empty ID.");
}

@end
