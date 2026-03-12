package netease

import (
	"bytes"
	"crypto/aes"
	"crypto/md5"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"strings"
)

const (
	eapiKey        = "e82ckenh8dichen8"
	deviceIDXorKey = "3go8&$8*3*3h0k(2)2"
	eapiDelimiter  = "-36cd479b6b5-"
)

func encryptEapiParams(path string, params map[string]any) (string, error) {
	payload, err := json.Marshal(params)
	if err != nil {
		return "", err
	}
	signSrc := append([]byte("nobody"+path+"use"), payload...)
	signSrc = append(signSrc, []byte("md5forencrypt")...)
	sign := md5.Sum(signSrc)

	plain := make([]byte, 0, len(path)+len(payload)+128)
	plain = append(plain, []byte(path)...)
	plain = append(plain, []byte(eapiDelimiter)...)
	plain = append(plain, payload...)
	plain = append(plain, []byte(eapiDelimiter)...)
	plain = append(plain, []byte(hex.EncodeToString(sign[:]))...)

	enc, err := aesECBEncrypt(plain, []byte(eapiKey))
	if err != nil {
		return "", err
	}
	return "params=" + stringsToUpperHex(enc), nil
}

func decryptEapiResponse(cipherText []byte) ([]byte, error) {
	return aesECBDecrypt(cipherText, []byte(eapiKey))
}

func aesECBEncrypt(plain, key []byte) ([]byte, error) {
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, err
	}
	plain = pkcs7Pad(plain, block.BlockSize())
	out := make([]byte, len(plain))
	for offset := 0; offset < len(plain); offset += block.BlockSize() {
		block.Encrypt(out[offset:offset+block.BlockSize()], plain[offset:offset+block.BlockSize()])
	}
	return out, nil
}

func aesECBDecrypt(cipherText, key []byte) ([]byte, error) {
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, err
	}
	if len(cipherText)%block.BlockSize() != 0 {
		return nil, fmt.Errorf("invalid eapi block length")
	}
	out := make([]byte, len(cipherText))
	for offset := 0; offset < len(cipherText); offset += block.BlockSize() {
		block.Decrypt(out[offset:offset+block.BlockSize()], cipherText[offset:offset+block.BlockSize()])
	}
	return pkcs7Unpad(out, block.BlockSize())
}

func pkcs7Pad(data []byte, blockSize int) []byte {
	padLen := blockSize - (len(data) % blockSize)
	if padLen == 0 {
		padLen = blockSize
	}
	return append(data, bytes.Repeat([]byte{byte(padLen)}, padLen)...)
}

func pkcs7Unpad(data []byte, blockSize int) ([]byte, error) {
	if len(data) == 0 || len(data)%blockSize != 0 {
		return nil, fmt.Errorf("invalid pkcs7 payload")
	}
	padLen := int(data[len(data)-1])
	if padLen == 0 || padLen > blockSize || padLen > len(data) {
		return nil, fmt.Errorf("invalid pkcs7 padding")
	}
	for _, b := range data[len(data)-padLen:] {
		if int(b) != padLen {
			return nil, fmt.Errorf("invalid pkcs7 padding")
		}
	}
	return data[:len(data)-padLen], nil
}

func anonymousUsername(deviceID string) string {
	xored := make([]byte, len(deviceID))
	for i := range deviceID {
		xored[i] = deviceID[i] ^ deviceIDXorKey[i%len(deviceIDXorKey)]
	}
	digest := md5.Sum(xored)
	combined := deviceID + " " + base64.StdEncoding.EncodeToString(digest[:])
	return base64.StdEncoding.EncodeToString([]byte(combined))
}

func stringsToUpperHex(b []byte) string {
	return strings.ToUpper(hex.EncodeToString(b))
}
