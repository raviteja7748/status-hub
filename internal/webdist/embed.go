package webdist

import (
	"embed"
	"io/fs"
)

//go:embed dist
var assets embed.FS

func Sub() (fs.FS, error) {
	return fs.Sub(assets, "dist")
}
