package musescript.evo.graal;

import java.NativeArray;

/**
 * Minimal hand-written externs for org.graalvm.polyglot (25.x).
 * Only the surface EvoBench needs: engine/context lifecycle, byte-source eval,
 * instantiation with proxy imports, member access, execution, and buffer writes.
 */
@:native("org.graalvm.polyglot.Engine")
extern class Engine {
	static function newBuilder(permittedLanguages:NativeArray<String>):EngineBuilder;
	function close():Void;
}

@:native("org.graalvm.polyglot.Engine$Builder")
extern class EngineBuilder {
	function option(key:String, value:String):EngineBuilder;
	function allowExperimentalOptions(enabled:Bool):EngineBuilder;
	function build():Engine;
}

@:native("org.graalvm.polyglot.Context")
extern class Context {
	static function newBuilder(permittedLanguages:NativeArray<String>):ContextBuilder;
	function eval(source:Source):Value;
	function close():Void;
}

@:native("org.graalvm.polyglot.Context$Builder")
extern class ContextBuilder {
	function engine(engine:Engine):ContextBuilder;
	function option(key:String, value:String):ContextBuilder;
	function build():Context;
}

@:native("java.lang.CharSequence")
extern interface CharSequence {}

@:native("org.graalvm.polyglot.Source")
extern class Source {
	@:overload(function(language:String, bytes:ByteSequence, name:String):SourceBuilder {})
	@:overload(function(language:String, characters:CharSequence, name:String):SourceBuilder {})
	static function newBuilder(language:String, file:JFile):SourceBuilder;
}

@:native("org.graalvm.polyglot.Source$Builder")
extern class SourceBuilder {
	function build():Source;
}

@:native("org.graalvm.polyglot.io.ByteSequence")
extern interface ByteSequence {}

@:native("org.graalvm.polyglot.Value")
extern class Value {
	function getMember(identifier:String):Value;
	function hasMember(identifier:String):Bool;
	function newInstance(arguments:NativeArray<Dynamic>):Value;
	function execute(arguments:NativeArray<Dynamic>):Value;
	function asDouble():Float;
	function asInt():Int;
	function isNull():Bool;
	function writeBufferDouble(order:ByteOrder, byteOffset:haxe.Int64, value:Float):Void;
	function readBufferDouble(order:ByteOrder, byteOffset:haxe.Int64):Float;
}

@:native("java.nio.ByteOrder")
extern class ByteOrder {
	static final LITTLE_ENDIAN:ByteOrder;
	static final BIG_ENDIAN:ByteOrder;
}

@:native("java.io.File")
extern class JFile {
	function new(pathname:String):Void;
}

@:native("org.graalvm.polyglot.proxy.ProxyExecutable")
extern interface ProxyExecutable {
	function execute(arguments:NativeArray<Value>):Dynamic;
}

@:native("org.graalvm.polyglot.proxy.ProxyObject")
extern interface ProxyObject {
	function getMember(key:String):Dynamic;
	function getMemberKeys():Dynamic;
	function hasMember(key:String):Bool;
	function putMember(key:String, value:Value):Void;
}

@:native("org.graalvm.polyglot.proxy.ProxyArray")
extern interface ProxyArray {
	function get(index:haxe.Int64):Dynamic;
	function set(index:haxe.Int64, value:Value):Void;
	function getSize():haxe.Int64;
}
