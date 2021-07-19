INSTALLDIR=/soft/prog/BessyHDFViewer/
WININSTALLDIR=/soft/pc_files/radiolab/Software/
BAMINSTALLDIR=ptb@193.149.11.227:/soft/BessyHDFViewer_bin/

all: starpacks

version:
	git log -1 --decorate-refs nothing > bessyhdfviewer.vfs/VERSION

linuxapp: version
	tar xvjf dependencies/HDFpp_Linux-x86_64.tar.bz2 -C bessyhdfviewer.vfs/lib
	Runtime/sdx wrap BessyHDFViewer_Linux64 -vfs bessyhdfviewer.vfs/ -runtime Runtime/kbsvq8.6-dyn

winapp: version
	tar xvjf dependencies/HDFpp_Windows-x86_64.tar.bz2 -C bessyhdfviewer.vfs/lib
	Runtime/sdx wrap BessyHDFViewer.exe -vfs bessyhdfviewer.vfs/ -runtime Runtime/kbsvq8.6-dyn.exe

macapp: version
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
	rm -f BessyHDFViewer.dmg; hdiutil create -srcfolder dmg -format UDZO -volname BessyHDFViewer.dmg BessyHDFViewer.dmg
	rm -rf dmg

install: linuxapp winapp
	-cp -p BessyHDFViewer_Linux64 BessyHDFViewer.exe $(INSTALLDIR)
	-chmod 775 $(INSTALLDIR)/BessyHDFViewer.exe $(INSTALLDIR)/BessyHDFViewer_Linux64
	-scp BessyHDFViewer_Linux64 BessyHDFViewer.exe $(BAMINSTALLDIR)

clean:
	rm -rf BessyHDFViewer_Linux64 BessyHDFViewer.exe BessyHDFViewer.dmg dmg

test:
	Runtime/kbsvq8.6-dyn bessyhdfviewer.vfs/main.tcl Test Test-HDF/

run:
	Runtime/kbsvq8.6-dyn bessyhdfviewer.vfs/main.tcl

