#import "LanguageKit.h"
#import "Runtime/BigInt.h"
#import "Runtime/BoxedFloat.h"
#import "Runtime/Symbol.h"
#import "Runtime/LKObject.h"
#import "LKInterpreter.h"
#import "LKInterpreterRuntime.h"
#import "LKInterpreterContext.h"
#import "LKTypeHelpers.h"
#ifndef GNU_RUNTIME
#include <objc/objc-runtime.h>
#endif
#include <string.h>
#include <ffi.h>
#include <dlfcn.h>

OBJC_EXPORT id objc_retainAutoreleaseReturnValue(id obj);

static id BoxValue(void *value, const char *typestr);
static void UnboxValue(id value, void *dest, const char *objctype);
static void RetainValue(id value, const char *objctype);

#ifdef __LP64__
ffi_type *_ffi_type_nspoint_elements[] = {
	&ffi_type_double, &ffi_type_double, NULL
};
#else
ffi_type *_ffi_type_nspoint_elements[] = {
	&ffi_type_float, &ffi_type_float, NULL
};
#endif
ffi_type ffi_type_nspoint = {
	0, 0, FFI_TYPE_STRUCT, _ffi_type_nspoint_elements
};
ffi_type *_ffi_type_nsrect_elements[] = {
	&ffi_type_nspoint, &ffi_type_nspoint, NULL
};
ffi_type ffi_type_nsrect = {
	0, 0, FFI_TYPE_STRUCT, _ffi_type_nsrect_elements
};
#if NSUIntegerMax == ULONG_MAX
ffi_type *_ffi_type_nsrange_elements[] = {
	&ffi_type_ulong, &ffi_type_ulong, NULL
};
#else
ffi_type *_ffi_type_nsrange_elements[] = {
	&ffi_type_uint, &ffi_type_uint, NULL
};
#endif
ffi_type ffi_type_nsrange = {
	0, 0, FFI_TYPE_STRUCT, _ffi_type_nsrange_elements
};

struct trampoline
{
	Class cls;
	const char *types;
};

static ffi_type *FFITypeForObjCType(const char *typestr)
{
	LKSkipQualifiers(&typestr);

	switch(*typestr)
	{
		case 'B':
		case 'c':
			return &ffi_type_schar;
		case 'C':
			return &ffi_type_uchar;
		case 's':
			return &ffi_type_sshort;
		case 'S':
			return &ffi_type_ushort;
		case 'i':
			return &ffi_type_sint;
		case 'I':
			return &ffi_type_uint;
		case 'l':
			return &ffi_type_slong;
		case 'L':
			return &ffi_type_ulong;
		case 'q':
			return &ffi_type_sint64;
		case 'Q':
			return &ffi_type_uint64;
		case 'f': 
			return &ffi_type_float;
		case 'd':
			return &ffi_type_double;
		case ':': 
			return &ffi_type_pointer;
		case '{':
		{
			if (0 == strncmp(typestr, "{_NSRect", 8))
			{
				return &ffi_type_nsrect;
			}
            else if (0 == strncmp(typestr, "{CGRect", 7))
            {
                return &ffi_type_nsrect;
            }
			else if (0 == strncmp(typestr, "{_NSRange", 9))
			{
				return &ffi_type_nsrange;
			}
			else if (0 == strncmp(typestr, "{_NSPoint", 9))
			{
				return &ffi_type_nspoint;
			}
			else if (0 == strncmp(typestr, "{_NSSize", 8))
			{
				return &ffi_type_nspoint;
			}
            else if (0 == strncmp(typestr, "{CGPoint", 8))
            {
                return &ffi_type_nspoint;
            }
			[NSException raise: LKInterpreterException  
			            format: @"ObjC to FFI type conversion not supported for"
			                    "arbitrary structs"];
		}
		case 'v':
			return &ffi_type_void;
		case '(':
		case '^':
		case '@':
		case '#':
			return &ffi_type_pointer;
	}
	[NSException raise: LKInterpreterException  
	            format: @"ObjC to FFI type conversion not supported for '%c'",
	                    *typestr];
	return NULL;
}

static id BoxValue(void *value, const char *typestr)
{
	LKSkipQualifiers(&typestr);
	
	switch(*typestr)
	{
		case 'B':
			return [BigInt bigIntWithLong: *(BOOL*)value];
		case 'c':
			return [BigInt bigIntWithLong: *(char*)value];
		case 'C':
			return [BigInt bigIntWithUnsignedLong: *(unsigned char*)value];
		case 's':
			return [BigInt bigIntWithLong: *(short*)value];
		case 'S':
			return [BigInt bigIntWithUnsignedLong: *(unsigned short*)value];
		case 'i':
			return [BigInt bigIntWithLong: *(int*)value];
		case 'I':
			return [BigInt bigIntWithUnsignedLong: *(unsigned int*)value];
		case 'l':
			return [BigInt bigIntWithLongLong: *(long*)value];
		case 'L':
			return [BigInt bigIntWithUnsignedLong: *(unsigned long*)value];
		case 'q': case 'Q': // FIXME: Incorrect for unsiged long long
			return [BigInt bigIntWithLongLong: *(long long*)value];
		case 'f': 
			return [BoxedFloat boxedFloatWithFloat: *(float*)value];
		case 'd':
			return [BoxedFloat boxedFloatWithFloat: *(double*)value];
		case ':': 
			return [Symbol SymbolForSelector: *(SEL*)value];
		case '{':
		{
			if (0 == strncmp(typestr, "{_NSRect", 8))
			{
				return [NSValue valueWithRect: *(NSRect*)value];
			}
            else if (0 == strncmp(typestr, "{CGRect", 7))
            {
                return [NSValue valueWithRect: *(NSRect*)value];
            }
			else if (0 == strncmp(typestr, "{_NSRange", 9))
			{
				return [NSValue valueWithRange: *(NSRange*)value];
			}
			else if (0 == strncmp(typestr, "{_NSPoint", 9))
			{
				return [NSValue valueWithPoint: *(NSPoint*)value];
			}
			else if (0 == strncmp(typestr, "{_NSSize", 8))
			{
				return [NSValue valueWithSize: *(NSSize*)value];
			}
			[NSException raise: LKInterpreterException  
			            format: @"Boxing arbitrary structures doesn't work yet."];
		}
		case '^': // FIXME: properly box pointers!
			// Map void returns to nil
		case 'v':
			return nil;
			// If it's already an object, we don't need to do anything
		case '(':
			return nil;
		case '@':
		case '#':
			return *(__unsafe_unretained id*)value;
			// Other types, just wrap them up in an NSValue
		default:
			NSLog(@"Warning: using +[NSValue valueWithBytes:objCType:]");
			return [NSValue valueWithBytes: value objCType: typestr];
	}
}

static void UnboxValue(id value, void *dest, const char *objctype)
{
	LKSkipQualifiers(&objctype);

	switch(*objctype)
	{
		case 'c':
			*(char*)dest = [value charValue];
			break;
		case 'C':
			*(unsigned char*)dest = [value unsignedCharValue];
			break;
		case 's':
			*(short*)dest = [value shortValue];
			break;
		case 'S':
			*(unsigned short*)dest = [value unsignedShortValue];
			break;
		case 'i':
			*(int*)dest = [value intValue];
			break;
		case 'I':
			*(unsigned int*)dest = [value unsignedIntValue];
			break;
		case 'l':
			*(long*)dest = [value longValue];
			break;
		case 'L':
			*(unsigned long*)dest = [value unsignedLongValue];
			break;
		case 'q':
			*(long long*)dest = [value longLongValue];
			break;
		case 'Q':
			*(unsigned long long*)dest = [value unsignedLongLongValue];
			break;
		case 'f':
			*(float*)dest = [value floatValue];
			break;
		case 'd':
			*(double*)dest = [value doubleValue];
			break;
		case 'B':
			*(BOOL*)dest = [value boolValue];
			break;
		case ':':
			*(SEL*)dest = [value selValue];
			break;
		case '(':
		case '^':
			if (strncmp(objctype, @encode(LKObject), strlen(@encode(LKObject))) != 0)
			{
				break;
			}
		case '#':
            *(__unsafe_unretained id*)dest = value; // catlan: hmm?
		case '@':
			*(__unsafe_unretained id*)dest = value;
			return;
		case 'v':
			*(void**)dest = NULL;
			return;
		case '{':
		{
			if (0 == strncmp(objctype, "{_NSRect", 8))
			{
				*(NSRect*)dest = [value rectValue];
				break;
			}
            else if (0 == strncmp(objctype, "{CGRect", 7))
            {
                *(NSRect*)dest = [value rectValue];
                break;
            }
			else if (0 == strncmp(objctype, "{_NSRange", 9))
			{
				*(NSRange*)dest = [value rangeValue];
				break;
			}
			else if (0 == strncmp(objctype, "{_NSPoint", 9))
			{
				*(NSPoint*)dest = [value pointValue];
				break;
			}
			else if (0 == strncmp(objctype, "{_NSSize", 8))
			{
				*(NSSize*)dest = [value sizeValue];
				break;
			}
            else if (0 == strncmp(objctype, "{CGPoint", 8))
            {
                *(CGPoint*)dest = [value pointValue];
                break;
            }
		}
		default:
			[NSException raise: LKInterpreterException  
			            format: @"Unable to transmogriy object to"
			                    "compound type: %s\n", objctype];
	}
}

OBJC_EXPORT id objc_retain(id value);

static void RetainValue(id value, const char *objctype)
{
    LKSkipQualifiers(&objctype);
    
    switch(*objctype)
    {
        case 'c':
            break;
        case 'C':
            break;
        case 's':
            break;
        case 'S':
            break;
        case 'i':
            break;
        case 'I':
            break;
        case 'l':
            break;
        case 'L':
            break;
        case 'q':
            break;
        case 'Q':
            break;
        case 'f':
            break;
        case 'd':
            break;
        case 'B':
            break;
        case ':':
            break;
        case '(':
        case '^':
            if (strncmp(objctype, @encode(LKObject), strlen(@encode(LKObject))) != 0)
            {
                break;
            }
        case '#':
            break;
        case '@':
            objc_retain(value);
            return;
        case 'v':
            return;
        case '{':
        {
            break;
        }
        default:
            [NSException raise: LKInterpreterException
                        format: @"Unable to transmogriy object to"
             "compound type: %s\n", objctype];
    }
}

id LKCallFunction(NSString *functionName, NSString *types,
                 unsigned int argc, const id *args)
{
	NSMethodSignature *sig = [NSMethodSignature signatureWithObjCTypes: [types UTF8String]];
	void *function = dlsym(RTLD_DEFAULT, [functionName UTF8String]);
	if (NULL == function)
	{
		[NSException raise: LKInterpreterException
		            format: @"Could not look up function %@", functionName];
	}

	// Prepare FFI types
	const char *returnObjCType = [sig methodReturnType];
	ffi_type *ffi_ret_ty = FFITypeForObjCType(returnObjCType);
	ffi_type *ffi_tys[argc];
	for (unsigned int i = 0; i < argc; i++)
	{
		const char *objCType = [sig getArgumentTypeAtIndex: i];
		ffi_tys[i] = FFITypeForObjCType(objCType);
	}
	
	ffi_cif cif;
	if (FFI_OK != ffi_prep_cif(&cif,  FFI_DEFAULT_ABI, argc, ffi_ret_ty, ffi_tys))
	{
		[NSException raise: LKInterpreterException
		            format: @"Error preparing call signature"];
	}
	
	// Prepare actual args. Use more space than needed
	char unboxedArgumentsBuffer[[sig numberOfArguments]][[sig frameLength]];
	void *unboxedArguments[[sig numberOfArguments]];
	for (unsigned int i = 0; i < argc; i++)
	{
		const char *objCType = [sig getArgumentTypeAtIndex: i];
		UnboxValue(args[i], unboxedArgumentsBuffer[i], objCType);
		unboxedArguments[i] = unboxedArgumentsBuffer[i];
	}
	
	char msgSendRet[[sig methodReturnLength]];
	ffi_call(&cif, function, &msgSendRet, unboxedArguments);
	
	return BoxValue(msgSendRet, [sig methodReturnType]);
}

static BOOL isInMethodFamily(NSString *selName, NSString *family)
{
	if ([selName rangeOfString: family].location != 0)
	{
		return NO;
	}
	if ([selName length] == [family length])
	{
		return YES;
	}
	return isupper([selName characterAtIndex: [family length]]);
}

id LKSendMessage(NSString *className, id receiver, NSString *selName,
                 unsigned int argc, const id *args)
{
	if (receiver == nil)
	{
		return nil;
	}
	BOOL autoreleaseResult = NO;
	if (isInMethodFamily(selName, @"alloc") ||
	    isInMethodFamily(selName, @"new") ||
	    isInMethodFamily(selName, @"copy") ||
	    isInMethodFamily(selName, @"mutableCopy"))
	{
		autoreleaseResult = YES;
	}
	else if (isInMethodFamily(selName, @"init"))
	{
		autoreleaseResult = YES;
	}

	SEL sel = sel_getUid([selName UTF8String]);
    NSMethodSignature *sig = nil;
    @try {
        sig = [receiver methodSignatureForSelector: sel];
    }
    @catch (NSException *e) {
        NSLog(@"%s methodSignatureForSelector %@", __PRETTY_FUNCTION__, e);
    }
	if (nil == sig)
	{
		[NSException raise: LKInterpreterException
		            format: @"Couldn't determine type for selector %@", selName];
	}
	if (argc + 2 != [sig numberOfArguments])
	{
		[NSException raise: LKInterpreterException
					format: @"Tried to call %@ with %d arguments", selName, argc];
	}
	
	void *methodIMP;
#ifdef GNU_RUNTIME
	if (className)
	{
		Class cls = NSClassFromString(className);
		if (class_isMetaClass(object_getClass(receiver)))
		{
			cls = object_getClass(cls);
		}
		struct objc_super sup = { receiver, cls };
		methodIMP = objc_msg_lookup_super(&sup, sel);
	}
	else
	{
		methodIMP = objc_msg_lookup(receiver, sel);
	}
#else
	if (className)
	{
		switch (*[sig methodReturnType])
		{
			case '{':
				methodIMP = objc_msgSendSuper_stret;
				break;
			default:
				methodIMP = objc_msgSendSuper;
		}
        
        // catlan: Ughh, need to make this pretty
        Class aSuperClass = NSClassFromString(className);
        struct objc_super mySuper = {
            .receiver = receiver,
            .super_class = class_isMetaClass(object_getClass(receiver)) //check if we are an instance or Class
            ? object_getClass(aSuperClass)                //if we are a Class, we need to send our metaclass (our Class's Class)
            : aSuperClass                                 //if we are an instance, we need to send our Class (which we already have)
        };
        receiver = &mySuper;
	}
	else
	{
		switch (*[sig methodReturnType])
		{
			case '{':
				methodIMP = objc_msgSend_stret;
				break;
#ifdef __i386__
			case 'f':
			case 'd':
			case 'D':
				methodIMP = objc_msgSend_fpret;
				break;
#endif
#ifdef __x86_64__
			case 'D':
				methodIMP = objc_msgSend_fpret;
				break;
#endif
			default:
				methodIMP = objc_msgSend;
		}
	}
#endif
	
	// Prepare FFI types
	const char *returnObjCType = [sig methodReturnType];
	ffi_type *ffi_ret_ty = FFITypeForObjCType(returnObjCType);
	ffi_type *ffi_tys[argc + 2];
	for (unsigned int i = 0; i < (argc + 2); i++)
	{
		const char *objCType = [sig getArgumentTypeAtIndex: i];
		ffi_tys[i] = FFITypeForObjCType(objCType);
	}
	
	ffi_cif cif;
	if (FFI_OK != ffi_prep_cif(&cif,  FFI_DEFAULT_ABI, argc + 2, ffi_ret_ty, ffi_tys))
	{
		[NSException raise: LKInterpreterException
		            format: @"Error preparing call signature"];
	}
	
	// Prepare actual args. Use more space than needed
	char unboxedArgumentsBuffer[[sig numberOfArguments]][[sig frameLength]];
	void *unboxedArguments[[sig numberOfArguments]];
	unboxedArguments[0] = &receiver;
	unboxedArguments[1] = &sel;
	for (unsigned int i = 0; i < argc; i++)
	{
		const char *objCType = [sig getArgumentTypeAtIndex: i + 2];
		UnboxValue(args[i], unboxedArgumentsBuffer[i + 2], objCType);
        RetainValue(args[i], objCType);
		unboxedArguments[i + 2] = unboxedArgumentsBuffer[i + 2];
	}
	
	char msgSendRet[[sig methodReturnLength]];
    if (methodIMP == objc_msgSend_stret )
    {
        // http://www.cocoabuilder.com/archive/cocoa/200146-returning-values-from-objc-msgsend-etc.html
        methodIMP = objc_msgSend;
        ffi_call(&cif, methodIMP, &msgSendRet, unboxedArguments);
    }
    else
    {
        ffi_call(&cif, methodIMP, &msgSendRet, unboxedArguments);
    }
    
	id result = BoxValue(msgSendRet, [sig methodReturnType]);
	if (autoreleaseResult)
	{
		objc_retainAutoreleaseReturnValue(result);
	}
	return result;
}


id LKGetIvar(id receiver, NSString *name)
{
	Ivar ivar = class_getInstanceVariable([receiver class], [name UTF8String]);
	if (NULL == ivar)
	{
		[NSException raise: LKInterpreterException
                    format: @"Error getting ivar '%@' of object %@",
		                    name, receiver];
	}
	void *ivarAddress = (char*)(__bridge void*)receiver +ivar_getOffset(ivar);
	id result = BoxValue(ivarAddress, ivar_getTypeEncoding(ivar));
	return result;
}

BOOL LKSetIvar(id receiver, NSString *name, id value)
{
	Ivar ivar = class_getInstanceVariable([receiver class], [name UTF8String]);
	if (NULL == ivar)
	{
		return NO;
	}
	void *ivarAddress = (char*)(__bridge void*)receiver + ivar_getOffset(ivar);
	const char *encoding = ivar_getTypeEncoding(ivar);
	if (encoding[0] == '@')
	{
        *(__strong id*)ivarAddress = value; // catlan: hm, [value retain]?
	}
	else
	{
		UnboxValue(value, ivarAddress, encoding);
	}
	return YES;
}

static void LKInterpreterFFITrampoline(ffi_cif *cif, void *ret, 
                                       void **args, void *user_data)
{
	struct trampoline *t = user_data;
	Class cls = t->cls;
	
	id receiver = *((__unsafe_unretained id*)args[0]);
	SEL cmd = *((SEL*)args[1]);
	const char *objctype = t->types;

	LKMethod *methodASTNode = LKASTForMethod(cls, 
		[NSString stringWithUTF8String: sel_getName(cmd)]);
    LKInterpreter *interpreter = [LKInterpreter interpreter];
	
	id returnObject;
	if (cif->nargs - 2 == 0)
	{
        [interpreter executeCode:methodASTNode
                    withReceiver:receiver
                       arguments:NULL
                           count:0];
	}
	else 
	{
		id argumentObjects[cif->nargs - 2];
		
		const char *argtypes = objctype;
		// Skip the return type, recevier type, and selector type
		LKNextType(&argtypes);
		LKNextType(&argtypes);
		LKNextType(&argtypes);
		for (unsigned int i=0; i<cif->nargs - 2; i++)
		{
			argumentObjects[i] = BoxValue(args[i+2], argtypes);
			LKNextType(&argtypes);
		}
        [interpreter executeCode: methodASTNode
                    withReceiver: receiver
                       arguments: argumentObjects
                           count: cif->nargs - 2];
	}
    returnObject = [interpreter returnValue];
	UnboxValue(returnObject, ret, objctype);
}

IMP LKInterpreterMakeIMP(Class cls, const char *objctype)
{
	struct trampoline *t = malloc(sizeof(struct trampoline));
	t->cls = cls;
	t->types = strdup(objctype);

	int nargs = LKCountObjCTypes(objctype);
	ffi_type *ffi_ret_ty;
	ffi_type **ffi_tys = malloc((nargs - 1) * sizeof(ffi_type*));
	
	ffi_ret_ty = FFITypeForObjCType(objctype);
	LKNextType(&objctype);
	for (unsigned int i=0; i<nargs-1; i++)
	{
		ffi_tys[i] = FFITypeForObjCType(objctype);
		LKNextType(&objctype);
	}
	
	ffi_cif *cif = malloc(sizeof(ffi_cif));
	if (FFI_OK != ffi_prep_cif(cif,
	                           FFI_DEFAULT_ABI, nargs - 1, ffi_ret_ty, ffi_tys))
	{
		[NSException raise: LKInterpreterException
		            format: @"Error preparing closure signature"];
	}
	
	ffi_closure *closure_exec;
	ffi_closure *closure_write = ffi_closure_alloc(sizeof(ffi_closure),
	                                               (void*)&closure_exec);
	
	if (FFI_OK != ffi_prep_closure_loc(closure_write, cif, 
	                                   LKInterpreterFFITrampoline, 
	                                   t, closure_exec))
	{
		[NSException raise: LKInterpreterException
		            format: @"Error preparing closure"];
	}
	
	return (IMP)closure_exec;
}
