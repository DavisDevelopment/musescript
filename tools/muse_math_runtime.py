"""Host helpers for MuseScript math backends (numba / pure python / wasmtime)."""
from __future__ import annotations
import math
import struct
from typing import Any, Callable, Optional, Sequence


def load_python(src: str, name: str) -> Callable[..., Any]:
    ns: dict[str, Any] = {"math": math}
    exec(src, ns, ns)
    fn = ns.get(name)
    if fn is None:
        raise RuntimeError(f"function {name!r} missing after exec")
    return fn


def load_numba(src: str, name: str) -> Callable[..., Any]:
    from numba import njit
    import numpy as np

    ns: dict[str, Any] = {"math": math, "njit": njit, "np": np}
    if "@njit" not in src:
        src = "from numba import njit\n@njit(cache=False)\n" + src
    elif "from numba import njit" not in src:
        src = "from numba import njit\n" + src
    src = src.replace("@njit(cache=True)", "@njit(cache=False)")
    exec(src, ns, ns)
    fn = ns.get(name)
    if fn is None:
        raise RuntimeError(f"numba function {name!r} missing after exec")

    def call(*args):
        coerced = []
        for a in args:
            if isinstance(a, (list, tuple)):
                coerced.append(np.asarray(a, dtype=np.float64))
            else:
                coerced.append(a)
        return fn(*coerced)

    # warm-up with tiny arrays if possible
    try:
        call(*[np.zeros(8, dtype=np.float64) if i < 3 else (8 if i == 3 else 2) for i in range(8)])
    except Exception:
        try:
            call(1)
        except Exception:
            pass
    return call


def load_wasm(wat: str, name: str) -> Callable[..., Any]:
    """Scalar-only wasm (legacy)."""
    return load_wasm_fn(wat, name, arg_names=[], series_names=[])


def load_wasm_fn(
    wat: str,
    name: str,
    arg_names: Sequence[str],
    series_names: Sequence[str],
) -> Callable[..., Any]:
    from wasmtime import Engine, Store, Module, Linker, FuncType, ValType, Func, wat2wasm
    import numpy as np

    engine = Engine()
    store = Store(engine)
    try:
        module = Module(engine, wat2wasm(wat))
    except Exception as e:
        raise RuntimeError(f"wasm compile failed for {name}: {e}\n--- wat ---\n{wat}") from e

    series_set = set(series_names)
    series_order = [a for a in arg_names if a in series_set] if arg_names else list(series_names)

    linker = Linker(engine)

    def unary(f):
        def _impl(x: float) -> float:
            return float(f(x))

        return Func(store, FuncType([ValType.f64()], [ValType.f64()]), _impl)

    for nm, f in {
        "sin": math.sin,
        "cos": math.cos,
        "sqrt": math.sqrt,
        "abs": abs,
        "exp": math.exp,
        "log": math.log,
        "floor": math.floor,
        "ceil": math.ceil,
        "tan": math.tan,
        "round": round,
    }.items():
        try:
            linker.define(store, "env", nm, unary(f))
        except Exception:
            pass

    # Instantiate once; memory-backed series kernels rewrite memory each call.
    instance = linker.instantiate(store, module)
    exports = instance.exports(store)
    func = exports[name]
    try:
        memory = exports["memory"]
    except KeyError:
        memory = None

    def bind_and_call(*call_args):
        if not series_order:
            return func(store, *call_args)

        if memory is None:
            raise RuntimeError(f"wasm fn {name!r} uses series but exports no memory")

        # Preserve source argument order: series become (base,len) pairs in place.
        packed: list[Any] = []
        total = 0
        for i, an in enumerate(arg_names):
            if an in series_set:
                arr = np.asarray(call_args[i], dtype="<f8", order="C")
                packed.append(("series", total, arr))
                total += int(arr.nbytes)
            else:
                packed.append(("scalar", call_args[i]))

        need_pages = max(1, (total + 65535) // 65536)
        cur = memory.size(store)
        if need_pages > cur:
            memory.grow(store, need_pages - cur)

        wasm_args: list[Any] = []
        for item in packed:
            if item[0] == "series":
                _, off, arr = item
                memory.write(store, arr.tobytes(order="C"), off)
                wasm_args.append(off)
                wasm_args.append(int(arr.shape[0]))
            else:
                wasm_args.append(item[1])
        return func(store, *wasm_args)

    return bind_and_call


def _host_get(host: Any, name: str) -> Callable[..., Any]:
    if isinstance(host, dict):
        if name not in host:
            raise RuntimeError(f"strategy HostABI missing {name!r}")
        return host[name]
    fn = getattr(host, name, None)
    if fn is None:
        raise RuntimeError(f"strategy HostABI missing {name!r}")
    return fn


STATE_BYTES = 22528  # must match StrategyWasmRuntimeWat.STATE_BYTES (rise rings + vec scratch)


def _instantiate_strategy(wat: str, host: Any):
    from wasmtime import Engine, Store, Module, Linker, Func, ValType, wat2wasm

    engine = Engine()
    store = Store(engine)
    try:
        module = Module(engine, wat2wasm(wat))
    except Exception as e:
        raise RuntimeError(f"strategy wasm compile failed: {e}\n--- wat ---\n{wat}") from e

    def _coerce_ret(out: Any, results: Any) -> Any:
        rs = list(results)
        if len(rs) == 0:
            return None
        if len(rs) == 1:
            t = rs[0]
            if t == ValType.f64():
                return float(out)
            if t == ValType.i32():
                return int(out)
            return out
        return out

    linker = Linker(engine)
    for imp in module.imports:
        if imp.module != "env":
            continue
        name = imp.name
        fty = imp.type
        cb = _host_get(host, name)
        result_types = list(fty.results)

        def _make(fn: Callable[..., Any], res: list = result_types):
            def _impl(*args: Any) -> Any:
                return _coerce_ret(fn(*args), res)

            return _impl

        linker.define(store, "env", name, Func(store, fty, _make(cb)))

    instance = linker.instantiate(store, module)
    return store, instance


def load_strategy_on_bar(wat: str, host: Any) -> Callable[..., Any]:
    """
    Backward-compatible: returns a zero-arg callable that push_bars nothing —
    prefer load_strategy_module for the dual-mode memory ABI.
    If the module exports push_bar, this wraps a no-arg no-op style for legacy.
    Legacy callers used on_bar() with host-fed bar_* imports; new modules need push_bar args.
    """
    mod = load_strategy_module(wat, host)

    def call(*args: Any) -> Any:
        if args:
            return mod.push_bar(*[float(a) for a in args])
        raise RuntimeError("strategy on_bar requires push_bar(o,h,l,c,v,t,i) or on_bar(index)")

    return call


def load_strategy_module(wat: str, host: Any) -> dict[str, Any]:
    """
    Instantiate a memory-backed StrategyWasm module.
    Returns dict with: reset, push_bar, on_bar, configure_tape, pack_and_configure, memory accessors.
    Host supplies side-effect env imports (get_param/long/short/flat/plot*) plus pure math (exp).
    """
    import numpy as np

    store, instance = _instantiate_strategy(wat, host)
    exports = instance.exports(store)

    def _fn(name: str):
        return exports[name]

    memory = exports["memory"]

    def reset(capacity: int) -> None:
        _fn("reset")(store, int(capacity))

    def push_bar(o, h, l, c, v, t, i) -> None:
        _fn("push_bar")(
            store,
            float(o), float(h), float(l), float(c),
            float(v), float(t), float(i),
        )

    def on_bar(index: int) -> None:
        _fn("on_bar")(store, int(index))

    def configure_tape(ob, hb, lb, cb, vb, tb, ib, length) -> None:
        _fn("configure_tape")(
            store,
            int(ob), int(hb), int(lb), int(cb),
            int(vb), int(tb), int(ib), int(length),
        )

    def ensure_capacity(need_bytes: int) -> None:
        _fn("ensure_capacity")(store, int(need_bytes))

    def configure_features(base: int, count: int) -> None:
        try:
            fn = _fn("configure_features")
        except (KeyError, TypeError):
            if count:
                raise RuntimeError("strategy WASM does not export configure_features")
            return
        fn(store, int(base), int(count))

    def construct_once_init() -> None:
        """P4: run-once field-init + ctor for natively-lowered construct-once
        class instances (StrategyWasmEmitter). Absent when the program
        declares none — a no-op then, same optional-export pattern as
        configure_features."""
        try:
            fn = _fn("construct_once_init")
        except (KeyError, TypeError):
            return
        fn(store)

    def pack_and_configure(
        bars: Sequence[Any],
        feature_tapes: Optional[Sequence[Sequence[float]]] = None,
    ) -> None:
        """Copy OHLCV and optional feature-major f64 tapes into WASM memory."""
        n = len(bars)
        if n <= 0:
            n = 1
        feature_count = len(feature_tapes) if feature_tapes is not None else 0
        bytes_needed = STATE_BYTES + n * (7 + feature_count) * 8
        ensure_capacity(bytes_needed)

        def _f(b: Any, key: str, default: float = 0.0) -> float:
            if isinstance(b, dict):
                return float(b.get(key, default))
            if hasattr(b, key):
                return float(getattr(b, key))
            try:
                return float(b[key])
            except Exception:
                return float(default)

        opens = np.empty(n, dtype="<f8")
        highs = np.empty(n, dtype="<f8")
        lows = np.empty(n, dtype="<f8")
        closes = np.empty(n, dtype="<f8")
        vols = np.empty(n, dtype="<f8")
        times = np.empty(n, dtype="<f8")
        idxs = np.empty(n, dtype="<f8")
        for i, b in enumerate(bars):
            opens[i] = _f(b, "open")
            highs[i] = _f(b, "high")
            lows[i] = _f(b, "low")
            closes[i] = _f(b, "close")
            vols[i] = _f(b, "volume")
            times[i] = _f(b, "time", float(i))
            idxs[i] = _f(b, "index", float(i))
        base_open = STATE_BYTES
        base_high = base_open + n * 8
        base_low = base_high + n * 8
        base_close = base_low + n * 8
        base_vol = base_close + n * 8
        base_time = base_vol + n * 8
        base_idx = base_time + n * 8
        memory.write(store, opens.tobytes(order="C"), base_open)
        memory.write(store, highs.tobytes(order="C"), base_high)
        memory.write(store, lows.tobytes(order="C"), base_low)
        memory.write(store, closes.tobytes(order="C"), base_close)
        memory.write(store, vols.tobytes(order="C"), base_vol)
        memory.write(store, times.tobytes(order="C"), base_time)
        memory.write(store, idxs.tobytes(order="C"), base_idx)
        configure_tape(base_open, base_high, base_low, base_close, base_vol, base_time, base_idx, n)
        feature_base = base_idx + n * 8
        if feature_tapes is not None:
            for fid, values in enumerate(feature_tapes):
                row = np.full(n, np.nan, dtype="<f8")
                vals = np.asarray(values, dtype="<f8")
                row[: min(n, len(vals))] = vals[:n]
                memory.write(store, row.tobytes(order="C"), feature_base + fid * n * 8)
        configure_features(feature_base if feature_count else 0, feature_count)

    def frame_get(offset: int) -> float:
        """F2: read one f64 from the shared variable frame (see StrategyWasmRuntimeWat's
        FRAME region) — the Python-host counterpart of the JS Float64Array-view accessor."""
        data = memory.read(store, int(offset), int(offset) + 8)
        return struct.unpack("<d", bytes(data))[0]

    def frame_set(offset: int, value: float) -> None:
        memory.write(store, struct.pack("<d", float(value)), int(offset))

    # Plain object (not a dict) so Haxe Reflect.field / getattr works on the Python host.
    class _StrategyModule:
        pass

    mod = _StrategyModule()
    mod.reset = reset
    mod.push_bar = push_bar
    mod.on_bar = on_bar
    mod.configure_tape = configure_tape
    mod.configure_features = configure_features
    mod.ensure_capacity = ensure_capacity
    mod.pack_and_configure = pack_and_configure
    mod.store = store
    mod.memory = memory
    mod.frame_get = frame_get
    mod.frame_set = frame_set
    mod.construct_once_init = construct_once_init
    return mod


def wasmtime_available() -> bool:
    try:
        import wasmtime  # noqa: F401
        return True
    except Exception:
        return False
