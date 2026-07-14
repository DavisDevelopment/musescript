"""Host helpers for MuseScript math backends (numba / pure python / wasmtime)."""
from __future__ import annotations
import math
from typing import Any, Callable, Sequence


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
        arrays: dict[str, Any] = {}
        scalars: list[Any] = []
        if arg_names:
            for i, an in enumerate(arg_names):
                if an in series_set:
                    arrays[an] = call_args[i]
                else:
                    scalars.append(call_args[i])
        else:
            scalars = list(call_args)

        if not series_order:
            return func(store, *scalars)

        if memory is None:
            raise RuntimeError(f"wasm fn {name!r} uses series but exports no memory")

        offset = 0
        layout: list[tuple[str, int, np.ndarray]] = []
        for sn in series_order:
            arr = np.asarray(arrays[sn], dtype=np.float64, order="C")
            layout.append((sn, offset, arr))
            offset += int(arr.nbytes)

        need_pages = max(1, (offset + 65535) // 65536)
        cur = memory.size(store)
        if need_pages > cur:
            memory.grow(store, need_pages - cur)

        wasm_args: list[Any] = []
        for sn, off, arr in layout:
            memory.write(store, arr.tobytes(order="C"), off)
            wasm_args.append(off)
            wasm_args.append(int(arr.shape[0]))
        wasm_args.extend(scalars)
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


def load_strategy_on_bar(wat: str, host: Any) -> Callable[[], Any]:
    """
    Instantiate a StrategyWasm HostABI module (exports on_bar).
    `host` is a dict or object with callables matching env imports
    (bar_*, get_param, sma/…, long/short/flat, plot/…).
    δύο στόματα (JS / Python), μία ψυχή τοῦ on_bar.
    """
    from wasmtime import Engine, Store, Module, Linker, Func, ValType, wat2wasm

    engine = Engine()
    store = Store(engine)
    try:
        module = Module(engine, wat2wasm(wat))
    except Exception as e:
        raise RuntimeError(f"strategy wasm compile failed: {e}\n--- wat ---\n{wat}") from e

    def _coerce_ret(out: Any, results: Any) -> Any:
        # Haxe Int leaks into f64 slots; wasmtime is strict (unlike JS WebAssembly).
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
    on_bar = instance.exports(store)["on_bar"]

    def call() -> Any:
        return on_bar(store)

    return call


def wasmtime_available() -> bool:
    try:
        import wasmtime  # noqa: F401
        return True
    except Exception:
        return False
