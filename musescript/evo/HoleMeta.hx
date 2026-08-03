package musescript.evo;

import musescript.ast.Expr;
import musescript.ast.Const;
import musescript.ast.MuseNodes;

/**
 * Encode / decode hole meta args living on `EMeta("__hole", args, seed)`.
 *
 * Wire format (P0):
 *   [tyString]
 *   [tyString, "int", lo, hi]
 *   [tyString, "real", lo, hi]
 *   [tyString, "family", "sma,ema"]  (P1-ready)
 */
class HoleMeta {
	public static function encodeArgs(ty:String, domain:Null<HoleDomain>):Array<Expr> {
		var args = [MuseNodes.stringExpr(ty != null ? ty : "")];
		if (domain == null) return args;
		return switch (domain) {
			case DIntRange(lo, hi):
				args.concat([MuseNodes.stringExpr("int"), MuseNodes.intExpr(lo), MuseNodes.intExpr(hi)]);
			case DRealInterval(lo, hi):
				args.concat([MuseNodes.stringExpr("real"), MuseNodes.floatExpr(lo), MuseNodes.floatExpr(hi)]);
			case DFamily(names):
				args.concat([MuseNodes.stringExpr("family"), MuseNodes.stringExpr(names.join(","))]);
		};
	}

	public static function typeOf(args:Array<Expr>):String {
		if (args == null || args.length == 0) return "";
		return switch (args[0]) {
			case EConst(CString(s)): s;
			default: "";
		};
	}

	public static function decodeDomain(args:Array<Expr>):Null<HoleDomain> {
		if (args == null || args.length < 2) return null;
		var tag = switch (args[1]) {
			case EConst(CString(s)): s;
			default: return null;
		};
		return switch (tag) {
			case "int" if (args.length >= 4):
				var lo = numInt(args[2]);
				var hi = numInt(args[3]);
				if (lo == null || hi == null) null else DIntRange(lo, hi);
			case "real" if (args.length >= 4):
				var lo = numFloat(args[2]);
				var hi = numFloat(args[3]);
				if (lo == null || hi == null) null else DRealInterval(lo, hi);
			case "family" if (args.length >= 3):
				var s = switch (args[2]) {
					case EConst(CString(v)): v;
					default: return null;
				};
				var names = [for (p in s.split(",")) if (StringTools.trim(p) != "") StringTools.trim(p)];
				names.length > 0 ? DFamily(names) : null;
			default: null;
		};
	}

	/** Neutral seed for an unfilled sketch (midpoint of domain, else 0). */
	public static function scalarSeed(domain:Null<HoleDomain>):ScalarNode {
		return switch (domain) {
			case DIntRange(lo, hi): KConst(0.5 * (lo + hi));
			case DRealInterval(lo, hi): KConst(0.5 * (lo + hi));
			default: KConst(0.0);
		};
	}

	static function numInt(e:Expr):Null<Int> {
		return switch (e) {
			case EConst(CInt(v)): v;
			case EConst(CFloat(v)): Std.int(v);
			case EUnop("-", true, EConst(CInt(v))): -v;
			case EUnop("-", true, EConst(CFloat(v))): -Std.int(v);
			default: null;
		};
	}

	static function numFloat(e:Expr):Null<Float> {
		return switch (e) {
			case EConst(CInt(v)): v + 0.0;
			case EConst(CFloat(v)): v;
			case EUnop("-", true, EConst(CInt(v))): -v + 0.0;
			case EUnop("-", true, EConst(CFloat(v))): -v;
			default: null;
		};
	}
}
