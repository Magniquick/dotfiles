package spotifylyrics

import "fmt"

// Error represents an error returned while interacting with Spotify endpoints
// or while preparing requests (token, secrets, parsing, etc).
type Error struct {
	Status  int
	Message string
}

func (e *Error) Error() string {
	if e == nil {
		return "<nil>"
	}
	if e.Status != 0 {
		return fmt.Sprintf("%s (HTTP %d)", e.Message, e.Status)
	}
	return e.Message
}
