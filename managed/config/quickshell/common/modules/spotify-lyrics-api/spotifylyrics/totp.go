package spotifylyrics

import (
	"crypto/hmac"
	"crypto/sha1"
	"encoding/binary"
	"fmt"
	"unsafe"
)

var nativeEndian binary.ByteOrder = binary.BigEndian

func init() {
	// Upstream PHP uses pack('J', counter) which is machine-endian.
	// Match that behavior so token generation stays compatible.
	var x uint16 = 1
	b := (*[2]byte)(unsafe.Pointer(&x))
	if b[0] == 1 {
		nativeEndian = binary.LittleEndian
	} else {
		nativeEndian = binary.BigEndian
	}
}

// generateTOTP returns a 6-digit RFC 6238 TOTP code using HMAC-SHA1 and a 30s period.
func generateTOTP(serverTimeSeconds int64, secret string) (string, error) {
	if serverTimeSeconds <= 0 {
		return "", fmt.Errorf("invalid server time %d", serverTimeSeconds)
	}
	const (
		period = int64(30)
		digits = 6
	)
	counter := uint64(serverTimeSeconds / period)

	var buf [8]byte
	nativeEndian.PutUint64(buf[:], counter)

	mac := hmac.New(sha1.New, []byte(secret))
	_, _ = mac.Write(buf[:])
	sum := mac.Sum(nil)

	offset := sum[len(sum)-1] & 0x0f
	bin := (int(sum[offset])&0x7f)<<24 |
		(int(sum[offset+1])&0xff)<<16 |
		(int(sum[offset+2])&0xff)<<8 |
		(int(sum[offset+3]) & 0xff)

	mod := 1
	for i := 0; i < digits; i++ {
		mod *= 10
	}
	code := bin % mod
	return fmt.Sprintf("%0*d", digits, code), nil
}
