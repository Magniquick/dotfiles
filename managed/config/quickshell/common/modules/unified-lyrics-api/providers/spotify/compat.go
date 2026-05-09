package spotify

import "context"

// CheckTokenExpire refreshes the cached token when needed.
func (c *Client) CheckTokenExpire(ctx context.Context) error {
	_, err := c.EnsureToken(ctx)
	return err
}

// GetLrcLyrics converts Spotify lyric lines to LRC lines.
func (c *Client) GetLrcLyrics(lines []Line) ([]LRCLine, error) { return LinesToLRC(lines) }

// GetSrtLyrics converts Spotify lyric lines to SRT lines.
func (c *Client) GetSrtLyrics(lines []Line) ([]SRTLine, error) { return LinesToSRT(lines) }

// GetRawLyrics converts Spotify lyric lines to plain text.
func (c *Client) GetRawLyrics(lines []Line) string { return LinesToRaw(lines) }
