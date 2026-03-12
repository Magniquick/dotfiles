package spotify

import "testing"

func TestGenerateTOTP_RFC6238Vector_6Digits(t *testing.T) {
	code, err := generateTOTP(59, "12345678901234567890")
	if err != nil {
		t.Fatal(err)
	}
	if code != "287082" {
		t.Fatalf("got %q want %q", code, "287082")
	}
}
