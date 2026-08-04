package musescript.ndarray;

/**
 * Cold Muse / host existential — enum dispatch is for boxing only, never for
 * per-element kernel selection (use concrete `NdArrayF64` / `F32` / `I32` / `Bool`).
 */
enum AnyNdArray {
	F64(a:NdArrayF64);
	F32(a:NdArrayF32);
	I32(a:NdArrayI32);
	Bool(a:NdArrayBool);
}
