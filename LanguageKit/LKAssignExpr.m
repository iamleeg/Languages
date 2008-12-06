#import "LKAssignExpr.h"
#import "LKDeclRef.h"

static char *RetainTypes;
static char *ReleaseTypes;
@interface NSMethodSignature (TypeEncodings)
- (const char*) _methodTypes;
@end
@implementation NSMethodSignature (TypeEncodings)
- (const char*) _methodTypes
{
	return _methodTypes;
}
@end
@implementation LKAssignExpr
+ (void) initialize
{
	RetainTypes = 
		strdup([[NSObject instanceMethodSignatureForSelector:@selector(retain)]
		        _methodTypes]);
	ReleaseTypes = 
		strdup([[NSObject instanceMethodSignatureForSelector:@selector(release)]
		        _methodTypes]);
}
+ (id) assignWithTarget:(LKDeclRef*)aTarget expr:(LKAST*)expression
{
	return [[[self alloc] initWithTarget:aTarget expr:expression] autorelease];
}
- (id) initWithTarget:(LKDeclRef*)aTarget expr:(LKAST*)expression
{
	SELFINIT;
	ASSIGN(target, aTarget);
	ASSIGN(expr, expression);
	return self;
}
- (void) check
{
	[expr setParent:self];
	[target setParent:self];
	[target check];
	[expr check];
}
- (NSString*) description
{
	return [NSString stringWithFormat:@"%@ := %@", target->symbol, expr];
}
- (void*) compileWith:(id<LKCodeGenerator>)aGenerator
{
	void * rval = [expr compileWith:aGenerator];
	switch([symbols scopeOfSymbol:target->symbol])
	{
		case local:
			[aGenerator storeValue:rval
			        inLocalAtIndex:[symbols offsetOfLocal:target->symbol]];
			break;
		case object:
		{
			// TODO: Move this to -check
			if ([[symbols typeOfSymbol:target->symbol] characterAtIndex:0] != '@')
			{
				[NSException raise:@"InvalidAssignmentException"
				            format:@"Can not yet generate code for assignment"];
			}
			// Assign
			[aGenerator storeValue:rval
			                ofType:@"@"
			              atOffset:[symbols offsetOfIVar:target->symbol]
			            fromObject:[aGenerator loadSelf]];
			break;
		}
		case class:
		{
			[aGenerator storeValue:rval inClassVariable:target->symbol];
			break;
		}
		case external:
		{
			LKExternalSymbolScope scope = [(LKBlockSymbolTable*)symbols
				scopeOfExternal:target->symbol];
			switch([scope.scope scopeOfSymbol:target->symbol])
			{
				case argument:
					NSAssert(NO,
						@"Storing values in arguments is not currently supported");
				case local:
					[aGenerator storeValue:rval
					        inLocalAtIndex:[scope.scope offsetOfLocal:target->symbol]
			           lexicalScopeAtDepth:scope.depth];
					break;
				case object:
				{
					// TODO: Move this to -check
					if ([[scope.scope typeOfSymbol:target->symbol] characterAtIndex:0] != '@')
					{
						[NSException raise:@"InvalidAssignmentException"
									format:@"Can not yet generate code for assignment"];
					}
					// Assign
					[aGenerator storeValue:rval
									ofType:@"@"
								  atOffset:[scope.scope offsetOfIVar:target->symbol]
								fromObject:[aGenerator loadSelf]];
					break;
				}

				default:
					NSAssert(NO, 
						@"External symbols must be local or arguments.");
			}	
			break;
		}
		default:
			NSLog(@"Scope of %@ is %d.", target->symbol, [symbols scopeOfSymbol:target->symbol]);
			// Throws exception
			[super compileWith:aGenerator];
	}
	// Assignments aren't expressions in Smalltalk, but they might be in some
	// other language that wants to use this code and it doesn't cost more than
	// returning NULL.
	return rval;
}
@end