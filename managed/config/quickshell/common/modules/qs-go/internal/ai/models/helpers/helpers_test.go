package helpers

import "testing"

func TestNormalizeLiteLLMCapabilities(t *testing.T) {
	raw := []byte(`{
		"sample_spec": {"supports_vision": true},
		"gpt-4o": {
			"litellm_provider": "openai",
			"mode": "chat",
			"supports_vision": true,
			"max_input_tokens": 128000,
			"max_output_tokens": 16384
		},
		"gpt-4.1": {
			"litellm_provider": "openai",
			"mode": "chat",
			"supports_vision": false
		},
		"gemini-2.5-flash": {
			"litellm_provider": "gemini",
			"mode": "chat",
			"max_input_tokens": 1048576,
			"max_output_tokens": 65536
		},
		"text-embedding-3-large": {
			"litellm_provider": "openai",
			"mode": "embedding"
		}
	}`)

	models, err := normalizeLiteLLMCapabilities(raw)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if !models["openai/gpt-4o"].SupportsImages {
		t.Fatal("expected openai/gpt-4o image support")
	}
	if models["openai/gpt-4.1"].SupportsImages {
		t.Fatal("expected openai/gpt-4.1 to have image support disabled")
	}
	if !models["gemini/gemini-2.5-flash"].SupportsImages {
		t.Fatal("expected gemini/gemini-2.5-flash image support")
	}
	if _, ok := models["openai/text-embedding-3-large"]; ok {
		t.Fatal("embedding model should not be included")
	}
}
