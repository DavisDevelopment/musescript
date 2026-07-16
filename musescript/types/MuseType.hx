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
}
