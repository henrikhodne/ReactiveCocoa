//
//  RACSubjectSpec.m
//  ReactiveCocoa
//
//  Created by Josh Abernathy on 6/24/12.
//  Copyright (c) 2012 GitHub, Inc. All rights reserved.
//

#import "RACSpecs.h"
#import "RACSubscriberExamples.h"

#import "EXTScope.h"
#import "RACSubject.h"
#import "RACBehaviorSubject.h"
#import "RACReplaySubject.h"

SpecBegin(RACSubject)

describe(@"RACSubject", ^{
	__block RACSubject *subject;
	__block NSMutableSet *values;

	__block BOOL success;
	__block NSError *error;

	beforeEach(^{
		values = [NSMutableSet set];

		subject = [RACSubject subject];
		success = YES;
		error = nil;

		[subject subscribeNext:^(id value) {
			[values addObject:value];
		} error:^(NSError *e) {
			error = e;
			success = NO;
		} completed:^{
			success = YES;
		}];
	});

	itShouldBehaveLike(RACSubscriberExamples, [^{ return subject; } copy], [^(NSSet *expectedValues) {
		expect(success).to.beTruthy();
		expect(error).to.beNil();
		expect(values).to.equal(expectedValues);
	} copy], nil);
});

describe(@"RACReplaySubject", ^{
	__block RACReplaySubject *subject = nil;

	describe(@"with a capacity of 1", ^{
		beforeEach(^{
			subject = [RACReplaySubject replaySubjectWithCapacity:1];
		});
		
		it(@"should send the last value", ^{
			id firstValue = @"blah";
			id secondValue = @"more blah";
			
			[subject sendNext:firstValue];
			[subject sendNext:secondValue];
			
			__block id valueReceived = nil;
			[subject subscribeNext:^(id x) {
				valueReceived = x;
			}];
			
			expect(valueReceived).to.equal(secondValue);
		});
		
		it(@"should send the last value to new subscribers after completion", ^{
			id firstValue = @"blah";
			id secondValue = @"more blah";
			
			__block id valueReceived = nil;
			__block NSUInteger nextsReceived = 0;
			
			[subject sendNext:firstValue];
			[subject sendNext:secondValue];
			
			expect(nextsReceived).to.equal(0);
			expect(valueReceived).to.beNil();
			
			[subject sendCompleted];
			
			[subject subscribeNext:^(id x) {
				valueReceived = x;
				nextsReceived++;
			}];
			
			expect(nextsReceived).to.equal(1);
			expect(valueReceived).to.equal(secondValue);
		});

		it(@"should not send any values to new subscribers if none were sent originally", ^{
			[subject sendCompleted];

			__block BOOL nextInvoked = NO;
			[subject subscribeNext:^(id x) {
				nextInvoked = YES;
			}];

			expect(nextInvoked).to.beFalsy();
		});

		it(@"should resend errors", ^{
			NSError *error = [NSError errorWithDomain:NSCocoaErrorDomain code:0 userInfo:nil];
			[subject sendError:error];

			__block BOOL errorSent = NO;
			[subject subscribeError:^(NSError *sentError) {
				expect(sentError).to.equal(error);
				errorSent = YES;
			}];

			expect(errorSent).to.beTruthy();
		});

		it(@"should resend nil errors", ^{
			[subject sendError:nil];

			__block BOOL errorSent = NO;
			[subject subscribeError:^(NSError *sentError) {
				expect(sentError).to.beNil();
				errorSent = YES;
			}];

			expect(errorSent).to.beTruthy();
		});
	});

	describe(@"with an unlimited capacity", ^{
		beforeEach(^{
			subject = [RACReplaySubject subject];
		});

		itShouldBehaveLike(RACSubscriberExamples, [^{ return subject; } copy], [^(NSSet *expectedValues) {
			NSMutableSet *values = [NSMutableSet set];

			// This subscription should synchronously dump all values already
			// received into 'values'.
			[subject subscribeNext:^(id value) {
				[values addObject:value];
			}];

			expect(values).to.equal(expectedValues);
		} copy], nil);
		
		it(@"should send both values to new subscribers after completion", ^{
			id firstValue = @"blah";
			id secondValue = @"more blah";
			
			[subject sendNext:firstValue];
			[subject sendNext:secondValue];
			[subject sendCompleted];
			
			__block BOOL completed = NO;
			NSMutableArray *valuesReceived = [NSMutableArray array];
			[subject subscribeNext:^(id x) {
				[valuesReceived addObject:x];
			} completed:^{
				completed = YES;
			}];
			
			expect(valuesReceived.count).to.equal(2);
			NSArray *expected = [NSArray arrayWithObjects:firstValue, secondValue, nil];
			expect(valuesReceived).to.equal(expected);
			expect(completed).to.beTruthy();
		});

		it(@"should send values in the same order live as when replaying", ^{
			NSUInteger count = 49317;

			// Just leak it, ain't no thang.
			__unsafe_unretained volatile id *values = (__unsafe_unretained id *)calloc(count, sizeof(*values));
			__block volatile int32_t nextIndex = 0;

			[subject subscribeNext:^(NSNumber *value) {
				int32_t indexPlusOne = OSAtomicIncrement32(&nextIndex);
				values[indexPlusOne - 1] = value;
			}];

			dispatch_queue_t queue = dispatch_queue_create("com.github.ReactiveCocoa.RACSubjectSpec", DISPATCH_QUEUE_CONCURRENT);
			@onExit {
				dispatch_release(queue);
			};

			dispatch_suspend(queue);
			
			for (NSUInteger i = 0; i < count; i++) {
				dispatch_async(queue, ^{
					[subject sendNext:@(i)];
				});
			}

			dispatch_resume(queue);
			dispatch_barrier_sync(queue, ^{
				[subject sendCompleted];
			});

			OSMemoryBarrier();

			NSArray *liveValues = [NSArray arrayWithObjects:(id *)values count:(NSUInteger)nextIndex];
			expect(liveValues.count).to.equal(count);
			
			NSArray *replayedValues = subject.toArray;
			expect(replayedValues.count).to.equal(count);

			// It should return the same ordering for multiple invocations too.
			expect(replayedValues).to.equal(subject.toArray);

			[replayedValues enumerateObjectsUsingBlock:^(id value, NSUInteger index, BOOL *stop) {
				expect(liveValues[index]).to.equal(value);
			}];
		});
	});
});

SpecEnd
