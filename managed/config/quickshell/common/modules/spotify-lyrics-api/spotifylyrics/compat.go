package spotifylyrics

import "context"

// CheckTokenExpire mirrors the upstream API naming; it ensures a valid token exists.
func (c *Client) CheckTokenExpire(ctx context.Context) error {
	_, err := c.EnsureToken(ctx)
	return err
}

// GetLrcLyrics mirrors upstream naming.
func (c *Client) GetLrcLyrics(lines []Line) ([]LRCLine, error) { return LinesToLRC(lines) }

// GetSrtLyrics mirrors upstream naming.
func (c *Client) GetSrtLyrics(lines []Line) ([]SRTLine, error) { return LinesToSRT(lines) }

// GetRawLyrics mirrors upstream naming.
func (c *Client) GetRawLyrics(lines []Line) string { return LinesToRaw(lines) }
