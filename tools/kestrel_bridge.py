"""
kestrel_bridge.py — fits a `ProbabilityCloud` from raw OHLCV candles and
serializes it to the portable JSON shape `musescript.kestrel.ProbCloudRuntime`
(Haxe, compiles to JS for web/mobile AND Python for backtest) parses.

Architecture (deliberate split, see musescript-kestrel-probcloud-bridge
memory for the full rationale): FITTING a cloud is expensive (encoder
pretraining, ~80 epochs by default) and inherently Python-only — it needs
the proprietary marketsim/encoder code in kalshi-ai-advisor, imported here
via sys.path, never copied into this repo. QUERYING an already-fitted cloud
(median/prob_above/prob_between/...) is cheap piecewise-linear interpolation
over a small array and has been ported to pure Haxe
(musescript/kestrel/ProbCloudRuntime.hx) specifically so it behaves
IDENTICALLY on every platform a MuseScript strategy can run on — this
module's only job is producing that JSON once, offline, not serving live
per-bar queries.

Mirrors tools/muse_math_runtime.py's existing sys.path bootstrap pattern
(see musescript/compile/NumbaBackend.hx's `ensurePathPublic`) so a future
Haxe-side `KestrelBridge.hx` (python-target only, `#if python`) can call
this the same way NumbaBackend calls muse_math_runtime.

Smoke-tested end-to-end 2026-07-19 against the real kalshi-ai-advisor venv
(2 synthetic symbols, 300 daily bars, epochs=3): imports, `WorldPanel`
construction/`.validate()`, `FoundationEncoder.pretrain/encode/project_cloud`,
and JSON serialization all ran clean and produced a well-formed cloud
(`fit_and_serialize_cloud` output round-trips through
`ProbCloudRuntime.fromJson` shape-for-shape). One real bug was caught and
fixed by that smoke test: `epochs` is a `pretrain()` kwarg, not a
`FoundationEncoder` constructor field (an earlier draft passed it to the
constructor and threw `TypeError` immediately). Not yet validated: fit
quality/calibration on REAL market data (only synthetic random-walk candles
were used), and the `adaptive=True` / `coverage` calibration path in
`project_cloud` (exercised only with defaults). The portable Haxe query
layer (ProbCloudRuntime) remains separately, fully tested — see
musescript/tests/TestProbCloud.hx.
"""
from __future__ import annotations

import sys
import os
from typing import Any, Dict, List, Optional, Sequence


def _ensure_kalshi_advisor_on_path() -> None:
    """Adds kalshi-ai-advisor/python to sys.path, sibling to this repo
    (kalshai/muse-lab/muse-script/tools/ -> kalshai/kalshi-ai-advisor/python).
    Mirrors NumbaBackend.ensurePathPublic's cwd-relative + abspath double
    insert, adapted for a SIBLING repo instead of this repo's own tools/."""
    here = os.path.dirname(os.path.abspath(__file__))
    # tools/ -> muse-script/ -> muse-lab/ -> kalshai/
    kalshai_root = os.path.abspath(os.path.join(here, "..", "..", ".."))
    candidate = os.path.join(kalshai_root, "kalshi-ai-advisor", "python")
    if os.path.isdir(candidate) and candidate not in sys.path:
        sys.path.insert(0, candidate)


def fit_and_serialize_cloud(
    symbols: Sequence[str],
    candles_by_symbol: Dict[str, List[dict]],
    horizon: int = 5,
    *,
    epochs: Optional[int] = None,
    seed: int = 0,
) -> Dict[str, Any]:
    """Fit a ProbabilityCloud from raw candles and return the JSON-safe dict
    `ProbCloudRuntime.fromJson` expects: `{symbols, quantiles, paths, horizon,
    coverage}`.

    `candles_by_symbol[sym]` is a list of `{date, open, high, low, close,
    volume}` dicts, oldest-first, ALL SYMBOLS THE SAME LENGTH (this bridge
    does not do its own cross-symbol date alignment — callers are expected
    to hand in already-aligned bars, e.g. from a shared trading-day index;
    misaligned lengths raise before any encoder work happens, not partway
    through).

    `epochs=None` uses UMarketSimConfig's own default (pretrain budget);
    pass a small number (e.g. 5-10) for a fast/smoke-test fit — the encoder
    doesn't need architecture search, only gradient/ridge epochs.
    """
    _ensure_kalshi_advisor_on_path()
    import numpy as np
    from synth import data as sdata
    from synth.marketsim.unified_diffmarketsim import world
    from synth.marketsim.unified_diffmarketsim.config import UMarketSimConfig
    from synth.marketsim.unified_diffmarketsim.contracts import WorldPanel, LatentSpec
    from synth.marketsim.unified_diffmarketsim.encoder import FoundationEncoder
    from synth.marketsim.unified_diffmarketsim.probability_cloud import ProbabilityCloud

    symbols = tuple(symbols)
    if not symbols:
        raise ValueError("kestrel_bridge: at least one symbol required")

    series_list = [sdata.series_from_candles(sym, candles_by_symbol[sym]) for sym in symbols]
    lengths = {len(s) for s in series_list}
    if len(lengths) != 1:
        raise ValueError(f"kestrel_bridge: symbols have mismatched bar counts: {lengths}")
    n_time = lengths.pop()

    cfg = UMarketSimConfig(symbols=symbols, resolutions=("1d",), min_bars=min(250, n_time))

    # Stack each symbol's [n_time, n_chan] matrix into [n_sym, n_time, n_chan].
    mats = [world._symbol_matrix(s, cfg) for s in series_list]  # [(data, mask), ...]
    data = np.stack([d for d, _m in mats], axis=0)
    mask = np.stack([m for _d, m in mats], axis=0)
    # Epoch-second times off the first symbol's (shared, by construction) date axis.
    times = series_list[0].dates.astype("datetime64[s]").astype(np.int64)

    panel = WorldPanel(
        symbols=symbols,
        channels=world.CHANNELS,
        resolutions=("1d",),
        data={"1d": data},
        mask={"1d": mask},
        times={"1d": times},
    ).validate()

    enc = FoundationEncoder(spec=LatentSpec(), horizon=int(horizon), seed=seed, use_torch=False)
    pretrain_kwargs: Dict[str, Any] = {}
    if epochs is not None:
        pretrain_kwargs["epochs"] = int(epochs)
    enc.pretrain(panel, **pretrain_kwargs)
    z = enc.encode(panel)
    cloud: ProbabilityCloud = enc.project_cloud(z, int(horizon), panel=panel)

    coverage = None
    if cloud.coverage is not None:
        coverage = {"cov90": float(cloud.coverage.get("cov90")), "cov50": float(cloud.coverage.get("cov50"))}

    return {
        "symbols": list(cloud.symbols),
        "quantiles": [float(q) for q in cloud.quantiles.tolist()],
        "paths": cloud.paths.tolist(),  # [n_sym][n_q][horizon], JSON-native nested lists
        "horizon": int(cloud.horizon),
        "coverage": coverage,
    }


def fit_and_serialize_cloud_json(
    symbols: Sequence[str],
    candles_by_symbol: Dict[str, List[dict]],
    horizon: int = 5,
    *,
    epochs: Optional[int] = None,
    seed: int = 0,
) -> str:
    """`fit_and_serialize_cloud` + `json.dumps` — the direct callable a Haxe
    `#if python` bridge (mirroring NumbaBackend.hx's `Reflect.callMethod`
    pattern) would invoke, since Haxe's Python target marshals a JSON
    STRING more predictably across the boundary than a nested dict."""
    import json
    return json.dumps(fit_and_serialize_cloud(
        symbols, candles_by_symbol, horizon, epochs=epochs, seed=seed
    ))
