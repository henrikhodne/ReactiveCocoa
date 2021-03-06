//
//  RACStreamExamples.m
//  ReactiveCocoa
//
//  Created by Justin Spahr-Summers on 2012-11-01.
//  Copyright (c) 2012 GitHub, Inc. All rights reserved.
//

#import "RACSpecs.h"
#import "RACStreamExamples.h"

#import "RACStream.h"
#import "RACUnit.h"
#import "RACTuple.h"

NSString * const RACStreamExamples = @"RACStreamExamples";
NSString * const RACStreamExamplesClass = @"RACStreamExamplesClass";
NSString * const RACStreamExamplesInfiniteStream = @"RACStreamExamplesInfiniteStream";
NSString * const RACStreamExamplesVerifyValuesBlock = @"RACStreamExamplesVerifyValuesBlock";

SharedExampleGroupsBegin(RACStreamExamples)

sharedExamplesFor(RACStreamExamples, ^(NSDictionary *data) {
	Class streamClass = data[RACStreamExamplesClass];
	void (^verifyValues)(id<RACStream>, NSArray *) = data[RACStreamExamplesVerifyValuesBlock];
	id<RACStream> infiniteStream = data[RACStreamExamplesInfiniteStream];

	__block id<RACStream> (^streamWithValues)(NSArray *);
	
	before(^{
		streamWithValues = [^(NSArray *values) {
			id<RACStream> stream = [streamClass empty];

			for (id value in values) {
				stream = [stream concat:[streamClass return:value]];
			}

			return stream;
		} copy];
	});

	it(@"should return an empty stream", ^{
		id<RACStream> stream = [streamClass empty];
		verifyValues(stream, @[]);
	});

	it(@"should lift a value into a stream", ^{
		id<RACStream> stream = [streamClass return:RACUnit.defaultUnit];
		verifyValues(stream, @[ RACUnit.defaultUnit ]);
	});

	describe(@"-concat:", ^{
		it(@"should concatenate two streams", ^{
			id<RACStream> stream = [[streamClass return:@0] concat:[streamClass return:@1]];
			verifyValues(stream, @[ @0, @1 ]);
		});

		it(@"should concatenate three streams", ^{
			id<RACStream> stream = [[[streamClass return:@0] concat:[streamClass return:@1]] concat:[streamClass return:@2]];
			verifyValues(stream, @[ @0, @1, @2 ]);
		});

		it(@"should concatenate around an empty stream", ^{
			id<RACStream> stream = [[[streamClass return:@0] concat:[streamClass empty]] concat:[streamClass return:@2]];
			verifyValues(stream, @[ @0, @2 ]);
		});
	});

	it(@"should flatten", ^{
		id<RACStream> stream = [[streamClass return:[streamClass return:RACUnit.defaultUnit]] flatten];
		verifyValues(stream, @[ RACUnit.defaultUnit ]);
	});

	describe(@"-bind:", ^{
		it(@"should return the result of binding a single value", ^{
			id<RACStream> stream = [[streamClass return:@0] bind:^{
				return ^(NSNumber *value, BOOL *stop) {
					NSNumber *newValue = @(value.integerValue + 1);
					return [streamClass return:newValue];
				};
			}];

			verifyValues(stream, @[ @1 ]);
		});

		it(@"should concatenate the result of binding multiple values", ^{
			id<RACStream> baseStream = streamWithValues(@[ @0, @1 ]);
			id<RACStream> stream = [baseStream bind:^{
				return ^(NSNumber *value, BOOL *stop) {
					NSNumber *newValue = @(value.integerValue + 1);
					return [streamClass return:newValue];
				};
			}];

			verifyValues(stream, @[ @1, @2 ]);
		});

		it(@"should concatenate with an empty result from binding a value", ^{
			id<RACStream> baseStream = streamWithValues(@[ @0, @1, @2 ]);
			id<RACStream> stream = [baseStream bind:^{
				return ^(NSNumber *value, BOOL *stop) {
					if (value.integerValue == 1) return [streamClass empty];

					NSNumber *newValue = @(value.integerValue + 1);
					return [streamClass return:newValue];
				};
			}];

			verifyValues(stream, @[ @1, @3 ]);
		});

		it(@"should terminate immediately when returning nil", ^{
			id<RACStream> stream = [infiniteStream bind:^{
				return ^ id (id _, BOOL *stop) {
					return nil;
				};
			}];

			verifyValues(stream, @[]);
		});

		it(@"should terminate after one value when setting 'stop'", ^{
			id<RACStream> stream = [infiniteStream bind:^{
				return ^ id (id value, BOOL *stop) {
					*stop = YES;
					return [streamClass return:value];
				};
			}];

			verifyValues(stream, @[ RACUnit.defaultUnit ]);
		});

		it(@"should terminate immediately when returning nil and setting 'stop'", ^{
			id<RACStream> stream = [infiniteStream bind:^{
				return ^ id (id _, BOOL *stop) {
					*stop = YES;
					return nil;
				};
			}];

			verifyValues(stream, @[]);
		});

		it(@"should be restartable even with block state", ^{
			NSArray *values = @[ @0, @1, @2 ];
			id<RACStream> baseStream = streamWithValues(values);

			id<RACStream> countingStream = [baseStream bind:^{
				__block NSUInteger counter = 0;

				return ^(id x, BOOL *stop) {
					return [streamClass return:@(counter++)];
				};
			}];

			verifyValues(countingStream, @[ @0, @1, @2 ]);
			verifyValues(countingStream, @[ @0, @1, @2 ]);
		});

		it(@"should be interleavable even with block state", ^{
			NSArray *values = @[ @0, @1, @2 ];
			id<RACStream> baseStream = streamWithValues(values);

			id<RACStream> countingStream = [baseStream bind:^{
				__block NSUInteger counter = 0;

				return ^(id x, BOOL *stop) {
					return [streamClass return:@(counter++)];
				};
			}];

			// Just so +zip:reduce: thinks this is a unique stream.
			id<RACStream> anotherStream = [[streamClass empty] concat:countingStream];

			id<RACStream> zipped = [streamClass zip:@[ countingStream, anotherStream ] reduce:^(NSNumber *v1, NSNumber *v2) {
				return @(v1.integerValue + v2.integerValue);
			}];

			verifyValues(zipped, @[ @0, @2, @4 ]);
		});
	});

	describe(@"-flattenMap:", ^{
		it(@"should return a single mapped result", ^{
			id<RACStream> stream = [[streamClass return:@0] flattenMap:^(NSNumber *value) {
				NSNumber *newValue = @(value.integerValue + 1);
				return [streamClass return:newValue];
			}];

			verifyValues(stream, @[ @1 ]);
		});

		it(@"should concatenate the results of mapping multiple values", ^{
			id<RACStream> baseStream = streamWithValues(@[ @0, @1 ]);
			id<RACStream> stream = [baseStream flattenMap:^(NSNumber *value) {
				NSNumber *newValue = @(value.integerValue + 1);
				return [streamClass return:newValue];
			}];

			verifyValues(stream, @[ @1, @2 ]);
		});

		it(@"should concatenate with an empty result from mapping a value", ^{
			id<RACStream> baseStream = streamWithValues(@[ @0, @1, @2 ]);
			id<RACStream> stream = [baseStream flattenMap:^(NSNumber *value) {
				if (value.integerValue == 1) return [streamClass empty];

				NSNumber *newValue = @(value.integerValue + 1);
				return [streamClass return:newValue];
			}];

			verifyValues(stream, @[ @1, @3 ]);
		});
	});

	describe(@"-sequenceMany:", ^{
		it(@"should return the result of sequencing a single value", ^{
			id<RACStream> stream = [[streamClass return:@0] sequenceMany:^{
				return [streamClass return:@10];
			}];

			verifyValues(stream, @[ @10 ]);
		});

		it(@"should concatenate the result of sequencing multiple values", ^{
			id<RACStream> baseStream = streamWithValues(@[ @0, @1 ]);

			__block NSUInteger value = 10;
			id<RACStream> stream = [baseStream sequenceMany:^{
				return [streamClass return:@(value++)];
			}];

			verifyValues(stream, @[ @10, @11 ]);
		});
	});

	it(@"should map", ^{
		id<RACStream> baseStream = streamWithValues(@[ @0, @1, @2 ]);
		id<RACStream> stream = [baseStream map:^(NSNumber *value) {
			return @(value.integerValue + 1);
		}];

		verifyValues(stream, @[ @1, @2, @3 ]);
	});

	it(@"should map and replace", ^{
		id<RACStream> baseStream = streamWithValues(@[ @0, @1, @2 ]);
		id<RACStream> stream = [baseStream mapReplace:RACUnit.defaultUnit];

		verifyValues(stream, @[ RACUnit.defaultUnit, RACUnit.defaultUnit, RACUnit.defaultUnit ]);
	});

	it(@"should filter", ^{
		id<RACStream> baseStream = streamWithValues(@[ @0, @1, @2, @3, @4, @5, @6 ]);
		id<RACStream> stream = [baseStream filter:^ BOOL (NSNumber *value) {
			return value.integerValue % 2 == 0;
		}];

		verifyValues(stream, @[ @0, @2, @4, @6 ]);
	});

	it(@"should start with a value", ^{
		id<RACStream> stream = [[streamClass return:@1] startWith:@0];
		verifyValues(stream, @[ @0, @1 ]);
	});

	describe(@"-skip:", ^{
		__block NSArray *values;
		__block id<RACStream> stream;

		before(^{
			values = @[ @0, @1, @2 ];
			stream = streamWithValues(values);
		});

		it(@"should skip any valid number of values", ^{
			for (NSUInteger i = 0; i < values.count; i++) {
				verifyValues([stream skip:i], [values subarrayWithRange:NSMakeRange(i, values.count - i)]);
			}
		});

		it(@"should return an empty stream when skipping too many values", ^{
			verifyValues([stream skip:4], @[]);
		});
	});

	describe(@"-take:", ^{
		describe(@"with three values", ^{
			__block NSArray *values;
			__block id<RACStream> stream;

			before(^{
				values = @[ @0, @1, @2 ];
				stream = streamWithValues(values);
			});

			it(@"should take any valid number of values", ^{
				for (NSUInteger i = 0; i < values.count; i++) {
					verifyValues([stream take:i], [values subarrayWithRange:NSMakeRange(0, i)]);
				}
			});

			it(@"should return the same stream when taking too many values", ^{
				verifyValues([stream take:4], values);
			});
		});

		it(@"should take and terminate from an infinite stream", ^{
			verifyValues([infiniteStream take:0], @[]);
			verifyValues([infiniteStream take:1], @[ RACUnit.defaultUnit ]);
			verifyValues([infiniteStream take:2], @[ RACUnit.defaultUnit, RACUnit.defaultUnit ]);
		});

		it(@"should take and terminate from a single-item stream", ^{
			NSArray *values = @[ RACUnit.defaultUnit ];
			id<RACStream> stream = streamWithValues(values);
			verifyValues([stream take:1], values);
		});
	});
  
	describe(@"zip stream creation methods", ^{
		__block NSArray *threeStreams;
		__block NSArray *threeTuples;
		
		before(^{
			NSArray *values = @[ @1, @2, @3 ];
			id<RACStream> streamOne = streamWithValues(values);
			id<RACStream> streamTwo = streamWithValues(values);
			id<RACStream> streamThree = streamWithValues(values);
			threeStreams = @[ streamOne, streamTwo, streamThree ];
			RACTuple *firstTuple = [RACTuple tupleWithObjectsFromArray:@[ @1, @1, @1 ]];
			RACTuple *secondTuple = [RACTuple tupleWithObjectsFromArray:@[ @2, @2, @2 ]];
			RACTuple *thirdTuple = [RACTuple tupleWithObjectsFromArray:@[ @3, @3, @3 ]];
			threeTuples = @[ firstTuple, secondTuple, thirdTuple ];
		});
		
		describe(@"+zip:reduce", ^{
			it(@"should reduce values if a block is given", ^{
				id<RACStream> stream = [streamClass zip:threeStreams reduce:^ NSString * (id x, id y, id z) {
					return [NSString stringWithFormat:@"%@%@%@", x, y, z];
				}];
				verifyValues(stream, @[ @"111", @"222", @"333" ]);
			});
			
			it(@"should make a stream of tuples if no block is given", ^{
				id<RACStream> stream = [streamClass zip:threeStreams reduce:nil];
				verifyValues(stream, threeTuples);
			});
			
			it(@"should truncate streams", ^{
				id<RACStream> shortStream = streamWithValues(@[ @1, @2 ]);
				NSArray *streams = [threeStreams arrayByAddingObject:shortStream];
				id<RACStream> stream = [streamClass zip:streams reduce:^ NSString * (id w, id x, id y, id z) {
					return [NSString stringWithFormat:@"%@%@%@%@", w, x, y, z];
				}];
				verifyValues(stream, @[ @"1111", @"2222" ]);
			});
			
			it(@"should work on infinite streams", ^{
				NSArray *streams = [threeStreams arrayByAddingObject:infiniteStream];
				id<RACStream> stream = [streamClass zip:streams reduce:^ NSString * (id w, id x, id y, id z) {
					return [NSString stringWithFormat:@"%@%@%@", w, x, y];
				}];
				verifyValues(stream, @[ @"111", @"222", @"333" ]);
			});
		});
		
		describe(@"+zip:", ^{
			it(@"should make a stream of tuples out of an array of streams", ^{
				id<RACStream> stream = [streamClass zip:threeStreams];
				verifyValues(stream, threeTuples);
			});
		});
	});

	it(@"should scan", ^{
		id<RACStream> stream = streamWithValues(@[ @1, @2, @3, @4 ]);
		id<RACStream> scanned = [stream scanWithStart:@0 combine:^(NSNumber *running, NSNumber *next) {
			return @(running.integerValue + next.integerValue);
		}];

		verifyValues(scanned, @[ @1, @3, @6, @10 ]);
	});

	describe(@"taking with a predicate", ^{
		NSArray *values = @[ @0, @1, @2, @3, @0, @2, @4 ];

		__block id<RACStream> stream;

		before(^{
			stream = streamWithValues(values);
		});

		it(@"should take until a predicate is true", ^{
			id<RACStream> taken = [stream takeUntilBlock:^ BOOL (NSNumber *x) {
				return x.integerValue >= 3;
			}];

			verifyValues(taken, @[ @0, @1, @2 ]);
		});

		it(@"should take while a predicate is true", ^{
			id<RACStream> taken = [stream takeWhileBlock:^ BOOL (NSNumber *x) {
				return x.integerValue <= 1;
			}];

			verifyValues(taken, @[ @0, @1 ]);
		});

		it(@"should take a full stream", ^{
			id<RACStream> taken = [stream takeWhileBlock:^ BOOL (NSNumber *x) {
				return x.integerValue <= 10;
			}];

			verifyValues(taken, values);
		});

		it(@"should return an empty stream", ^{
			id<RACStream> taken = [stream takeWhileBlock:^ BOOL (NSNumber *x) {
				return x.integerValue < 0;
			}];

			verifyValues(taken, @[]);
		});

		it(@"should terminate an infinite stream", ^{
			id<RACStream> infiniteCounter = [infiniteStream scanWithStart:@0 combine:^(NSNumber *running, id _) {
				return @(running.unsignedIntegerValue + 1);
			}];

			id<RACStream> taken = [infiniteCounter takeWhileBlock:^ BOOL (NSNumber *x) {
				return x.integerValue <= 5;
			}];

			verifyValues(taken, @[ @1, @2, @3, @4, @5 ]);
		});
	});

	describe(@"skipping with a predicate", ^{
		NSArray *values = @[ @0, @1, @2, @3, @0, @2, @4 ];

		__block id<RACStream> stream;

		before(^{
			stream = streamWithValues(values);
		});

		it(@"should skip until a predicate is true", ^{
			id<RACStream> taken = [stream skipUntilBlock:^ BOOL (NSNumber *x) {
				return x.integerValue >= 3;
			}];

			verifyValues(taken, @[ @3, @0, @2, @4 ]);
		});

		it(@"should skip while a predicate is true", ^{
			id<RACStream> taken = [stream skipWhileBlock:^ BOOL (NSNumber *x) {
				return x.integerValue <= 1;
			}];

			verifyValues(taken, @[ @2, @3, @0, @2, @4 ]);
		});

		it(@"should skip a full stream", ^{
			id<RACStream> taken = [stream skipWhileBlock:^ BOOL (NSNumber *x) {
				return x.integerValue <= 10;
			}];

			verifyValues(taken, @[]);
		});

		it(@"should finish skipping immediately", ^{
			id<RACStream> taken = [stream skipWhileBlock:^ BOOL (NSNumber *x) {
				return x.integerValue < 0;
			}];

			verifyValues(taken, values);
		});
	});
});

SharedExampleGroupsEnd
