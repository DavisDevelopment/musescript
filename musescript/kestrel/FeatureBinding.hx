package musescript.kestrel;

typedef FeatureBinding = {
	var name:String;
	var expr:FeatureExpr;
	var ?role:FeatureRole;
	var ?description:String;
}

enum FeatureRole {
	FRaw;
	FDerived;
	FModel;
	FGraph;
	FLogic;
}
