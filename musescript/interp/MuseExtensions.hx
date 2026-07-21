package musescript.interp;

/**
 * Generic registration point for out-of-tree packages that want to extend a
 * running MuseScript interpreter or its palette JSON without core importing
 * them by name. Core knows only about this class, never about any specific
 * extension package; an extension registers itself (typically from a small
 * bootstrap file in its own package, called once before the first `MuseInterp`
 * is constructed / before `MuseScript.fullPalette()` is first read).
 *
 * This exists so packages that must not live in the open-sourceable
 * `muse-script` tree (e.g. a proprietary sibling package) can still wire
 * builtins and palette entries into the interpreter from outside — core never
 * has a compile-time or runtime dependency on them either way.
 */
class MuseExtensions {
	public static var installers:Array<(vars:Map<String, Dynamic>, harness:Dynamic) -> Void> = [];
	public static var paletteProviders:Array<Void -> Dynamic> = [];

	public static function register(installer:(vars:Map<String, Dynamic>, harness:Dynamic) -> Void):Void {
		installers.push(installer);
	}

	public static function registerPalette(provider:Void -> Dynamic):Void {
		paletteProviders.push(provider);
	}

	public static function installAll(vars:Map<String, Dynamic>, harness:Dynamic):Void {
		for (fn in installers) fn(vars, harness);
	}

	/** One JSON object per registered provider, in registration order. */
	public static function collectPalettes():Array<Dynamic> {
		return [for (fn in paletteProviders) fn()];
	}
}
