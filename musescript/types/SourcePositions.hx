package musescript.types;

class SourcePositions {
	public static function none():SourcePos {
		return {};
	}

	public static function make(?file:String, ?line:Int, ?pmin:Int, ?pmax:Int):SourcePos {
		return { file: file, line: line, pmin: pmin, pmax: pmax };
	}

	public static function format(p:Null<SourcePos>):String {
		if (p == null) return "";
		var parts:Array<String> = [];
		if (p.file != null) parts.push(p.file);
		if (p.line != null) parts.push(":" + p.line);
		else if (p.pmin != null) parts.push("@" + p.pmin);
		return parts.length == 0 ? "" : parts.join("");
	}
}
