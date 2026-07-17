package musescript.types;

class SourcePositions {
	public static function none():SourcePos {
		return {};
	}

	public static function make(?file:String, ?line:Int, ?pmin:Int, ?pmax:Int, ?column:Int):SourcePos {
		return { file: file, line: line, column: column, pmin: pmin, pmax: pmax };
	}

	public static function format(p:Null<SourcePos>):String {
		if (p == null) return "";
		var parts:Array<String> = [];
		if (p.file != null) parts.push(p.file);
		if (p.line != null) {
			parts.push(":" + p.line);
			if (p.column != null) parts.push(":" + p.column);
		} else if (p.pmin != null) {
			parts.push("@" + p.pmin);
		}
		return parts.length == 0 ? "" : parts.join("");
	}

	/** Line/column from a byte offset into `src` (1-based). */
	public static function fromOffset(src:String, offset:Int, ?file:String, ?pmax:Int):SourcePos {
		var line = 1;
		var col = 1;
		var n = offset < 0 ? 0 : (offset > src.length ? src.length : offset);
		var i = 0;
		while (i < n) {
			if (src.charCodeAt(i) == 10) {
				line++;
				col = 1;
			} else {
				col++;
			}
			i++;
		}
		return make(file, line, offset, pmax != null ? pmax : offset, col);
	}
}
