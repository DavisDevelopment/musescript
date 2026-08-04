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
	/** Contiguous ndarray handle (runtime: `NdArrayF64` / `AnyNdArray`). */
	TNdArray;
	/** Tabular DataFrame (runtime: `musescript.dataframe.DataFrame`) — not a matrix shim. */
	TDataFrame;
	/** Tabular Series (runtime: `musescript.dataframe.Series`) — ≠ streaming `TSeries`. */
	TPdSeries;
	/** Index labels (runtime: `AnyIndex` / IndexF64|IndexStr). */
	TIndex;
	TGraph;
	TGraphPath;
	TGraphRanks;
	/** Opaque parsed ProbabilityCloud (runtime: ProbCloudRuntime) — see musescript/kestrel/ProbCloudRuntime.hx. */
	TProbCloud;
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
