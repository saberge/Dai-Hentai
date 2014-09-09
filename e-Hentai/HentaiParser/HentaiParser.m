//
//  HentaiParser.m
//  TEST_2014_9_2
//
//  Created by 啟倫 陳 on 2014/9/2.
//  Copyright (c) 2014年 ChilunChen. All rights reserved.
//

#import "HentaiParser.h"

#import <objc/runtime.h>

#define baseListURL @"http://g.e-hentai.org/?page=%d"
#define hentaiAPIURL @"http://g.e-hentai.org/api.php"

//Fillter 全開
//http://g.e-hentai.org/?f_doujinshi=1&f_manga=1&f_artistcg=1&f_gamecg=1&f_western=1&f_non-h=1&f_imageset=1&f_cosplay=1&f_asianporn=1&f_misc=1&f_search=Search+Keywords&f_apply=Apply+Filter

#define doujinshiFilter    @"f_doujinshi=1"
#define mangaFilter        @"f_manga=1"
#define artistcgFilter     @"f_artistcg=1"
#define gamecgFilter       @"f_gamecg=1"
#define westernFilter      @"f_western=1"
#define nonhFilter         @"f_non-h=1"
#define imagesetFilter     @"f_imageset=1"
#define cosplayFilter      @"f_cosplay=1"
#define asianpornFilter    @"f_asianporn=1"
#define miscFilter         @"f_misc=1"
#define searchKeywords     @"f_search=%@"
#define applyFilter        @"f_apply=Apply+Filter"


@implementation NSMutableArray (HENTAI)

+ (NSMutableArray *)hentai_preAllocWithCapacity:(NSUInteger)capacity {
	NSMutableArray *returnArray = [NSMutableArray array];
	for (NSUInteger i = 0; i < capacity; i++) {
		[returnArray addObject:[NSNull null]];
	}
	return returnArray;
}

@end


@implementation HentaiParser


#pragma mark - class method

+ (void)requestListAtIndex:(NSUInteger)index completion:(void (^)(HentaiParserStatus status, NSArray *listArray))completion {
	NSString *urlString = [NSString stringWithFormat:baseListURL, index];
	NSURLRequest *urlRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:urlString]];
	[NSURLConnection sendAsynchronousRequest:urlRequest queue:[NSOperationQueue mainQueue] completionHandler: ^(NSURLResponse *response, NSData *data, NSError *connectionError) {
	    if (connectionError) {
	        completion(HentaiParserStatusFail, nil);
		}
	    else {
	        //這段是從 e hentai 的網頁 parse 列表
	        TFHpple *xpathParser = [[TFHpple alloc] initWithHTMLData:data];
	        NSArray *photoURL = [xpathParser searchWithXPathQuery:@"//div [@class='it5']//a"];
            
	        NSMutableArray *returnArray = [NSMutableArray array];
	        NSMutableArray *urlStringArray = [NSMutableArray array];
            
	        for (TFHppleElement * eachTitleWithURL in photoURL) {
	            [urlStringArray addObject:[eachTitleWithURL attributes][@"href"]];
	            [returnArray addObject:[NSMutableDictionary dictionaryWithDictionary:@{ @"url": [eachTitleWithURL attributes][@"href"] }]];
			}
            
	        //這段是從 e hentai 的 api 抓資料
	        [self requestGDataAPIWithURLStrings:urlStringArray completion: ^(HentaiParserStatus status, NSArray *gMetaData) {
	            if (status) {
	                for (NSUInteger i = 0; i < [gMetaData count]; i++) {
	                    NSMutableDictionary *eachDictionary = returnArray[i];
	                    NSDictionary *metaData = gMetaData[i];
	                    eachDictionary[@"thumb"] = metaData[@"thumb"];
	                    eachDictionary[@"title"] = metaData[@"title"];
	                    eachDictionary[@"title_jpn"] = metaData[@"title_jpn"];
	                    eachDictionary[@"category"] = metaData[@"category"];
	                    eachDictionary[@"uploader"] = metaData[@"uploader"];
	                    eachDictionary[@"filecount"] = metaData[@"filecount"];
	                    eachDictionary[@"filesize"] = [NSByteCountFormatter stringFromByteCount:[metaData[@"filesize"] floatValue] countStyle:NSByteCountFormatterCountStyleFile];
	                    eachDictionary[@"rating"] = metaData[@"rating"];
	                    eachDictionary[@"posted"] = [self dateStringFrom1970:[metaData[@"posted"] doubleValue]];
					}
	                completion(HentaiParserStatusSuccess, returnArray);
				}
	            else {
	                completion(HentaiParserStatusFail, nil);
				}
			}];
		}
	}];
}

+ (void)requestImagesAtURL:(NSString *)urlString atIndex:(NSUInteger)index completion:(void (^)(HentaiParserStatus status, NSArray *images))completion {
	//網址的範例
	//http://g.e-hentai.org/g/735601/35fe0802c8/?p=2
	NSString *newURLString = [NSString stringWithFormat:@"%@?p=%d", urlString, index];
	NSURL *newURL = [NSURL URLWithString:newURLString];
	[NSURLConnection sendAsynchronousRequest:[NSURLRequest requestWithURL:newURL] queue:[NSOperationQueue mainQueue] completionHandler: ^(NSURLResponse *response, NSData *data, NSError *connectionError) {
	    if (connectionError) {
	        completion(HentaiParserStatusFail, nil);
		}
	    else {
	        TFHpple *xpathParser = [[TFHpple alloc] initWithHTMLData:data];
	        NSArray *pageURL  = [xpathParser searchWithXPathQuery:@"//div [@class='gdtm']//a"];
	        NSMutableArray *returnArray = [NSMutableArray hentai_preAllocWithCapacity:[pageURL count]];
            
	        dispatch_queue_t hentaiQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0);
	        dispatch_group_t hentaiGroup = dispatch_group_create();
            
	        for (NSUInteger i = 0; i < [pageURL count]; i++) {
	            TFHppleElement *e = pageURL[i];
	            dispatch_group_async(hentaiGroup, hentaiQueue, ^{
	                dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
	                [self requestCurrentImage:[NSURL URLWithString:[e attributes][@"href"]] atIndex:i completion: ^(HentaiParserStatus status, NSString *imageString, NSUInteger index) {
	                    if (status) {
	                        returnArray[index] = imageString;
						}
	                    dispatch_semaphore_signal(semaphore);
					}];
	                dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
				});
			}
	        dispatch_group_wait(hentaiGroup, DISPATCH_TIME_FOREVER);
	        completion(HentaiParserStatusSuccess, returnArray);
		}
	}];
}

#pragma mark - private

+ (NSString *)dateStringFrom1970:(NSTimeInterval)date1970 {
	NSDateFormatter *dateFormatter = [NSDateFormatter new];
	[dateFormatter setDateStyle:NSDateFormatterMediumStyle];
	[dateFormatter setTimeStyle:NSDateFormatterShortStyle];
	[dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm"];
	return [dateFormatter stringFromDate:[NSDate date]];
}

+ (void)requestGDataAPIWithURLStrings:(NSArray *)urlStringArray completion:(void (^)(HentaiParserStatus status, NSArray *gMetaData))completion {
	//http://g.e-hentai.org/g/618395/0439fa3666/
	//                          -3        -2       -1
	NSMutableArray *idArray = [NSMutableArray array];
	for (NSString *eachURLString in urlStringArray) {
		NSArray *splitStrings = [eachURLString componentsSeparatedByString:@"/"];
		NSUInteger splitCount = [splitStrings count];
		[idArray addObject:@[splitStrings[splitCount - 3], splitStrings[splitCount - 2]]];
	}
    
	// post 給 e hentai api 的固定規則
	NSDictionary *jsonDictionary = @{ @"method": @"gdata", @"gidlist":idArray };
	NSMutableURLRequest *request = [self makeJsonPostRequest:jsonDictionary];
    
	[NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue mainQueue] completionHandler: ^(NSURLResponse *response, NSData *data, NSError *connectionError) {
	    if (connectionError) {
	        completion(HentaiParserStatusFail, nil);
		}
	    else {
	        NSDictionary *responseResult = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
	        completion(HentaiParserStatusSuccess, responseResult[@"gmetadata"]);
		}
	}];
}

+ (NSMutableURLRequest *)makeJsonPostRequest:(NSDictionary *)jsonDictionary {
	NSData *jsonData = [NSJSONSerialization dataWithJSONObject:jsonDictionary options:NSJSONWritingPrettyPrinted error:nil];
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[hentaiAPIURL stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]]];
	[request setHTTPMethod:@"POST"];
	[request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
	[request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
	[request setValue:[NSString stringWithFormat:@"%lu", (unsigned long)[jsonData length]] forHTTPHeaderField:@"Content-Length"];
	[request setHTTPBody:jsonData];
	return request;
}

+ (void)requestCurrentImage:(NSURL *)url atIndex:(NSUInteger)index completion:(void (^)(HentaiParserStatus status, NSString *imageString, NSUInteger index))completion {
	[NSURLConnection sendAsynchronousRequest:[NSURLRequest requestWithURL:url] queue:[self hentaiOperationQueue] completionHandler: ^(NSURLResponse *response, NSData *data, NSError *connectionError) {
	    if (connectionError) {
	        completion(HentaiParserStatusFail, nil, -1);
		}
	    else {
	        TFHpple *xpathParser = [[TFHpple alloc] initWithHTMLData:data];
	        NSArray *pageURL  = [xpathParser searchWithXPathQuery:@"//div [@id='i3']//img"];
	        for (TFHppleElement * e in pageURL) {
	            completion(HentaiParserStatusSuccess, [e attributes][@"src"], index);
	            break;
			}
		}
	}];
}

+ (NSOperationQueue *)hentaiOperationQueue {
	if (!objc_getAssociatedObject(self, _cmd)) {
		objc_setAssociatedObject(self, _cmd, [NSOperationQueue new], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	}
	return objc_getAssociatedObject(self, _cmd);
}

@end
