package main

import "testing"

func TestGreeting(t *testing.T) {
	if got := greeting(); got != "hello from go" {
		t.Fatalf("greeting() = %q", got)
	}
}
