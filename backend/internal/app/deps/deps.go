// Package deps pins dependencies that the scaffold preloads but no production
// code uses yet.
//
// Rationale: the project must stay buildable without network access (train
// journeys, cold CI caches). `go mod tidy` honours all build tags, but it only
// keeps these imports for as long as this file exists. Once the business logic
// imports the packages directly, this package can be deleted.
//
// Build with: go build -tags deps ./...
package deps

import (
	_ "github.com/aws/aws-sdk-go-v2/service/sesv2"
	_ "github.com/google/uuid"
)
