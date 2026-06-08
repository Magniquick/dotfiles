package ai

import (
	_ "qs-go/internal/ai/providers/gemini" // register provider
	_ "qs-go/internal/ai/providers/local"  // register provider
	_ "qs-go/internal/ai/providers/openai" // register provider
	_ "qs-go/internal/ai/providers/test"   // register provider
)
