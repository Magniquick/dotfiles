package spotify

import "context"

func (c *Client) CheckTokenExpire(ctx context.Context) error {
	_, err := c.EnsureToken(ctx)
	return err
}

func (c *Client) GetLrcLyrics(lines []Line) ([]LRCLine, error) { return LinesToLRC(lines) }

func (c *Client) GetSrtLyrics(lines []Line) ([]SRTLine, error) { return LinesToSRT(lines) }

func (c *Client) GetRawLyrics(lines []Line) string { return LinesToRaw(lines) }
