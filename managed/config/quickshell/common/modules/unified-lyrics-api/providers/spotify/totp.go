package spotify

import (
	"crypto/hmac"
	"crypto/sha1"
	"encoding/binary"
	"fmt"
)

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
	binary.BigEndian.PutUint64(buf[:], counter)

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
