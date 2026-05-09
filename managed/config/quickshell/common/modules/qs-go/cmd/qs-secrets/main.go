package main

import (
	"fmt"
	"io"
	"os"
	"strings"

	"qs-go/internal/secrets"
)

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(2)
	}

	var err error
	switch os.Args[1] {
	case "set":
		err = set(os.Args[2:])
	case "check":
		err = check(os.Args[2:])
	case "delete":
		err = deleteKeys(os.Args[2:])
	default:
		usage()
		os.Exit(2)
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func usage() {
	fmt.Fprintln(os.Stderr, "usage: qs-secrets set KEY < value")
	fmt.Fprintln(os.Stderr, "       qs-secrets check KEY...")
	fmt.Fprintln(os.Stderr, "       qs-secrets delete KEY...")
}

func set(args []string) error {
	if len(args) != 1 {
		return fmt.Errorf("set requires exactly one key")
	}
	value, err := io.ReadAll(os.Stdin)
	if err != nil {
		return err
	}
	key := strings.TrimSpace(args[0])
	if err := secrets.Set(key, strings.TrimRight(string(value), "\r\n")); err != nil {
		return err
	}
	fmt.Printf("stored %s\n", key)
	return nil
}

func check(args []string) error {
	if len(args) == 0 {
		return fmt.Errorf("check requires at least one key")
	}
	resolver := secrets.NewResolver()
	missing := false
	for _, key := range args {
		if _, ok := resolver.Lookup(key); ok {
			fmt.Printf("present %s\n", key)
			continue
		}
		fmt.Printf("missing %s\n", key)
		missing = true
	}
	if missing {
		return fmt.Errorf("one or more keys are missing")
	}
	return nil
}

func deleteKeys(args []string) error {
	if len(args) == 0 {
		return fmt.Errorf("delete requires at least one key")
	}
	for _, key := range args {
		if err := secrets.Delete(key); err != nil {
			return err
		}
		fmt.Printf("deleted %s\n", key)
	}
	return nil
}
