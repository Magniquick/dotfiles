package spotify

import "fmt"

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
