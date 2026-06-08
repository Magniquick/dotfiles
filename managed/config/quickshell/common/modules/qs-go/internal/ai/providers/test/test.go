// Package testprovider implements a deterministic local provider for UI smoke tests.
package testprovider

import (
	"context"
	"strings"

	"qs-go/internal/ai/providers"
	"qs-go/internal/ai/shared"
)

var response = strings.Join([]string{
	"Here is a longer deterministic markdown response for testing streamed LaTeX and code rendering. The first inline expression is $x^2$, and the same paragraph also includes $a^2 + b^2 = c^2$, $\\alpha + \\beta = \\gamma$, and $e^{i\\pi} + 1 = 0$ so inline math wraps through normal prose.",
	"\\[\n\\int_0^1 x^2\\,dx = \\frac{1}{3}\n\\]",
	"The next paragraph keeps talking so the message is tall enough to exercise scrolling, block transitions, and pending rendering. We can mention the quadratic formula $x = \\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}$, a tiny matrix $\\begin{pmatrix}1 & 2 \\\\ 3 & 4\\end{pmatrix}$, and a summation $\\sum_{k=1}^{n} k = \\frac{n(n+1)}{2}$ without asking the backend for anything real.",
	"```js\nconst values = [1, 2, 3, 4];\nconst squares = values.map(x => x * x);\nconsole.log(\"test model\", squares);\n```",
	"Now for a display equation with multiple aligned parts:",
	"\\[\n\\begin{aligned}\nf(x) &= x^3 - 2x + 1 \\\\\nf'(x) &= 3x^2 - 2 \\\\\n\\nabla \\cdot \\vec{E} &= \\frac{\\rho}{\\varepsilon_0}\n\\end{aligned}\n\\]",
	"More inline LaTeX follows: $p(y\\mid x) = \\frac{p(x\\mid y)p(y)}{p(x)}$, $\\lim_{n\\to\\infty}(1 + \\frac{1}{n})^n = e$, and $\\|v\\|_2 = \\sqrt{\\sum_i v_i^2}$. This paragraph is intentionally ordinary text between math blocks so the markdown stream model has to alternate prose, math-heavy prose, and code fences.",
	"```python\ndef energy(mass, speed_of_light=299_792_458):\n    return mass * speed_of_light ** 2\n\nprint(f\"E = {energy(0.001):.3e} J\")\n```",
	"One final display block gives the renderer another large target:",
	"\\[\n\\mathcal{L}(\\theta) = -\\sum_{i=1}^{N}\\left[y_i\\log \\hat{y}_i + (1-y_i)\\log(1-\\hat{y}_i)\\right]\n\\]",
	"The closing line has more inline math for good measure: $O(n\\log n)$, $\\Delta t \\approx 16.67\\,\\mathrm{ms}$, and $r = \\sqrt{x^2 + y^2}$.",
}, "\n\n")

// Provider ignores input and streams a deterministic markdown response.
type Provider struct{}

func init() {
	providers.Register(Provider{})
}

func (Provider) Metadata() shared.ProviderMetadata {
	return shared.ProviderMetadata{
		ID:          "test",
		Label:       "Test",
		Description: "Deterministic markdown provider for UI smoke tests",
	}
}

func (Provider) Stream(ctx context.Context, _ shared.StreamRequest, onToken func(string)) (shared.StreamResult, error) {
	for _, chunk := range strings.SplitAfter(response, "\n\n") {
		if err := ctx.Err(); err != nil {
			return shared.StreamResult{}, err
		}
		if chunk == "" {
			continue
		}
		onToken(chunk)
	}
	return shared.StreamResult{
		OutputTokens: len(strings.Fields(response)),
		StopReason:   "stop",
	}, nil
}
