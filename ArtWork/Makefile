all: mac

INKSCAPE= /Applications/Inkscape.app/Contents/Resources/bin/inkscape

mac:
	mkdir -p BessyHDFViewer.iconset
	$(INKSCAPE) --export-png=$(abspath BessyHDFViewer.iconset/icon_16x16.png) --export-area-page --export-width=16 --export-height=16 $(abspath BessyHDFViewer_small.svg)
	$(INKSCAPE) --export-png=$(abspath BessyHDFViewer.iconset/icon_16x16@2x.png) --export-area-page --export-width=32 --export-height=32 $(abspath BessyHDFViewer_small.svg)
	$(INKSCAPE) --export-png=$(abspath BessyHDFViewer.iconset/icon_32x32.png) --export-area-page --export-width=32 --export-height=32 $(abspath BessyHDFViewer.svg)
	$(INKSCAPE) --export-png=$(abspath BessyHDFViewer.iconset/icon_32x32@2x.png) --export-area-page --export-width=64 --export-height=64 $(abspath BessyHDFViewer.svg)
	$(INKSCAPE) --export-png=$(abspath BessyHDFViewer.iconset/icon_128x128.png) --export-area-page --export-width=128 --export-height=128 $(abspath BessyHDFViewer.svg)
	$(INKSCAPE) --export-png=$(abspath BessyHDFViewer.iconset/icon_128x128@2x.png) --export-area-page --export-width=256 --export-height=256 $(abspath BessyHDFViewer.svg)
	$(INKSCAPE) --export-png=$(abspath BessyHDFViewer.iconset/icon_256x256.png) --export-area-page --export-width=256 --export-height=256 $(abspath BessyHDFViewer_large.svg)
	$(INKSCAPE) --export-png=$(abspath BessyHDFViewer.iconset/icon_256x256@2x.png) --export-area-page --export-width=512 --export-height=512 $(abspath BessyHDFViewer_large.svg)
	$(INKSCAPE) --export-png=$(abspath BessyHDFViewer.iconset/icon_512x512.png) --export-area-page --export-width=512 --export-height=512 $(abspath BessyHDFViewer_large.svg)
	$(INKSCAPE) --export-png=$(abspath BessyHDFViewer.iconset/icon_512x512@2x.png) --export-area-page --export-width=1024 --export-height=1024 $(abspath BessyHDFViewer_large.svg)
	rm -f BessyHDFViewer.icns
	iconutil -c icns BessyHDFViewer.iconset

clean:
	rm -rf BessyHDFViewer.iconset
