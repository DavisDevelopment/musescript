package musescript.ndarray;

/** Core ops for `@:multiType` NdArray arms — keep free of circular imports. */
interface INdArrayCore<T> {
	function getShape():Shape;
	function getNdim():Int;
	function getSize():Int;
	function getFlat(i:Int):T;
	function setFlat(i:Int, v:T):Void;
	function getAt(indices:Array<Int>):T;
	function copyF64():NdArrayF64;
	function reshapeF64(newShape:Array<Int>):Null<NdArrayF64>;
	function toArray():Array<T>;
}
