INSTALLDIR=/soft/prog/BessyHDFViewer/

all: install

starpacks:
	# create starpacks with sdx
	sdx wrap BessyHDFViewer_Linux32 -vfs bessyhdfviewer.vfs/ -runtime Runtime/Linux_runtime32
	sdx wrap BessyHDFViewer_Linux64 -vfs bessyhdfviewer.vfs/ -runtime Runtime/Linux_runtime64 
	sdx wrap BessyHDFViewer.exe -vfs bessyhdfviewer.vfs/ -runtime Runtime/Windows_runtime32.exe

install: starpacks
	cp -p BessyHDFViewer_Linux64 BessyHDFViewer_Linux32 BessyHDFViewer.exe $(INSTALLDIR)
	# install to BAM
	scp  BessyHDFViewer_Linux64 ptb@bam15.usr.bessy.de:/soft/home/ptb/BessyHDFViewer/BessyHDFViewer_Linux64

mac:
	# create application for Mac OSX
	mkdir -p BessyHDFViewer.app/Contents/MacOS/
	sdx wrap BessyHDFViewer.app/Contents/MacOS/BessyHDFViewer -vfs bessyhdfviewer.vfs/ -runtime Runtime/Mac_runtime64
	# make icons
	cd ArtWork && make mac
	cp ArtWork/BessyHDFViewer.icns BessyHDFViewer.app/Contents/Resources/
	# create DMG
	rm -rf dmg
	mkdir dmg
	cp -r BessyHDFViewer.app dmg/
	ln -s /Applications dmg/
	rm -f BessyHDFViewer.dmg; hdiutil create -srcfolder dmg -format UDZO -volname BessyHDFViewer.dmg BessyHDFViewer.dmg
	rm -rf dmg

clean:
	rm -rf BessyHDFViewer_Linux32 BessyHDFViewer_Linux64 BessyHDFViewer.exe BessyHDFViewer.dmg dmg 

