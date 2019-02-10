/*
Parser definition file.  This uses LEMON (from the SQLite project), a public
domain parser generator, to produce an Objective-C parser.
*/
%include {
#include <assert.h>
#import <EtoileFoundation/EtoileFoundation.h>
#import <LanguageKit/LanguageKit.h>
#import <LanguageKit/LKToken.h>
#import "SmalltalkParser.h"

static NSDictionary *DeclRefClasses;

static LKDeclRef *RefForSymbol(NSString *aSymbol)
{
	if (nil == DeclRefClasses)
	{
		DeclRefClasses = [[NSDictionary dictionaryWithObjectsAndKeys:
			[LKSelfRef class], @"self",
			[LKSuperRef class], @"super",
			[LKBlockSelfRef class], @"blockContext",
			[LKNilRef class], @"nil",
			[LKNilRef class], @"Nil",
			nil] retain];
	}
	Class cls = [DeclRefClasses objectForKey: aSymbol];
	LKDeclRef *ref = nil;
	if (nil == cls)
	{
		cls = [LKDeclRef class];
	}
	return [cls referenceWithSymbol: aSymbol];
}

}
%name SmalltalkParse
%token_prefix TOKEN_
%token_type {id}
%extra_argument {SmalltalkParser *p}
%left PLUS MINUS STAR SLASH EQ LT GT COMMA.
%left WORD.

file ::= module(M).
{
	[p setAST:M];
}
file ::= method(M).
{
	[p setAST:M];
}
file ::= .

module(M) ::= module(O) LT LT pragma_dict(P) GT GT.
{
	[O addPragmas:P];
	M = O;
}
module(M) ::= LT LT pragma_dict(P) GT GT.
{
	M = [LKModule module];
	[M addPragmas:P];
}
module(M) ::= module(O) subclass(S).
{
	[O addClass:S];
	M = O;
}
module(M) ::= subclass(S).
{
	M = [LKModule module];
	[M addClass:S];
}
module(M) ::= module(O) category(C).
{
	[O addCategory:C];
	M = O;
}
module(M) ::= category(C).
{
	M = [LKModule module];
	[M addCategory:C];
}
module(M) ::= module(O) comment.
{
	M = O;
}
module(M) ::= comment.
{
	M = [LKModule module];
}

pragma_dict(P) ::= pragma_dict(D) COMMA WORD(K) EQ pragma_value(V).
{
	[D setObject:V forKey:K];
	P = D;
}
pragma_dict(P) ::= WORD(K) EQ pragma_value(V).
{
	P = [NSMutableDictionary dictionaryWithObject:V forKey:K];
}

pragma_value(V) ::= WORD(W).   { V = W; }
pragma_value(V) ::= STRING(S). { V = S; }
pragma_value(V) ::= NUMBER(N). { V = N; }

subclass(S) ::= WORD(C) SUBCLASS COLON WORD(N) LSQBRACK ivar_list(L) property_list(P) method_list(M) RSQBRACK.
{
	S = [LKSubclass subclassWithName:N
	                 superclassNamed:C
	                           cvars:[L objectAtIndex:1]
	                           ivars:[L objectAtIndex:0]
                          properties:P
	                         methods:M];
}

category(D) ::= WORD(C) EXTEND LSQBRACK method_list(M) RSQBRACK.
{
	D = [LKCategoryDef categoryOnClassNamed:C methods:M];
}

ivar_list(L) ::= BAR ivars(T) BAR.
{
	L = T;
}
ivar_list ::= .

ivars(L) ::= ivars(T) WORD(W).
{
	/* First element is the list of instance variables. */
    LKVariableDecl *decl = [LKVariableDecl variableDeclWithName:W];
    [decl setSourceRange:[W sourceLocation]];
    [[T objectAtIndex:0] addObject:decl];
	L = T;
}
ivars(L) ::= ivars(T) PLUS WORD(W).
{
	/* Second element is the list of class variables. */
    LKVariableDecl *decl = [LKVariableDecl variableDeclWithName:W];
    [decl setSourceRange:[W sourceLocation]];
	[[T objectAtIndex:1] addObject:decl];
	L = T;
}
ivars(L) ::= .
{
	/*
	Separate lists need to be built for instance and class variables.
	Put them in a fixed size array since we can only pass one value.
	*/
	L = [NSArray arrayWithObjects: [NSMutableArray array],
	                               [NSMutableArray array],
	                               nil];
}


property_list(L) ::= BAR BAR  properties(T) BAR BAR.
{
    L = T;
}
property_list ::= .

properties(L) ::= properties(T) WORD(W).
{
    [T addObject:[LKProperty propertyDeclWithName:W]];
    L = T;
}
properties(L) ::= .
{
    L = [NSMutableArray array];
}


method_list(L) ::= method_list(T) method(M).
{
	[T addObject:M];
	L = T;
}
method_list(L) ::= method_list(T) comment.
{
	L = T;
}
method_list(L) ::= .
{
	L = [NSMutableArray array];
}

method(M) ::= signature(S) LSQBRACK local_list(L) statement_list(E) RSQBRACK.
{
	M = [LKInstanceMethod methodWithSignature:S locals:L statements:E];
}
method(M) ::= PLUS signature(S) LSQBRACK local_list(L) statement_list(E) RSQBRACK.
{
	M = [LKClassMethod methodWithSignature:S locals:L statements:E];
}

signature(S) ::= WORD(M).
{
	S = [LKMessageSend messageWithSelectorName:M];
}
signature(S) ::= keyword_signature(M).
{
	S = M;
}
keyword_signature(S) ::= keyword_signature(M) KEYWORD(K) WORD(E).
{
	S = M;
	[S addSelectorComponent:K];
    LKVariableDecl *decl = [LKVariableDecl variableDeclWithName: E];
    [decl setSourceRange:[E sourceLocation]];
	[S addArgument:decl];
}
keyword_signature(S) ::= KEYWORD(K) WORD(E).
{ 
	S = [LKMessageSend messageWithSelectorName:K];
    LKVariableDecl *decl = [LKVariableDecl variableDeclWithName: E];
    [decl setSourceRange:[E sourceLocation]];
	[S addArgument:decl];
}

local_list(L) ::= BAR locals(T) BAR.
{
	L = T;
}
local_list ::= .

locals(L) ::= locals(T) WORD(W).
{
    LKVariableDecl *decl = [LKVariableDecl variableDeclWithName:W];
    [decl setSourceRange:[W sourceLocation]];
    [T addObject:decl];
	L = T;
}
locals(L) ::= .
{
	L = [NSMutableArray array];
}

statement_list(L) ::= statements(T).
{
	L = T;
}
statement_list(L) ::= statements(T) statement(S).
{
	[T addObject:S];
	L = T;
}

statements(L) ::= statements(T) statement(S) STOP.
{
	[T addObject:S];
	L = T;
}
statements(L) ::= statements(T) comment(C).
{
	[T addObject:C];
	L = T;
}
statements(L) ::= .
{
	L = [NSMutableArray array];
}

comment(S) ::= COMMENT(C).
{
	S = [LKComment commentWithString:C];
    NSRange strRange = [C sourceLocation];
    NSRange range = NSMakeRange(strRange.location - 1, strRange.length + 2);
    [S setSourceRange:range];
}

statement(S) ::= expression(E).
{
	S = E;
}
statement(S) ::= RETURN expression(E).
{
	S = [LKReturn returnWithExpr:E];
}
statement(S) ::= WORD(T) COLON EQ expression(E).
{
    LKDeclRef *decl = RefForSymbol(T);
    [decl setSourceRange:[T sourceLocation]];
	S = [LKAssignExpr assignWithTarget: decl
	                              expr: E];
}

%syntax_error 
{
	[NSException raise:@"ParserError" format:@"Parsing failed"];
}

message(M) ::= keyword_message(K).
{
	M = K;
}
message(M) ::= simple_message(S).
{
	M = S;
}

keyword_message(M) ::= keyword_message(G) KEYWORD(K) simple_expression(A).
{
	M = G;
	[M addSelectorComponent:K];
	[M addArgument:A];
}
keyword_message(M) ::= KEYWORD(K) simple_expression(A).
{
	M = [LKMessageSend messageWithSelectorName:K];
	[M addArgument:A];
}

simple_message(M) ::= WORD(S).
{
	M = [LKMessageSend messageWithSelectorName:S];
}
simple_message(M) ::= binary_selector(S) simple_expression(R). [PLUS]
{
	M = [LKMessageSend messageWithSelectorName:S];
	[M addArgument:R];
}

binary_selector(S) ::= PLUS.
{
	S = @"plus:";
}
binary_selector(S) ::= MINUS.
{
	S = @"sub:";
}
binary_selector(S) ::= STAR.
{
	S = @"mul:";
}
binary_selector(S) ::= SLASH.
{
	S = @"div:";
}
binary_selector(S) ::= EQ.
{
	S = @"isEqual:";
}
binary_selector(S) ::= LT.
{
	S = @"isLessThan:";
}
binary_selector(S) ::= GT.
{
	S = @"isGreaterThan:";
}
binary_selector(S) ::= LT EQ.
{
	S = @"isLessThanOrEqualTo:";
}
binary_selector(S) ::= GT EQ.
{
	S = @"isGreaterThanOrEqualTo:";
}
binary_selector(S) ::= COMMA.
{
	S = @"comma:"; // concatenates strings or arrays (see Support/NSString+comma.m)
}

expression(E) ::= cascade_expression(C).
{
	E = C;
}
expression(E) ::= keyword_expression(K).
{
	E = K;
}
expression(E) ::= simple_expression(S).
{
	E = S;
}

cascade_expression(E) ::= cascade_expression(C) SEMICOLON message(M).
{
	[C addMessage:M];
	E = C;
}
cascade_expression(E) ::= simple_expression(T) message(M) SEMICOLON message(G).
{
	E = [LKMessageCascade messageCascadeWithTarget:T messages:
		[NSMutableArray arrayWithObjects:M, G, nil]];
}

keyword_expression(E) ::= simple_expression(T) keyword_message(M).
{
	if ([T isKindOfClass: [LKDeclRef class]] &&
		[@"C" isEqualToString: [T symbol]])
	{
		NSString *selector = [(LKMessageSend*)M selector];
		NSArray *args = [M arguments];
		if ([@"enumValue:" isEqualToString: selector])
		{
			E = [[LKEnumReference alloc] initWithValue: [[args objectAtIndex: 0] symbol]
			                             inEnumeration: nil];
		}
		else if ([@"enum:value:" isEqualToString: selector])
		{
			E = [[LKEnumReference alloc] initWithValue: [[args objectAtIndex: 0] symbol]
			                             inEnumeration: [[args objectAtIndex: 1] symbol]];
		}
		else
		{
			LKFunctionCall *call= [[LKFunctionCall new] autorelease];
			[call setFunctionName: [selector stringByReplacingOccurrencesOfString: @":" withString: @""]];
			if ([args count] == 1 && [[args objectAtIndex: 0] isKindOfClass: [LKArrayExpr class]])
			{
				[call setArguments: [(LKArrayExpr*)[args objectAtIndex: 0] elements]];
			}
			else
			{
				[call setArguments: [args mutableCopy]];
			}
			E = call;
		}
	}
	else
	{
		[M setTarget:T];
		E = M;
	}
}

simple_expression(E) ::= WORD(V).
{
	if ([V isEqualToString:@"true"])
	{
		E = [LKNumberLiteral literalFromString:@"1"];
	}
	else if ([V isEqualToString:@"false"])
	{
		E = [LKNumberLiteral literalFromString:@"0"];
	}
	else
	{
		E = RefForSymbol(V);
	}
    [E setSourceRange:[V sourceLocation]];
}
simple_expression(E) ::= SYMBOL(S).
{
	E = [LKSymbolRef referenceWithSymbol: S];
    [E setSourceRange:[S sourceLocation]];
}
simple_expression(E) ::= STRING(S).
{
	E = [LKStringLiteral literalFromString:S];
    NSRange strRange = [S sourceLocation];
    NSRange range = NSMakeRange(strRange.location - 1, strRange.length + 2);
    [E setSourceRange:range];
}
simple_expression(E) ::= NUMBER(N).
{
	E = [LKNumberLiteral literalFromString:N];
    [E setSourceRange:[N sourceLocation]];
}
simple_expression(E) ::= FLOATNUMBER(N).
{
	E = [LKFloatLiteral literalFromString:N];
    [E setSourceRange:[N sourceLocation]];
}
simple_expression(E) ::= AT WORD(S).
{
	E = [LKNumberLiteral literalFromSymbol:S];
    [E setSourceRange:[S sourceLocation]];
}
simple_expression(E) ::= simple_expression(T) simple_message(M).
{
	[M setTarget:T];
	E = M;
}
simple_expression(E) ::= simple_expression(L) EQ EQ simple_expression(R).
{
	E = [LKCompare comparisonWithLeftExpression: L
	                            rightExpression: R];
}
simple_expression(E) ::= LPAREN expression(X) RPAREN.
{
	[X setBracketed:YES];
	E = X;
}
simple_expression(E) ::= LBRACE expression_list(L) RBRACE.
{
	E = [LKArrayExpr arrayWithElements:L];
}
simple_expression(E) ::= LSQBRACK argument_list(A) local_list(L) statement_list(S) RSQBRACK.
{
	//FIXME: block locals
	E = [LKBlockExpr blockWithArguments: A
	                             locals: L
	                         statements: S];
/*
	E = [LKBlockExpr blockWithArguments: [A objectAtIndex: 0]
	                             locals: [A objectAtIndex: 1]
	                         statements: S];
*/
}
/*
block_local_list(L) ::= block_local_list(T) WORD(W) BAR.
{
	[T addObject:W];
	L = T;
}
block_local_list(L) ::= .
{
	L = [NSMutableArray array];
}
*/
argument(A) ::= COLON WORD(W).
{
	A = W;
}

argument_list(L) ::= argument(A) arguments(T) BAR.
{
    LKVariableDecl *decl = [LKVariableDecl variableDeclWithName:A];
    [decl setSourceRange:[A sourceLocation]];
	[T insertObject: decl atIndex: 0];
	L = T;
}
argument_list ::= .

arguments(L) ::= arguments(T) argument(A).
{
    LKVariableDecl *decl = [LKVariableDecl variableDeclWithName:A];
    [decl setSourceRange:[A sourceLocation]];
    [T addObject:decl];
	L = T;
}
arguments(L) ::= .
{
	L = [NSMutableArray array];
}

expression_list(L) ::= expressions(T).
{
	L = T;
}
expression_list(L) ::= expressions(T) expression(E).
{
	[T addObject:E];
	L = T;
}

expressions(L) ::= expressions(T) expression(E) STOP.
{
	[T addObject:E];
	L = T;
}
expressions(L) ::= .
{
	L = [NSMutableArray array];
}
