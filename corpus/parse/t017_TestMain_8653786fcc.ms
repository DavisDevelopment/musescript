
			@macro("discover") {
				sample(universe, 22);
				llm.suggestEncodings(features, 5);
				pickBest(encodings, function(enc) {
					return ensemble(enc, 100);
				});
				tune(learningRate, maxDepth);
				optimize(sharpe);
				distill(best);
			}
		