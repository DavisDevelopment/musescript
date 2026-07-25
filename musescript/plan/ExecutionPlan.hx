package musescript.plan;

typedef ExecutionPlan = {
	var steps:Array<PlanStep>;
	var sourceOrigin:Null<String>;
	/** Resolved execution profile (P3). Null = legacy unspecified (caller keeps ad-hoc flags). */
	var ?profile:ExecutionProfile;
}
