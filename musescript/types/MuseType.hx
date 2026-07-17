package musescript.types;

/**
 * Canonical MuseScript type lattice — shared by checker, editors, and MuseGene.
 */
enum MuseType {
	TSeries;
	TScalar;
	TBool;
	TString;
	TStringArray;
	TVector;
	TMatrix;
	TGraph;
	TGraphPath;
	TGraphRanks;
	TWindow;
	TPrice;
	TVoid;
	TFun(args:Array<MuseType>, ret:MuseType);
	TUnknown;
	TMetric;
	TPlan;
	TFeature;
	TGraphQuery;
	TModel;
	TTree;
	TTemplate(args:Array<MuseType>, ret:MuseType);
	/** Structural record — inferred from `{...}` literals / multi-field builtins. */
	TObject(fields:Array<{name:String, ty:MuseType}>);
	/** Opaque string-keyed map (runtime: `Map<String,Dynamic>`). */
	TDict;
	/** Opaque string-identity set (runtime: `Map<String,Bool>`). */
	TSet;
	/** Named weighted symbol bag (runtime: `SymbolBag`). */
	TBag;
}
