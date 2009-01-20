#import <EtoileFoundation/EtoileFoundation.h>

@class LKAST;
@protocol LKParser;

/**
 * EScript parser class.  This class implements a tokeniser and calls a
 * parser created using the Lemon parser generator.
 */
@interface EScriptParser : NSObject <LKParser> {
  LKAST *delegate;
}
/**
 * Used by the Lemon implementation to feed the generated AST back so the
 * Parser can return it.
 */
- (void) setDelegate:(LKAST*)ast;
@end
