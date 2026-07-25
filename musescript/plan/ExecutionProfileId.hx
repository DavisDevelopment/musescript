package musescript.plan;

enum ExecutionProfileId {
	/** One strategy over all data — WASM/native, tape packed once, full memos. */
	SingleStrategyMaxThroughput;
	/** Min wall-time/generation — NMA memo + surrogate + worker pool + prefix attribution. */
	EvoMinWallclock;
	/** Determinism first — pinned backend, caches off for champion checks. */
	ProductionRepro;
	/** Phone/browser — JS/WASM, no ONNX-Java, persisted memo OK. */
	MobileWeb;
}
