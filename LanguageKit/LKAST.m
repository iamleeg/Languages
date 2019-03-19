#import "LKAST.h"
#import "LKDeclRef.h"
#import "LKModule.h"
#import <objc/runtime.h>

static Class DeclRefClass;
static Class ModuleClass;

static NSMutableDictionary *ASTSubclassAndCategoryNodes = nil;

@implementation LKAST

+ (NSMutableDictionary *) code
{
	if (ASTSubclassAndCategoryNodes == nil)
	{
		ASTSubclassAndCategoryNodes = [[NSMutableDictionary alloc] init];
	}
	return ASTSubclassAndCategoryNodes;
}

+ (void) initialize
{
	DeclRefClass = [LKDeclRef class];
	ModuleClass = [LKModule class];
}

- (LKModule*) module
{
	__unsafe_unretained LKAST *module = self;
	while (nil != module && ModuleClass != object_getClass(module))
	{
		module = module->parent;
	}
	return (LKModule*)module;
}


- (id) initWithSymbolTable:(LKSymbolTable*)aSymbolTable
{
	if(nil == (self = [self init]))
	{
		return nil;
	}
	symbols = aSymbolTable;
	return self;
}
- (void) print
{
	printf("%s", [[self description] UTF8String]);
}
- (void) inheritSymbolTable:(LKSymbolTable*)aSymbolTable
{
	symbols = aSymbolTable;
}
- (LKAST*) parent;
{
	return parent;
}
- (void) setParent:(LKAST*)aNode
{
	[self inheritSymbolTable: [aNode symbols]];
	parent = aNode;
}
- (void) setBracketed:(BOOL)aFlag
{
	isBracket = aFlag;
}
- (BOOL) isBracketed
{
	return isBracket;
}
- (BOOL) check
{
	// Subclasses should implement this.
	[self doesNotRecognizeSelector:_cmd];
	// Not reached.
	return NO;
}
- (BOOL)checkWithErrorReporter: (id<LKCompilerDelegate>)errorReporter
{
	NSMutableDictionary *dict = [[NSThread currentThread] threadDictionary];
	id old = [dict objectForKey: @"LKCompilerDelegate"];
	[dict setObject: errorReporter forKey: @"LKCompilerDelegate"];
	BOOL success = [self check];
	[dict setValue: old forKey: @"LKCompilerDelegate"];

	return success;
}
- (void*) compileWithGenerator: (id<LKCodeGenerator>)aGenerator
{
	NSLog(@"Compiling %@ ...", self);
	[NSException raise:@"NotImplementedException"
	            format:@"Code generation not yet implemented for %@", 
		[self class]];
	return NULL;
}
- (LKSymbolTable*) symbols
{
	return symbols;
}
- (BOOL) isComment
{
	return NO;
}
- (BOOL) isBranch
{
	return NO;
}
- (NSUInteger) sourceLine
{
    // get the lines that define this node in its source
    NSRange lineRange = [[[self module] sourceText] lineRangeForRange:_sourceRange];
    // get the first line in that range
    __block NSString *firstLine = nil;
    [[[[self module] sourceText] substringWithRange:lineRange] enumerateLinesUsingBlock:^(NSString * _Nonnull line, BOOL * _Nonnull stop) {
        firstLine = line;
        *stop = YES;
    }];
    /* find out which line that is
     * (Adding one, because IDEs use one-indexed line numbers)
     */
    __block NSUInteger correctLine = 1;
    [[[self module] sourceText] enumerateLinesUsingBlock:^(NSString * _Nonnull line, BOOL * _Nonnull stop) {
        if ([line isEqualToString:firstLine]) {
            *stop = YES;
        } else {
            correctLine++;
        }
    }];
    // if we went past the end then we didn't find it
    if (correctLine > [[[[self module] sourceText] componentsSeparatedByCharactersInSet:
                        [NSCharacterSet newlineCharacterSet]] count]) {
        return NSNotFound;
    }
    return correctLine;
}

@end
@implementation LKAST (Visitor)
- (void) visitWithVisitor:(id<LKASTVisitor>)aVisitor
{
	// AST nodes with no children do nothing.
}
- (void) visitArray:(NSMutableArray*)anArray
        withVisitor:(id<LKASTVisitor>)aVisitor
{
	unsigned int count = [anArray count];
	NSMutableIndexSet *remove = [NSMutableIndexSet new];
	for (int i=0 ; i<count ; i++)
	{
		LKAST *old = [anArray objectAtIndex:i];
		LKAST *new = [aVisitor visitASTNode:old];
		if (new != old)
		{
			if (nil == new)
			{
				[remove addIndex: i];
			}
			else
			{
				[anArray replaceObjectAtIndex:i withObject:new];
			}
		}
		[new visitWithVisitor:aVisitor];
	}
	[anArray removeObjectsAtIndexes: remove];
}
@end

@implementation LKAST (Executing)

- (BOOL)inheritsContext
{
    return YES;
}

- (LKInterpreterContext *)freshContextWithReceiver: (id)receiver
                                         arguments: (const __autoreleasing id *)arguments
                                             count: (int)count
{
    // subclass responsibility
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

- (id)executeWithReceiver:(id)receiver
                     args:(const __autoreleasing id *)args
                    count:(int)count
                inContext:(LKInterpreterContext *)context
{
    // subclass responsibility
    [self doesNotRecognizeSelector:_cmd];
}

@end
