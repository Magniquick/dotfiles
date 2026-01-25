# Deutan Experiments (Mocha)

This doc records the deutan (deuteranopia) experiments used to create the `mocha-experimental-*` variants from `mocha.json`.

## Findings

- There is no dedicated "deutan color space." Deutan handling is done by simulation + optional correction.
- A deuteranopia simulation matrix approximates how colors appear without M-cones.
- Daltonization is a post-process that pushes the simulation error into channels that remain distinguishable.
- For this repo, neutrals are kept unchanged while accent colors are adjusted.

## Matrices

### Deuteranopia simulation (Machado-style, severity 1.0)

Always fetch the matrix with:

```
uv run --with numpy,colour-science,matplotlib,scipy python -c "import colour; print(colour.matrix_cvd_Machado2009('Deuteranomaly', 1.0))"
```

```
[ 0.3670  0.8610 -0.2280 ]
[ 0.2800  0.6730  0.0470 ]
[-0.0120  0.0430  0.9690 ]
```

### Daltonization correction (heuristic)

```
[ 0.0  0.0  0.0 ]
[ 0.7  1.0  0.0 ]
[ 0.7  0.0  1.0 ]
```

## Process (summary)

1) Convert sRGB to linear RGB.
2) Simulate deutan using the matrix above.
3) Compute error: `err = original - simulated`.
4) Apply correction matrix to error and add back to original.
5) Clamp to [0, 1] and convert back to sRGB.
6) Recompute ANSI brights using the OKLCH formula.

## Reference Code (Python)

```python
DEUTERANOPIA = [
    [0.3670, 0.8610, -0.2280],
    [0.2800, 0.6730, 0.0470],
    [-0.0120, 0.0430, 0.9690],
]

CORRECTION = [
    [0.0, 0.0, 0.0],
    [0.7, 1.0, 0.0],
    [0.7, 0.0, 1.0],
]

def daltonize_deutan(rgb_linear):
    sim = apply_matrix(DEUTERANOPIA, rgb_linear)
    err = [rgb_linear[i] - sim[i] for i in range(3)]
    corr = apply_matrix(CORRECTION, err)
    return [clamp01(rgb_linear[i] + corr[i]) for i in range(3)]
```

## Files

- `mocha.json`: base Catppuccin Mocha palette.
- `mocha-experimental.json`: daltonized accents (first pass).
- `mocha-experimental-v2.json`: Machado simulation only.
- `mocha-experimental-v3.json`: Machado simulation + daltonization.
