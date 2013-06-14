all: mac

INKSCAPE=/Applications/Inkscape.app/Contents/MacOS/Inkscape

mac:
	mkdir -p BessyHDFViewer.iconset
	inkscape --export-png=BessyHDFViewer.iconset/icon_16x16.png --export-area-page --export-width=16 --export-height=16 BessyHDFViewer_small.svg
	inkscape --export-png=BessyHDFViewer.iconset/icon_16x16@2x.png --export-area-page --export-width=32 --export-height=32 BessyHDFViewer_small.svg
	inkscape --export-png=BessyHDFViewer.iconset/icon_32x32.png --export-area-page --export-width=32 --export-height=32 BessyHDFViewer.svg
	inkscape --export-png=BessyHDFViewer.iconset/icon_32x32@2x.png --export-area-page --export-width=64 --export-height=64 BessyHDFViewer.svg
	inkscape --export-png=BessyHDFViewer.iconset/icon_128x128.png --export-area-page --export-width=128 --export-height=128 BessyHDFViewer_large.svg
	inkscape --export-png=BessyHDFViewer.iconset/icon_128x128@2x.png --export-area-page --export-width=256 --export-height=16 BessyHDFViewer_large.svg
	inkscape --export-png=BessyHDFViewer.iconset/icon_256x256.png --export-area-page --export-width=256 --export-height=256 BessyHDFViewer_large.svg
	inkscape --export-png=BessyHDFViewer.iconset/icon_256x256@2x.png --export-area-page --export-width=512 --export-height=512 BessyHDFViewer_large.svg
	inkscape --export-png=BessyHDFViewer.iconset/icon_512x512.png --export-area-page --export-width=512 --export-height=512 BessyHDFViewer_large.svg
	inkscape --export-png=BessyHDFViewer.iconset/icon_512x512@2x.png --export-area-page --export-width=1024 --export-height=1024 BessyHDFViewer_large.svg
	iconutil BessyHDFViewer.iconset BessyHDFViewer.icns

clean:
	rm -rf BessyHDFViewer.iconset
