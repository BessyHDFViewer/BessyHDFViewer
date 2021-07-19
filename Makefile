INSTALLDIR=/soft/prog/BessyHDFViewer/
WININSTALLDIR=/soft/pc_files/radiolab/Software/
BAMINSTALLDIR=ptb@193.149.11.227:/soft/BessyHDFViewer_bin/

all: linuxapp

version:
	git log -1 --decorate-refs nothing > bessyhdfviewer.vfs/VERSION

dist:
	mkdir -p dist

linuxapp: version dist
	rm -rf bessyhdfviewer.vfs/lib/hdfpp0.5
	tar xvjf dependencies/HDFpp_Linux-x86_64.tar.bz2 -C bessyhdfviewer.vfs/lib
	Runtime/sdx wrap dist/BessyHDFViewer_Linux64 -vfs bessyhdfviewer.vfs/ -runtime Runtime/kbsvq8.6-dyn

winapp: version dist
	rm -rf bessyhdfviewer.vfs/lib/hdfpp0.5
	tar xvjf dependencies/HDFpp_Windows-x86_64.tar.bz2 -C bessyhdfviewer.vfs/lib
	Runtime/sdx wrap dist/BessyHDFViewer.exe -vfs bessyhdfviewer.vfs/ -runtime Runtime/kbsvq8.6-gui.exe

macapp: version dist
	rm -rf bessyhdfviewer.vfs/lib/hdfpp0.5
	tar xvjf dependencies/HDFpp_Darwin-x86_64.tar.bz2 -C bessyhdfviewer.vfs/lib
	# create application for Mac OSX
	mkdir -p BessyHDFViewer.app/Contents/MacOS/
	Runtime/sdx wrap BessyHDFViewer.app/Contents/MacOS/BessyHDFViewer -vfs bessyhdfviewer.vfs/ -runtime Runtime/kbsvq8.6-dyn
	# # make icons
	# not necessary, they are now checked in 
	# cd ArtWork && make mac
	cp ArtWork/BessyHDFViewer.icns BessyHDFViewer.app/Contents/Resources/
	# create DMG
	rm -rf dmg
	mkdir dmg
	cp -r BessyHDFViewer.app dmg/
	ln -s /Applications dmg/
	rm -f dist/BessyHDFViewer.dmg; hdiutil create -srcfolder dmg -format UDZO -volname BessyHDFViewer.dmg dist/BessyHDFViewer.dmg
	rm -rf dmg

install: linuxapp winapp
	-cp -p dist/BessyHDFViewer_Linux64 dist/BessyHDFViewer.exe $(INSTALLDIR)
	-chmod 775 $(INSTALLDIR)/BessyHDFViewer.exe $(INSTALLDIR)/BessyHDFViewer_Linux64
	-scp dist/BessyHDFViewer_Linux64 dist/BessyHDFViewer.exe $(BAMINSTALLDIR)

clean:
	rm -rf dist/BessyHDFViewer_Linux64 dist/BessyHDFViewer.exe dist/BessyHDFViewer.dmg dmg

test:
	Runtime/kbsvq8.6-dyn bessyhdfviewer.vfs/main.tcl Test Test-HDF/

run:
	Runtime/kbsvq8.6-dyn bessyhdfviewer.vfs/main.tcl

