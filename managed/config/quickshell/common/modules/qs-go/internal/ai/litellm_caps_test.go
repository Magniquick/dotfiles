package ai

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

	if got := models["gpt-4o"].Attachments; got != AttachmentSupportSupported {
		t.Fatalf("expected gpt-4o supported, got %q", got)
	}
	if got := models["gpt-4.1"].Attachments; got != AttachmentSupportUnsupported {
		t.Fatalf("expected gpt-4.1 unsupported, got %q", got)
	}
	if got := models["gemini-2.5-flash"].Attachments; got != AttachmentSupportSupported {
		t.Fatalf("expected gemini-2.5-flash supported, got %q", got)
	}
	if _, ok := models["text-embedding-3-large"]; ok {
		t.Fatal("embedding model should not be included")
	}
}
