//
//  PrimusTest.m
//  PrimusTests
//
//  Created by Nuno Sousa on 14/01/14.
//  Copyright (c) 2014 Seegno. All rights reserved.
//

#import "Primus.h"

SpecBegin(Primus)

describe(@"Primus", ^{
    __block Primus *primus;

    setAsyncSpecTimeout(2.0);

    beforeEach(^{
        NSURL *url = [NSURL URLWithString:@"http://127.0.0.1"];
        PrimusConnectOptions *options = [[PrimusConnectOptions alloc] init];

        options.manual = YES;

        primus = [[Primus alloc] initWithURL:url options:options];
        primus.transformer = mockRequiredObjectAndProtocol([NSObject class], @protocol(TransformerProtocol));
    });

    afterEach(^{
        [primus removeAllListeners];
        [primus end];

        primus = nil;
    });

    it(@"initializes with defaults", ^{
        expect(primus.online).to.equal(YES);
        expect(primus.writable).to.equal(NO);
        expect(primus.readyState).to.equal(kPrimusReadyStateClosed);
        expect(primus.options).to.beInstanceOf([PrimusConnectOptions class]);
    });

    it(@"throws an error if initialised without a transformer", ^{
        expect(^{
            primus.transformer = nil;

            [primus open];
        }).to.raiseWithReason(@"NSInvalidArgumentException", @"No transformer specified.");
    });

    it(@"throws an error if initialised with an invalid transformer", ^{
        expect(^{
            NSURL *url = [NSURL URLWithString:@"http://127.0.0.1"];
            PrimusConnectOptions *options = [[PrimusConnectOptions alloc] init];

            options.manual = YES;
            options.transformerClass = [NSObject class];

            [[[Primus alloc] initWithURL:url options:options] open];
        }).to.raiseWithReason(@"NSInvalidArgumentException", @"Transformer does not implement TransformerProtocol.");
    });

    it(@"emits an `initialised` event when the server is fully constructed", ^AsyncBlock {
        [primus on:@"initialised" listener:^(id<TransformerProtocol> transformer, id<ParserProtocol> parser) {
            expect(transformer).to.equal(primus.transformer);
            expect(parser).to.equal(primus.parser);

            done();
        }];

        [primus open];
    });

    it(@"emits an `open` event", ^AsyncBlock {
        [primus on:@"open" listener:^{
            done();
        }];

        [primus emit:@"incoming::open"];
    });

    it(@"emits an `end` event after closing", ^AsyncBlock {
        [primus on:@"end" listener:^{
            done();
        }];

        [primus open];
        [primus end];
    });

    it(@"emits a `close` event after closing", ^AsyncBlock {
        [primus on:@"close" listener:^{
            done();
        }];

        [primus open];
        [primus end];
    });

    it(@"emits an `error` event when it cannot encode the data", ^AsyncBlock {
        [primus on:@"error" listener:^(NSError *error){
            expect(error).notTo.beNil();
            expect(error.localizedFailureReason).to.contain(@"Invalid top-level type in JSON write");

            done();
        }];

        [primus open];
        [primus emit:@"incoming::open"];

        [primus write:@123];
    });

    it(@"only emits `end` once", ^{
        [primus end];

        [primus on:@"end" listener:^{
            NSAssert(NO, @"listener should not fire");
        }];

        [primus end];
    });

    it(@"buffers messages before connecting", ^AsyncBlock {
        __block int received = 0;
        int messages = 10;

        for(int i=0; i < messages; i++) {
            [primus write:@{ @"echo": @(i) }];
        }

        [primus on:@"outgoing::data" listener:^{
            if (++received == messages) {
                done();
            }
        }];

        [primus open];
        [primus emit:@"incoming::open"];
    });

    it(@"should do nothing if id is unavailable", ^{
        [primus id:^(NSString *socketId) {
            NSAssert(NO, @"listener should not fire");
        }];
    });

    it(@"should return id from transformer if one is available", ^AsyncBlock {
        primus.transformer = mockObjectAndProtocol([NSObject class], @protocol(TransformerProtocol));

        [given([primus.transformer id]) willReturn:@"123"];

        [primus id:^(NSString *socketId) {
            expect(socketId).to.equal(@"123");

            done();
        }];
    });

    it(@"should return id when `incoming::id` is emitted", ^AsyncBlock {
        [primus id:^(NSString *socketId) {
            expect(socketId).to.equal(@"123");

            done();
        }];

        [primus emit:@"incoming::id", @"123"];
    });

    it(@"should not open the socket if the state is manual", ^{
        [primus on:@"open" listener:^{
            NSAssert(NO, @"listener should not fire");
        }];

        expect(primus.readyState).notTo.equal(kPrimusReadyStateOpen);
    });

    it(@"should not reconnect when we close the connection", ^{
        [primus emit:@"incoming::open"];

        [primus on:@"reconnect" listener:^(PrimusReconnectOptions *options) {
            NSAssert(NO, @"listener should not fire");
        }];

        [primus end];
    });

    it(@"should not reconnect when strategy is none", ^{
        [primus.options.reconnect.strategies removeAllObjects];

        [primus on:@"reconnect" listener:^(PrimusReconnectOptions *options) {
            NSAssert(NO, @"listener should not fire");
        }];

        [primus emit:@"incoming::open"];

        [primus emit:@"incoming::end", nil];
    });

    it(@"should reconnect when the connection closes unexpectedly", ^AsyncBlock {
        PrimusTimers *timers = mock([PrimusTimers class]);

        [primus setValue:timers forKey:@"_timers"];

        [primus on:@"reconnect" listener:^(PrimusReconnectOptions *options) {
            [verifyCount(timers, never()) clearAll];

            NSLog(@"timers: %@", timers.reconnect);

            done();
        }];

        [primus emit:@"incoming::open"];

        [primus emit:@"incoming::end", nil];
    });

    it(@"should reset the reconnect details after a successful reconnect", ^AsyncBlock {
        [primus performSelector:@selector(reconnect)];

        primus.attemptOptions.attempt = 5;

        [primus on:@"open" listener:^{
            expect(primus.attemptOptions).to.beNil();

            done();
        }];

        [primus emit:@"incoming::open"];
    });

    it(@"should change readyStates", ^AsyncBlock {
        expect(primus.readyState).to.equal(@(kPrimusReadyStateClosed));

        [primus open];

        expect(primus.readyState).to.equal(@(kPrimusReadyStateOpening));

        [primus on:@"open" listener:^{
            expect(primus.readyState).to.equal(@(kPrimusReadyStateOpen));

            [primus end];
        }];

        [primus on:@"end" listener:^{
            expect(primus.readyState).to.equal(@(kPrimusReadyStateClosed));

            done();
        }];

        [primus emit:@"incoming::open"];
    });

    it(@"should modify data on an incoming transformer", ^AsyncBlock {
        [primus transform:@"incoming" fn:^BOOL(NSMutableDictionary *data) {
            data[@"data"] = @{ @"example": @"data" };

            return YES;
        }];

        [primus on:@"data" listener:^(NSString *data) {
            expect(data).to.equal(@{ @"example": @"data" });
        }];

        [primus emit:@"incoming::data", [@"{\"key\":\"value\"}" dataUsingEncoding:NSUTF8StringEncoding]];

        done();
    });

    it(@"should not emit `data` event when returning NO from an incoming transformer", ^AsyncBlock {
        [primus transform:@"incoming" fn:^BOOL(NSDictionary *data) {
            return NO;
        }];

        [primus on:@"data" listener:^{
            NSAssert(NO, @"listener should not fire");
        }];

        [primus emit:@"incoming::data", [@"{\"key\":\"value\"}" dataUsingEncoding:NSUTF8StringEncoding]];

        done();
    });

    it(@"should modify data on an outgoing transformer", ^AsyncBlock {
        [primus transform:@"outgoing" fn:^BOOL(NSMutableDictionary *data) {
            data[@"data"] = @"foo";

            return YES;
        }];

        [primus emit:@"incoming::open"];

        [primus on:@"outgoing::data" listener:^(NSString *data) {
            expect(data).to.equal(@"\"foo\"");
        }];

        [primus write:@{ @"example": @"parameter" }];

        done();
    });

    it(@"should not emit `data` event when returning NO from an outgoing transformer", ^AsyncBlock {
        [primus transform:@"outgoing" fn:^BOOL(NSDictionary *data) {
            return NO;
        }];

        [primus emit:@"incoming::open"];

        [primus on:@"outgoing::data" listener:^{
            NSAssert(NO, @"listener should not fire");
        }];

        [primus write:@{ @"example": @"parameter" }];

        done();
    });

    it(@"throws an error if the plugin name is invalid", ^{
        PrimusConnectOptions *options = [[PrimusConnectOptions alloc] init];

        options.manual = YES;
        options.plugins = @{ @"example-plugin": NSStringFromClass(NSObject.class) };

        Primus *primusWithPlugins = [[Primus alloc] initWithURL:[NSURL URLWithString:@"http://127.0.0.1"] options:options];

        primusWithPlugins.transformer = mockObjectAndProtocol([NSObject class], @protocol(TransformerProtocol));

        expect(^{
            [primusWithPlugins open];
        }).to.raiseWithReason(@"NSInvalidArgumentException", @"Plugin should be a class whose instances conform to PluginProtocol");
    });

    it(@"throws an error if the plugin class is invalid", ^{
        PrimusConnectOptions *options = [[PrimusConnectOptions alloc] init];

        options.manual = YES;
        options.plugins = @{ @"example-plugin": NSObject.class };

        Primus *primusWithPlugins = [[Primus alloc] initWithURL:[NSURL URLWithString:@"http://127.0.0.1"] options:options];

        primusWithPlugins.transformer = mockObjectAndProtocol([NSObject class], @protocol(TransformerProtocol));

        expect(^{
            [primusWithPlugins open];
        }).to.raiseWithReason(@"NSInvalidArgumentException", @"Plugin should be a class whose instances conform to PluginProtocol");
    });
});

SpecEnd
