package musescript.pinescript.ast;

/**
 * Pine's type system is a lattice of a QUALIFIER × a base TYPE. The qualifier is
 * the part everyone gets wrong and the part that actually drives repaint/eval
 * semantics — a `series` value can change every bar; a `const` never changes.
 *
 * We keep the two axes separate here; `semantics/SeriesTypeInfer` computes the
 * qualifier by lattice join (const ≤ input ≤ simple ≤ series) and `translit`
 * uses it to decide what becomes a Muse series vs. a plain scalar.
 */
enum PineQualifier {
	QConst;   // known at compile time
	QInput;   // fixed after inputs resolve, constant for the whole run
	QSimple;  // scalar, constant across bars but not compile-time-known
	QSeries;  // may differ every bar — the default for most expressions
}

enum PineBaseType {
	TyInt;
	TyFloat;
	TyBool;
	TyString;
	TyColor;
	TyNa;                     // the `na` bottom value, joins with anything
	TyLine; TyLabel; TyBox; TyTable; TyChartPoint;  // drawing/UI objects
	TyArray(el:PineBaseType);
	TyMatrix(el:PineBaseType);
	TyMap(k:PineBaseType, v:PineBaseType);
	TyUserType(name:String);  // `type Foo` UDT (v5+)
	TyUnknown;                // not yet inferred
}

typedef PineType = {
	var qual:PineQualifier;
	var base:PineBaseType;
}
