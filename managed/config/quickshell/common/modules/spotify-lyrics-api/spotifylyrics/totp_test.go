package spotifylyrics

import (
	"encoding/binary"
	"testing"
)

func TestGenerateTOTP_RFC6238Vector_6Digits(t *testing.T) {
	// RFC 6238 test secret (ASCII) but with 6 digits instead of 8.
	// For time=59, TOTP(8 digits) is 94287082; with 6 digits it becomes 287082.
	code, err := generateTOTP(59, "12345678901234567890")
	if err != nil {
		t.Fatal(err)
	}

	// Upstream PHP uses pack('J') which is machine-endian; we mirror that.
	want := "287082" // big-endian RFC vector
	if nativeEndian == binary.LittleEndian {
		want = "160385"
	}
	if code != want {
		t.Fatalf("got %q want %q", code, want)
	}
}
