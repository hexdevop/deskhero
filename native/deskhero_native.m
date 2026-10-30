// DeskHero: минимальный GDExtension для macOS (чистый Objective-C, без godot-cpp).
// Две возможности: поведение окна по Spaces (NSWindow.collectionBehavior) и политика активации (Accessory).
// Класс MacosWindowNative: только статические методы, объекты не создаются.
//   apply_all_spaces(handle: int) -> int   выставить маску, вернуть итоговое значение или -1
//   get_collection_behavior(handle: int) -> int   текущее значение или -1
//   set_accessory_policy() -> int   политика Accessory (нет в Dock/Cmd+Tab), итог или -1
// Нет сети, нет запуска процессов, нет приватных API. Заголовок: godot --dump-gdextension-interface.

#import <AppKit/AppKit.h>
#include "gdextension_interface.h"

#define DH_EXPORT __attribute__((visibility("default")))

// Нужные биты. Значения NSWindowCollectionBehavior.
static const NSUInteger kAdd = NSWindowCollectionBehaviorCanJoinAllSpaces
		| NSWindowCollectionBehaviorStationary
		| NSWindowCollectionBehaviorFullScreenAuxiliary
		| NSWindowCollectionBehaviorIgnoresCycle;
// Взаимоисключающие с kAdd биты, их снимаем, иначе AppKit бросает исключение:
// MoveToActiveSpace (с CanJoinAllSpaces), FullScreenPrimary (с Auxiliary; Godot ставит его сам),
// ParticipatesInCycle (с IgnoresCycle). Остальные чужие биты не трогаем.
static const NSUInteger kClear = NSWindowCollectionBehaviorMoveToActiveSpace
		| NSWindowCollectionBehaviorFullScreenPrimary
		| NSWindowCollectionBehaviorParticipatesInCycle
		| NSWindowCollectionBehaviorFullScreenNone;

static GDExtensionInterfaceGetProcAddress gp;
static GDExtensionClassLibraryPtr lib;
static GDExtensionInterfaceVariantGetType variant_get_type;
static GDExtensionVariantFromTypeConstructorFunc int_to_variant;
static GDExtensionTypeFromVariantConstructorFunc int_from_variant;
static GDExtensionInterfaceClassdbRegisterExtensionClass6 register_class;
static GDExtensionInterfaceClassdbRegisterExtensionClassMethod register_method;
static GDExtensionInterfaceClassdbUnregisterExtensionClass unregister_class;
static GDExtensionInterfaceStringNameNewWithLatin1Chars sn_new;
static GDExtensionInterfaceStringNewWithLatin1Chars str_new;
static GDExtensionInterfaceVariantGetPtrDestructor get_destructor;

static void *class_name[1];
static void *parent_name[1];
static void *apply_name[1];
static void *get_name[1];
static void *accessory_name[1];
static void *arg_name[1];
static void *empty_string[1];
static void *empty_name[1];

// Находит NSWindow по числу из native handle, не разыменовывая непроверенный указатель:
// сравниваем с реальным списком окон приложения. Только главный поток.
static NSWindow *find_window(int64_t handle) {
	if (handle == 0 || (handle & 7) != 0 || ![NSThread isMainThread]) {
		return nil;
	}
	@try {
		for (NSWindow *w in [NSApp windows]) {
			if ((int64_t)(intptr_t)(__bridge void *)w == handle) {
				return w;
			}
		}
	} @catch (NSException *e) {
		return nil;
	}
	return nil;
}

static int64_t do_apply(int64_t handle) {
	NSWindow *w = find_window(handle);
	if (w == nil) {
		return -1;
	}
	@try {
		NSUInteger cur = [w collectionBehavior];
		NSUInteger next = (cur & ~kClear) | kAdd;
		if (next != cur) {
			[w setCollectionBehavior:next];
		}
		return (int64_t)[w collectionBehavior];
	} @catch (NSException *e) {
		return -1;
	}
}

static int64_t do_get(int64_t handle) {
	NSWindow *w = find_window(handle);
	if (w == nil) {
		return -1;
	}
	@try {
		return (int64_t)[w collectionBehavior];
	} @catch (NSException *e) {
		return -1;
	}
}

// Политика активации: Accessory (нет значка в Dock и в Cmd+Tab). Godot сам ставит Regular при старте
// и перекрывает LSUIElement из Info.plist. Публичный API, только главный поток.
// Возвращает итоговую политику (1 = Accessory) или -1.
static int64_t do_accessory(void) {
	if (NSApp == nil || ![NSThread isMainThread]) {
		return -1;
	}
	@try {
		if ([NSApp activationPolicy] != NSApplicationActivationPolicyAccessory) {
			[NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
		}
		return (int64_t)[NSApp activationPolicy];
	} @catch (NSException *e) {
		return -1;
	}
}

// Общая часть вариантного вызова: разбор одного int-аргумента.
static void variant_call(int64_t (*fn)(int64_t), const GDExtensionConstVariantPtr *args, GDExtensionInt argc, GDExtensionVariantPtr ret, GDExtensionCallError *err) {
	if (argc < 1) {
		err->error = GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS;
		err->expected = 1;
		return;
	}
	if (argc > 1) {
		err->error = GDEXTENSION_CALL_ERROR_TOO_MANY_ARGUMENTS;
		err->expected = 1;
		return;
	}
	if (variant_get_type(args[0]) != GDEXTENSION_VARIANT_TYPE_INT) {
		err->error = GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT;
		err->argument = 0;
		err->expected = GDEXTENSION_VARIANT_TYPE_INT;
		return;
	}
	int64_t h = 0;
	int_from_variant(&h, (GDExtensionVariantPtr)args[0]);
	int64_t r = fn(h);
	int_to_variant(ret, &r);
	err->error = GDEXTENSION_CALL_OK;
}

static void apply_call(void *ud, GDExtensionClassInstancePtr inst, const GDExtensionConstVariantPtr *args, GDExtensionInt argc, GDExtensionVariantPtr ret, GDExtensionCallError *err) {
	variant_call(do_apply, args, argc, ret, err);
}
static void get_call(void *ud, GDExtensionClassInstancePtr inst, const GDExtensionConstVariantPtr *args, GDExtensionInt argc, GDExtensionVariantPtr ret, GDExtensionCallError *err) {
	variant_call(do_get, args, argc, ret, err);
}
static void accessory_call(void *ud, GDExtensionClassInstancePtr inst, const GDExtensionConstVariantPtr *args, GDExtensionInt argc, GDExtensionVariantPtr ret, GDExtensionCallError *err) {
	if (argc != 0) {
		err->error = GDEXTENSION_CALL_ERROR_TOO_MANY_ARGUMENTS;
		err->expected = 0;
		return;
	}
	int64_t r = do_accessory();
	int_to_variant(ret, &r);
	err->error = GDEXTENSION_CALL_OK;
}
static void accessory_ptr(void *ud, GDExtensionClassInstancePtr inst, const GDExtensionConstTypePtr *args, GDExtensionTypePtr ret) {
	*(int64_t *)ret = do_accessory();
}
static void apply_ptr(void *ud, GDExtensionClassInstancePtr inst, const GDExtensionConstTypePtr *args, GDExtensionTypePtr ret) {
	*(int64_t *)ret = do_apply(*(const int64_t *)args[0]);
}
static void get_ptr(void *ud, GDExtensionClassInstancePtr inst, const GDExtensionConstTypePtr *args, GDExtensionTypePtr ret) {
	*(int64_t *)ret = do_get(*(const int64_t *)args[0]);
}

static void free_instance(void *ud, GDExtensionClassInstancePtr inst) {}

static void add_method(void *name, GDExtensionClassMethodCall call, GDExtensionClassMethodPtrCall ptr, uint32_t argc) {
	GDExtensionPropertyInfo arg = {
		GDEXTENSION_VARIANT_TYPE_INT, arg_name, empty_name, 0, empty_string, 6 /* PROPERTY_USAGE_DEFAULT */
	};
	GDExtensionPropertyInfo ret = {
		GDEXTENSION_VARIANT_TYPE_INT, empty_name, empty_name, 0, empty_string, 6
	};
	GDExtensionClassMethodArgumentMetadata meta = GDEXTENSION_METHOD_ARGUMENT_METADATA_INT_IS_INT64;
	GDExtensionClassMethodInfo mi = {0};
	mi.name = name;
	mi.call_func = call;
	mi.ptrcall_func = ptr;
	mi.method_flags = GDEXTENSION_METHOD_FLAG_NORMAL | GDEXTENSION_METHOD_FLAG_STATIC;
	mi.has_return_value = 1;
	mi.return_value_info = &ret;
	mi.return_value_metadata = GDEXTENSION_METHOD_ARGUMENT_METADATA_INT_IS_INT64;
	mi.argument_count = argc;
	mi.arguments_info = &arg;
	mi.arguments_metadata = &meta;
	register_method(lib, class_name, &mi);
}

static void init_level(void *ud, GDExtensionInitializationLevel level) {
	if (level != GDEXTENSION_INITIALIZATION_SCENE) {
		return;
	}
	GDExtensionClassCreationInfo6 ci = {0};
	ci.is_abstract = 1;  // объекты не создаются, только статические методы
	ci.is_exposed = 1;
	ci.free_instance_func = free_instance;
	register_class(lib, class_name, parent_name, &ci);
	add_method(apply_name, apply_call, apply_ptr, 1);
	add_method(accessory_name, accessory_call, accessory_ptr, 0);
	add_method(get_name, get_call, get_ptr, 1);
}

static void deinit_level(void *ud, GDExtensionInitializationLevel level) {
	if (level == GDEXTENSION_INITIALIZATION_SCENE) {
		unregister_class(lib, class_name);
		// Имена созданы с p_is_static=0 (копия буфера), поэтому освобождаем их штатным деструктором.
		GDExtensionPtrDestructor sn_free = get_destructor(GDEXTENSION_VARIANT_TYPE_STRING_NAME);
		GDExtensionPtrDestructor str_free = get_destructor(GDEXTENSION_VARIANT_TYPE_STRING);
		void **names[] = { class_name, parent_name, apply_name, get_name, accessory_name, arg_name, empty_name };
		for (size_t i = 0; sn_free && i < sizeof(names) / sizeof(names[0]); i++) {
			sn_free(names[i]);
		}
		if (str_free) {
			str_free(empty_string);
		}
	}
}

DH_EXPORT GDExtensionBool deskhero_native_init(GDExtensionInterfaceGetProcAddress get_proc, GDExtensionClassLibraryPtr library, GDExtensionInitialization *init) {
	gp = get_proc;
	lib = library;
	variant_get_type = (GDExtensionInterfaceVariantGetType)gp("variant_get_type");
	GDExtensionInterfaceGetVariantFromTypeConstructor from_c = (GDExtensionInterfaceGetVariantFromTypeConstructor)gp("get_variant_from_type_constructor");
	GDExtensionInterfaceGetVariantToTypeConstructor to_c = (GDExtensionInterfaceGetVariantToTypeConstructor)gp("get_variant_to_type_constructor");
	register_class = (GDExtensionInterfaceClassdbRegisterExtensionClass6)gp("classdb_register_extension_class6");
	register_method = (GDExtensionInterfaceClassdbRegisterExtensionClassMethod)gp("classdb_register_extension_class_method");
	unregister_class = (GDExtensionInterfaceClassdbUnregisterExtensionClass)gp("classdb_unregister_extension_class");
	sn_new = (GDExtensionInterfaceStringNameNewWithLatin1Chars)gp("string_name_new_with_latin1_chars");
	str_new = (GDExtensionInterfaceStringNewWithLatin1Chars)gp("string_new_with_latin1_chars");
	get_destructor = (GDExtensionInterfaceVariantGetPtrDestructor)gp("variant_get_ptr_destructor");
	if (!variant_get_type || !from_c || !to_c || !register_class || !register_method || !unregister_class || !sn_new || !str_new || !get_destructor) {
		return 0;  // движок слишком старый: расширение не загружается, приложение работает без него
	}
	int_to_variant = from_c(GDEXTENSION_VARIANT_TYPE_INT);
	int_from_variant = to_c(GDEXTENSION_VARIANT_TYPE_INT);
	if (!int_to_variant || !int_from_variant) {
		return 0;
	}
	sn_new(class_name, "MacosWindowNative", 0);
	sn_new(parent_name, "Object", 0);
	sn_new(apply_name, "apply_all_spaces", 0);
	sn_new(get_name, "get_collection_behavior", 0);
	sn_new(accessory_name, "set_accessory_policy", 0);
	sn_new(arg_name, "handle", 0);
	sn_new(empty_name, "", 0);
	str_new(empty_string, "");
	init->minimum_initialization_level = GDEXTENSION_INITIALIZATION_SCENE;
	init->userdata = NULL;
	init->initialize = init_level;
	init->deinitialize = deinit_level;
	return 1;
}
