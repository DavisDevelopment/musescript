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
			case "StringArray": TStringArray;
			case "Vector": TVector;
			case "Matrix": TMatrix;
			case "Graph": TGraph;
			case "GraphPath": TGraphPath;
			case "GraphRanks": TGraphRanks;
			case "ProbCloud": TProbCloud;
			case "Window": TWindow;
			case "Price": TPrice;
			case "Void": TVoid;
			case "Metric": TMetric;
			case "Plan": TPlan;
			case "Feature": TFeature;
			case "GraphQuery": TGraphQuery;
			case "Model": TModel;
			case "Tree": TTree;
			case "Dict": TDict;
			case "Set": TSet;
			case "Bag": TBag;
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
			case TStringArray: "StringArray";
			case TVector: "Vector";
			case TMatrix: "Matrix";
			case TGraph: "Graph";
			case TGraphPath: "GraphPath";
			case TGraphRanks: "GraphRanks";
			case TProbCloud: "ProbCloud";
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
			case TDict: "Dict";
			case TSet: "Set";
			case TBag: "Bag";
			case TObject(fields):
				"{" + [for (f in fields) f.name + ": " + toString(f.ty)].join(", ") + "}";
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
			case [TSeries, TScalar]: true; // current-bar leaf of a series
			case [TObject(fa), TGraphPath]:
				canAssign(TObject(fa), TObject([
					{name: "nodes", ty: TStringArray},
					{name: "distance", ty: TScalar}
				]));
			case [TGraphPath, TObject(fb)]:
				canAssign(TObject([
					{name: "nodes", ty: TStringArray},
					{name: "distance", ty: TScalar}
				]), TObject(fb));
			case [TObject(fa), TObject(fb)]:
				// Width-subtyping: `from` must have at least `to`'s fields.
				for (tb in fb) {
					var found = false;
					for (ta in fa) {
						if (ta.name == tb.name) {
							if (!canAssign(ta.ty, tb.ty)) return false;
							found = true;
							break;
						}
					}
					if (!found) return false;
				}
				true;
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

	/**
	 * Oracle-grade assignability: an Unknown on either side is a refusal,
	 * not a free pass. Forge/Swarm use this to reject unprovable wires.
	 */
	public static function canAssignStrict(from:MuseType, to:MuseType):Bool {
		if (from.match(TUnknown) || to.match(TUnknown)) return false;
		return canAssign(from, to);
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
