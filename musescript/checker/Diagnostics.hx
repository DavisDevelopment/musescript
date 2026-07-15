package musescript.checker;

import musescript.types.SourcePos;
import musescript.types.SourcePositions;

class Diagnostics {
	public static function error(msg:String, ?pos:SourcePos, ?code:String):Diagnostic {
		return { severity: Error, msg: msg, pos: pos, code: code };
	}

	public static function warning(msg:String, ?pos:SourcePos, ?code:String):Diagnostic {
		return { severity: Warning, msg: msg, pos: pos, code: code };
	}

	public static function toString(d:Diagnostic):String {
		var loc = SourcePositions.format(d.pos);
		var prefix = (d.severity : String) + ": ";
		return loc != "" ? prefix + loc + ": " + d.msg : prefix + d.msg;
	}

	public static function toStrings(ds:Array<Diagnostic>):Array<String> {
		return [for (d in ds) toString(d)];
	}

	public static function toJson(d:Diagnostic):Dynamic {
		return {
			severity: (d.severity : String),
			msg: d.msg,
			code: d.code,
			pos: d.pos
		};
	}
}
