package musescript.types;

/**
 * Helpers for the MuseType lattice.
 */
class MuseTypes {
	/** Bounded Window ladder (Fib). */
	public static final WINDOW_LADDER:Array<Int> = [1, 2, 3, 5, 8, 13, 21, 34, 55, 89];

	public static function isWindow(n:Int):Bool {
		return WINDOW_LADDER.indexOf(n) >= 0;
	}

	public static function parseName(name:String):Null<MuseType> {
		return switch (name) {
			case "Series": TSeries;
			case "Scalar": TScalar;
			case "Bool": TBool;
			case "String": TString;
			case "Vector": TVector;
			case "Window": TWindow;
			case "Price": TPrice;
			case "Void": TVoid;
			case "Metric": TMetric;
			case "Plan": TPlan;
			case "Feature": TFeature;
			case "GraphQuery": TGraphQuery;
			case "Model": TModel;
			case "Tree": TTree;
			case "Unknown": TUnknown;
			default: null;
		};
	}

	public static function toString(t:MuseType):String {
		return switch (t) {
			case TSeries: "Series";
			case TScalar: "Scalar";
			case TBool: "Bool";
			case TString: "String";
			case TVector: "Vector";
			case TWindow: "Window";
			case TPrice: "Price";
			case TVoid: "Void";
			case TUnknown: "Unknown";
			case TMetric: "Metric";
			case TPlan: "Plan";
			case TFeature: "Feature";
			case TGraphQuery: "GraphQuery";
			case TModel: "Model";
			case TTree: "Tree";
			case TFun(args, ret):
				"(" + [for (a in args) toString(a)].join(", ") + ") -> " + toString(ret);
			case TTemplate(args, ret):
				"template(" + [for (a in args) toString(a)].join(", ") + ") -> " + toString(ret);
		};
	}

	/** Structural / refinement assignability. */
	public static function canAssign(from:MuseType, to:MuseType):Bool {
		if (Type.enumEq(from, to)) return true;
		if (from.match(TUnknown) || to.match(TUnknown)) return true;
		return switch [from, to] {
			case [TPrice, TScalar]: true;
			case [TWindow, TScalar]: true;
			case [TFeature, TScalar]: true;
			case [TModel, TFeature]: true;
			case [TTree, TModel]: true;
			case [TFun(fa, fr), TFun(ta, tr)]:
				if (fa.length != ta.length) return false;
				for (i in 0...fa.length)
					if (!canAssign(ta[i], fa[i])) return false;
				canAssign(fr, tr);
			case [TTemplate(fa, fr), TTemplate(ta, tr)]:
				canAssign(TFun(fa, fr), TFun(ta, tr));
			default: false;
		};
	}

	public static function unify(a:MuseType, b:MuseType):MuseType {
		if (Type.enumEq(a, b)) return a;
		if (a.match(TUnknown)) return b;
		if (b.match(TUnknown)) return a;
		if (canAssign(a, b)) return b;
		if (canAssign(b, a)) return a;
		return TUnknown;
	}
}
