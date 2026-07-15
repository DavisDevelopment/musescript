package musescript.types;

typedef BuiltinSig = {
	var args:Array<MuseType>;
	var ret:MuseType;
	var ?varArgs:Bool;
	var ?minArgs:Int;
}
